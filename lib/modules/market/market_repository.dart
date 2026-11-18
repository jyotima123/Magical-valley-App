import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and writes Market categories and items, plus the signed-in user's
/// own cars for My Listings (browsing cars stays with the vehicle providers).
/// Messaging goes through [ApiRepository] like every other inquiry.
///
/// Access rules live in RLS (migration 080): anyone signed in can read and
/// list, only the author can edit or mark sold. Nothing here re-checks them.
class MarketRepository {
  MarketRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// The signed-in user, who owns — and so may edit — their own items.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Every visible category, Cars & Trucks included, in display order.
  Future<List<MarketCategory>> fetchCategories() async {
    final rows = await _client
        .from('market_categories')
        .select()
        .eq('is_active', true)
        // postgrest-dart sorts descending unless told otherwise.
        .order('sort_order', ascending: true);
    return (rows as List)
        .map((e) => MarketCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// One page of a category, newest first. A sold item stays in the results,
  /// shown as sold, for 24h after the sale, then clears (sold_at is set by the
  /// market_items_sold_at trigger, 090), as on the Cars screen.
  ///
  /// Community listings only: a shelter animal someone has messaged about is
  /// mirrored into market_items (088), but the live feed is what lists it.
  Future<List<MarketItem>> fetchItems({
    required String category,
    String search = '',
    required int offset,
    required int limit,
  }) async {
    final soldCutoff =
        DateTime.now().toUtc().subtract(const Duration(hours: 24));
    // An item shows under both of its categories. Two .or() calls AND
    // together: (either category) AND (unsold or sold within 24h).
    var query = _client
        .from('market_items')
        .select()
        .eq('source', 'community')
        .or('category.eq.$category,secondary_category.eq.$category')
        .or('is_sold.eq.false,sold_at.gt.${soldCutoff.toIso8601String()}');
    final term = search.trim();
    if (term.isNotEmpty) {
      query = query.ilike('title', '%${_escapeLike(term)}%');
    }
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map((e) => MarketItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// A category's currently promoted items, the most recently promoted first.
  /// Sold items drop out: the carousel is for things that can still be had.
  Future<List<MarketItem>> fetchPromoted({required String category}) async {
    final rows = await _client
        .from('market_items')
        .select()
        .eq('source', 'community')
        .eq('is_sold', false)
        .gt('promoted_until', DateTime.now().toUtc().toIso8601String())
        .or('category.eq.$category,secondary_category.eq.$category')
        .order('promoted_until', ascending: false)
        .limit(20);
    return (rows as List)
        .map((e) => MarketItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Promotes [id] until [until], or ends its promotion when null. Refused by
  /// the database for anyone but a superadmin (089).
  Future<void> setPromotion(String id, DateTime? until) =>
      updateItem(id, {'promoted_until': until?.toUtc().toIso8601String()});

  /// Whether the signed-in user may promote listings.
  Future<bool> isSuperadmin() async {
    final userId = currentUserId;
    if (userId == null) return false;
    try {
      final row = await _client
          .from('user_profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      return row?['role'] == 'superadmin';
    } catch (_) {
      return false;
    }
  }

  Future<MarketItem> fetchItem(String id) async {
    final row = await _client
        .from('market_items')
        .select()
        .eq('id', id)
        .single();
    return MarketItem.fromJson(row);
  }

  /// Lists a new item as the signed-in user.
  Future<void> createItem(Map<String, dynamic> fields) async {
    await _client.from('market_items').insert({
      ...fields,
      'created_by': currentUserId,
    });
  }

  Future<void> updateItem(String id, Map<String, dynamic> fields) async {
    await _client.from('market_items').update(fields).eq('id', id);
  }

  Future<void> setSold(String id, {required bool sold}) =>
      updateItem(id, {'is_sold': sold});

  /// Everything [userId] has listed outside Cars & Trucks, sold or not,
  /// newest first. One person's listings are few enough not to page.
  Future<List<MarketItem>> fetchItemsBy(String userId) async {
    final rows = await _client
        .from('market_items')
        .select()
        .eq('created_by', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => MarketItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cars [userId] listed in the app, newest first. Dealer inventory is never
  /// theirs: it has no author, and is excluded by source as well so that a
  /// vendor's car can never be offered for editing. Sold listings stay here
  /// indefinitely — unlike the Cars tab, this is the creator's own history —
  /// but a deleted one is gone even to them.
  Future<List<VehicleListing>> fetchVehiclesBy(String userId) async {
    final rows = await _client
        .from('vehicle_listings')
        .select()
        .eq('created_by', userId)
        .eq('source', kCommunitySource)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => VehicleListing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setVehicleSold(String id, {required bool sold}) async {
    await _client
        .from('vehicle_listings')
        .update({'is_sold': sold})
        .eq('id', id);
  }

  /// Soft delete: a real DELETE would cascade away the buyers' conversations
  /// about this car (vehicle_inquiry_conversations.vehicle_id, 073/085), so
  /// this only marks it removed and every list query filters it out instead.
  Future<void> deleteVehicle(String id) async {
    await _client
        .from('vehicle_listings')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id);
  }

  /// A search for "50%" should find "50% off", not everything: `%`, `_` and
  /// the escape character itself are literal in the user's text.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
