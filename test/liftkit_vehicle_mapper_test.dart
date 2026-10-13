import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/modules/cars/liftkit_api_service.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// Trimmed from a live `GET /api/v1/vehicles` response. The feed nests its
/// fields and uses its own vocabulary, so these cases lock in the normalization
/// the search filters depend on.
const _liftKitVehicle = '''
{
  "vin": "3GCUDHEL5PG205293",
  "stock": "PG205293",
  "year": "2023",
  "make": "Chevrolet",
  "model": "Silverado 1500",
  "trim": "ZR2",
  "type": "Truck",
  "body": "Pickup",
  "color": {"name": "Summit White", "simple": "White", "interior": "Jet Black"},
  "mileage": 17534,
  "description": {"full": "Premier&#039;s <b>Lifetime</b> Powertrain Warranty."},
  "fuel": "Gas",
  "transmission": {"type": "Automatic", "speed": "10", "description": "10-Speed"},
  "doors": 4,
  "drivetrain": "Four Wheel Drive",
  "engine": {"size": "6.2", "cylinders": "8", "name": "6.2L 8 Cyl."},
  "status": "Used",
  "certified": false,
  "pricing": {"original": 59923, "final": 59923},
  "vdpurl": "https://example.com/inventory/1444365",
  "photos": ["https://media.liftkit.io/a.jpg", "https://media.liftkit.io/b.jpg"],
  "vehicle_acquired": 1720681200,
  "key_features": ["Apple CarPlay/Android Auto", "Back-up camera"]
}
''';

VehicleListing _map(String json) =>
    LiftKitVehicleMapper.toListing(jsonDecode(json) as Map<String, dynamic>)!;

void main() {
  group('LiftKitVehicleMapper', () {
    test('maps a feed vehicle onto the app listing shape', () {
      final listing = _map(_liftKitVehicle);

      expect(listing.id, 'liftkit:PG205293');
      expect(listing.stock, 'PG205293');
      expect(listing.vin, '3GCUDHEL5PG205293');
      expect(listing.year, 2023);
      expect(listing.make, 'Chevrolet');
      expect(listing.model, 'Silverado 1500');
      expect(listing.mileage, 17534);
      expect(listing.doors, '4');
      expect(listing.source, 'liftkit');
      expect(listing.externalId, 'liftkit:PG205293');
      expect(listing.isFromDealerFeed, isTrue);
      expect(listing.vdpUrl, 'https://example.com/inventory/1444365');
      expect(listing.images, hasLength(2));
      expect(listing.createdAt.year, 2024);
    });

    test('normalizes feed vocabulary to the app filter options', () {
      final listing = _map(_liftKitVehicle);

      // 'Used' would never match the app's 'Pre-Owned' status chip.
      expect(listing.status, 'Pre-Owned');
      expect(listing.fuel, 'Gasoline');
      expect(listing.transmission, 'Automatic');
      expect(listing.drivetrain, '4WD / 4x4');
      expect(listing.body, 'Pickup Truck');
      // The filter chips are built from the simple colour buckets.
      expect(listing.color, 'White');
      expect(listing.interior, 'Jet Black');
    });

    test('promotes certified vehicles to their own status', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json['certified'] = true;

      expect(
        LiftKitVehicleMapper.toListing(json)!.status,
        'Certified Pre-Owned',
      );
    });

    test('treats every SUV body the feed reports as Wagon as an SUV', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json['type'] = 'SUV';
      json['body'] = 'Wagon';

      expect(LiftKitVehicleMapper.toListing(json)!.body, 'SUV');
    });

    test('strips HTML and entities out of the description', () {
      expect(
        _map(_liftKitVehicle).description,
        "Premier's Lifetime Powertrain Warranty.",
      );
    });

    test('reads a discount as a promotional price', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json['pricing'] = {'original': r'$59,923.00', 'final': 54500};

      final listing = LiftKitVehicleMapper.toListing(json)!;
      expect(listing.price, 59923);
      expect(listing.promotion, 54500);
    });

    test('shows a missing price as "Call for price" rather than zero', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json['pricing'] = {'original': 0, 'final': 0};

      final listing = LiftKitVehicleMapper.toListing(json)!;
      expect(listing.hasPrice, isFalse);
      expect(listing.displayPrice, 'Call for price');
    });

    test('skips vehicles with no usable identity', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json['stock'] = '';
      json['vin'] = '';

      expect(LiftKitVehicleMapper.toListing(json), isNull);
    });

    test('falls back to the VIN when the feed omits a stock number', () {
      final json = jsonDecode(_liftKitVehicle) as Map<String, dynamic>;
      json.remove('stock');

      final listing = LiftKitVehicleMapper.toListing(json)!;
      expect(listing.id, 'liftkit:3GCUDHEL5PG205293');
      expect(listing.stock, '3GCUDHEL5PG205293');
    });
  });
}
