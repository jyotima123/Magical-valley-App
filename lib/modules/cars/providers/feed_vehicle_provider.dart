import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A vendor that delivers inventory as a file rather than serving an API.
///
/// The ingest function has already parsed and normalized these rows, so unlike
/// a live provider there is no vendor-specific mapping left to do at read time —
/// which is why one class covers every file-delivered vendor. What differs per
/// vendor lives server-side, in that vendor's mapper.
///
/// [sources] is every dealership this vendor exports for, from `dealer_sources`.
class FeedVehicleProvider implements VehicleProvider {
  @override
  final String providerKey;

  @override
  final String displayName;

  final List<String> sources;

  const FeedVehicleProvider({
    required this.providerKey,
    required this.displayName,
    required this.sources,
  });

  @override
  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false}) async {
    if (sources.isEmpty) return const [];

    // Sold vehicles are off the dealership's lot: either the file said so, or
    // reconciliation found them missing from the latest delivery. Community
    // listings keep showing when sold, because there a sale is part of the
    // seller's own history; a vendor's inventory has no such story to tell.
    final rows = await Supabase.instance.client
        .from('vehicle_listings')
        .select()
        .inFilter('source', sources)
        .eq('is_sold', false)
        .order('updated_at', ascending: false);

    return (rows as List)
        .map((e) => VehicleListing.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
