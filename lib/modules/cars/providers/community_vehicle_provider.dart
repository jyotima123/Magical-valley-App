import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listings people posted in the app. Not a vendor integration, but it reaches
/// the same list through the same interface, so the Cars tab has one code path
/// instead of a special case.
class CommunityVehicleProvider implements VehicleProvider {
  @override
  String get providerKey => kCommunitySource;

  @override
  String get displayName => 'Community';

  @override
  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false}) async {
    // A sold listing stays in this shared list for a day so a just-missed
    // buyer still sees it, then clears on its own rather than sitting here
    // indefinitely; sold_at is set by the vehicle_listings_sold_at trigger
    // (085), not the app, so it can't drift. The creator's own copy keeps
    // showing in My Listings regardless — this filter is this list only.
    final soldCutoff =
        DateTime.now().toUtc().subtract(const Duration(hours: 24));
    final rows = await Supabase.instance.client
        .from('vehicle_listings')
        .select()
        .eq('source', kCommunitySource)
        .isFilter('deleted_at', null)
        .or('is_sold.eq.false,sold_at.gt.${soldCutoff.toIso8601String()}')
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => VehicleListing.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
