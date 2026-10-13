import 'package:mvc_app/modules/cars/liftkit_api_service.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// LiftKit, pulled live over JSON at read time.
///
/// The transport and the field mapping stay where they were, in
/// [LiftKitApiService] and [LiftKitVehicleMapper]; this only adapts them to the
/// common interface. A live provider keeps its own in-memory cache, so
/// [forceRefresh] has to reach it rather than being handled generically.
class LiftKitVehicleProvider implements VehicleProvider {
  final LiftKitApiService _service;

  LiftKitVehicleProvider({LiftKitApiService? service})
      : _service = service ?? LiftKitApiService();

  @override
  String get providerKey => 'liftkit';

  @override
  String get displayName => 'LiftKit';

  @override
  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false}) {
    return _service.fetchVehicles(forceRefresh: forceRefresh);
  }
}
