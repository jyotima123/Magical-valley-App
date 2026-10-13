import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:mvc_app/modules/chat/models/organization_model.dart';

/// Lightweight local cache using SharedPreferences for organizations per category
/// and the latest category counts map. This avoids heavy dependencies while
/// giving us fast reads for stable data that changes infrequently.
class LocalCacheService {
  LocalCacheService._internal();
  static final LocalCacheService instance = LocalCacheService._internal();

  static const String _categoryCountsKey = 'category_counts_map_v1';
  static const String _orgsCachePrefix = 'orgs_cache_v1_'; // + categoryIdOrAll
  static const String _orgsCacheCountPrefix = 'orgs_cache_count_v1_';
  static const String _orgsCacheUpdatedAtPrefix = 'orgs_cache_updated_at_v1_';

  String _categoryKey(String? categoryId) =>
      '$_orgsCachePrefix${categoryId ?? 'all'}';
  String _categoryCountKey(String? categoryId) =>
      '$_orgsCacheCountPrefix${categoryId ?? 'all'}';
  String _categoryUpdatedAtKey(String? categoryId) =>
      '$_orgsCacheUpdatedAtPrefix${categoryId ?? 'all'}';

  Future<Map<String, int>> getCategoryCountsMap() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_categoryCountsKey);
    if (jsonString == null) return {};
    try {
      final Map<String, dynamic> map = json.decode(jsonString);
      return map.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> setCategoryCountsMap(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_categoryCountsKey, json.encode(counts));
  }

  Future<List<Organization>?> getOrganizationsForCategory(
    String? categoryId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_categoryKey(categoryId));
    if (jsonString == null) return null;
    try {
      final List<dynamic> list = json.decode(jsonString);
      return list.map((e) => _organizationFromCacheJson(e)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> setOrganizationsForCategory(
    String? categoryId,
    List<Organization> organizations,
    int currentCategoryCount,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(
      organizations.map(_organizationToCacheJson).toList(),
    );
    await prefs.setString(_categoryKey(categoryId), encoded);
    await prefs.setInt(_categoryCountKey(categoryId), currentCategoryCount);
    await prefs.setInt(
      _categoryUpdatedAtKey(categoryId),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<int?> getCachedOrganizationsCountForCategory(
    String? categoryId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_categoryCountKey(categoryId));
  }

  Future<DateTime?> getOrganizationsUpdatedAt(String? categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_categoryUpdatedAtKey(categoryId));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Map<String, dynamic> _organizationToCacheJson(Organization org) {
    return {
      'id': org.id,
      'name': org.name,
      'logo_url': org.logoUrl,
      'bio': org.bio,
      'website_url': org.websiteUrl,
      'maps_url': org.mapsUrl,
      'follower_count': org.followerCount,
      'category_ids': org.categoryIds,
      'phone_numbers': org.phoneNumbers
          .map((p) => {
                'id': p.id,
                'label': p.label,
                'phone_number': p.phoneNumber,
              })
          .toList(),
      'addresses': org.addresses
          .map((a) => {
                'id': a.id,
                'label': a.label,
                'street': a.street,
                'city': a.city,
                'state': a.state,
                'country': a.country,
                'postal_code': a.postalCode,
                'latitude': a.latitude,
                'longitude': a.longitude,
                'maps_url': a.mapsUrl,
              })
          .toList(),
      'photos': org.photos
          .map((p) => {
                'id': p.id,
                'photo_url': p.photoUrl,
                'caption': p.caption,
              })
          .toList(),
      'created_at': org.createdAt.toUtc().toIso8601String(),
      'updated_at': org.updatedAt.toUtc().toIso8601String(),
      'is_following': org.isFollowing,
    };
  }

  Organization _organizationFromCacheJson(dynamic jsonMap) {
    final map = Map<String, dynamic>.from(jsonMap as Map);
    return Organization.fromJson(map);
  }

  /// Clear cache for a specific category
  Future<void> clearOrganizationsCacheForCategory(String? categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_categoryKey(categoryId));
    await prefs.remove(_categoryCountKey(categoryId));
    await prefs.remove(_categoryUpdatedAtKey(categoryId));
  }

  /// Clear all organization caches (for all categories)
  Future<void> clearAllOrganizationsCache() async {
    final prefs = await SharedPreferences.getInstance();
    // Get all keys and filter for organization cache keys
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith(_orgsCachePrefix) ||
          key.startsWith(_orgsCacheCountPrefix) ||
          key.startsWith(_orgsCacheUpdatedAtPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// Update follow status for organizations in cache for a specific category
  /// This is called after follow/unfollow actions to keep cache in sync
  Future<void> updateFollowStatusInCache(
    String? categoryId,
    Map<String, bool> followStatusMap,
  ) async {
    final cachedOrgs = await getOrganizationsForCategory(categoryId);
    if (cachedOrgs == null || cachedOrgs.isEmpty) return;

    final updatedOrgs = cachedOrgs.map((org) {
      final isFollowing = followStatusMap[org.id] ?? org.isFollowing;
      return org.copyWith(isFollowing: isFollowing);
    }).toList();

    final cachedCount = await getCachedOrganizationsCountForCategory(
      categoryId,
    );
    if (cachedCount != null) {
      await setOrganizationsForCategory(categoryId, updatedOrgs, cachedCount);
    }
  }
}
