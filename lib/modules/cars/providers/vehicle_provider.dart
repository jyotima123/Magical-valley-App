import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// One inventory provider: where a set of vehicles comes from and how to get it.
///
/// Providers are deliberately independent of one another. Each owns its own
/// transport and its own mapping from whatever shape that provider speaks — a
/// JSON API, a table of ingested feed rows — onto the shared [VehicleListing].
/// The shared output is what lets the Cars tab render every provider in one
/// list and behave identically for buyers; the separate input handling is what
/// lets a provider be added or dropped without touching the others.
///
/// Which providers exist at runtime is data, not code: see
/// [VehicleSourceRegistry] and the `dealer_sources` table (migration 078).
abstract class VehicleProvider {
  /// Matches `dealer_sources.provider`.
  String get providerKey;

  /// Operator- and diagnostics-facing. Buyers are shown the dealership, not the
  /// plumbing that carried the vehicle to us.
  String get displayName;

  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false});
}

/// The outcome of asking one provider for its inventory.
///
/// Failure is per-provider and never fatal on its own: a provider that is down
/// contributes an [error] and no vehicles, and the rest of the list still
/// renders. Anything else would mean one vendor's outage empties the Cars tab.
class ProviderFetch {
  final VehicleProvider provider;
  final List<VehicleListing> vehicles;
  final String? error;

  const ProviderFetch({
    required this.provider,
    this.vehicles = const [],
    this.error,
  });

  bool get failed => error != null;
}
