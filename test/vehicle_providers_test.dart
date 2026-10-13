import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/modules/cars/providers/community_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/feed_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/liftkit_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_providers.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_source_registry.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// A provider that either yields vehicles or falls over, so the fan-out's
/// isolation guarantee can be exercised without a network.
class _FakeProvider implements VehicleProvider {
  @override
  final String providerKey;
  @override
  final String displayName;

  final List<VehicleListing> vehicles;
  final bool throws;

  _FakeProvider(
    this.providerKey, {
    this.vehicles = const [],
    this.throws = false,
  }) : displayName = providerKey;

  @override
  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false}) async {
    if (throws) throw StateError('$providerKey is down');
    return vehicles;
  }
}

VehicleListing _vehicle(String stock, String source) => VehicleListing(
      id: '$source:$stock',
      stock: stock,
      year: 2023,
      make: 'Chevrolet',
      model: 'Silverado 1500',
      status: 'Pre-Owned',
      mileage: 100,
      price: 45000,
      images: const [],
      videos: const [],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      source: source,
    );

void main() {
  group('registry parsing', () {
    test('reads the kind that decides where a source may be read', () {
      expect(
        VehicleSourceEntry.fromJson({'source': 'community', 'kind': 'community'})
            .kind,
        SourceKind.community,
      );
      expect(
        VehicleSourceEntry.fromJson({'source': 'liftkit', 'kind': 'api'}).kind,
        SourceKind.api,
      );
      expect(
        VehicleSourceEntry.fromJson({'source': 'vauto:1', 'kind': 'feed'}).kind,
        SourceKind.feed,
      );
    });

    test('an unknown kind is treated as a feed, never as a live pull', () {
      // Guessing "api" would mean trying to call a vendor we have no client
      // for; guessing "feed" only means reading rows that may not exist.
      final entry =
          VehicleSourceEntry.fromJson({'source': 'x', 'kind': 'something-new'});
      expect(entry.kind, SourceKind.feed);
    });

    test('provider falls back to the source key for pre-078 rows', () {
      final entry = VehicleSourceEntry.fromJson({'source': 'liftkit'});
      expect(entry.provider, 'liftkit');
    });
  });

  group('building providers from the registry', () {
    test('collapses one vendor\'s dealerships into a single provider', () async {
      final providers = await VehicleProviders.build(entries: const [
        VehicleSourceEntry(
          source: kCommunitySource,
          provider: kCommunitySource,
          kind: SourceKind.community,
          displayName: 'Community',
        ),
        VehicleSourceEntry(
          source: 'vauto:48213',
          provider: 'vauto',
          kind: SourceKind.feed,
          displayName: 'Smith Chevrolet',
        ),
        VehicleSourceEntry(
          source: 'vauto:50991',
          provider: 'vauto',
          kind: SourceKind.feed,
          displayName: 'Ridgeline Ford',
        ),
      ]);

      final feed = providers.whereType<FeedVehicleProvider>().single;
      expect(feed.providerKey, 'vauto');
      expect(feed.sources, ['vauto:48213', 'vauto:50991']);
      expect(providers.whereType<CommunityVehicleProvider>(), hasLength(1));
    });

    test('separate vendors stay separate providers', () async {
      final providers = await VehicleProviders.build(entries: const [
        VehicleSourceEntry(
          source: 'vauto:1',
          provider: 'vauto',
          kind: SourceKind.feed,
          displayName: 'A',
        ),
        VehicleSourceEntry(
          source: 'homenet:9',
          provider: 'homenet',
          kind: SourceKind.feed,
          displayName: 'B',
        ),
      ]);

      expect(
        providers.map((p) => p.providerKey).toSet(),
        {'vauto', 'homenet'},
      );
    });

    test('a live provider we have a client for is built', () async {
      final providers = await VehicleProviders.build(entries: const [
        VehicleSourceEntry(
          source: 'liftkit',
          provider: 'liftkit',
          kind: SourceKind.api,
          displayName: 'LiftKit',
        ),
      ]);

      expect(providers.whereType<LiftKitVehicleProvider>(), hasLength(1));
    });

    test('a live provider newer than the app build is skipped, not fatal',
        () async {
      final providers = await VehicleProviders.build(entries: const [
        VehicleSourceEntry(
          source: 'somevendor',
          provider: 'somevendor',
          kind: SourceKind.api,
          displayName: 'Some Vendor',
        ),
        VehicleSourceEntry(
          source: kCommunitySource,
          provider: kCommunitySource,
          kind: SourceKind.community,
          displayName: 'Community',
        ),
      ]);

      expect(providers, hasLength(1));
      expect(providers.single, isA<CommunityVehicleProvider>());
    });
  });

  group('fan-out isolation', () {
    test('one provider failing does not empty the list', () async {
      final results = await VehicleProviders.loadAll(providers: [
        _FakeProvider('liftkit', throws: true),
        _FakeProvider('vauto', vehicles: [_vehicle('A1', 'vauto:1')]),
        _FakeProvider(kCommunitySource, vehicles: [_vehicle('1001', 'community')]),
      ]);

      final failed = results.where((r) => r.failed).toList();
      final loaded = results.where((r) => !r.failed).toList();

      expect(failed, hasLength(1));
      expect(failed.single.provider.providerKey, 'liftkit');
      expect(failed.single.vehicles, isEmpty);
      expect(loaded, hasLength(2));
      expect(
        loaded.expand((r) => r.vehicles).map((v) => v.stock),
        containsAll(['A1', '1001']),
      );
    });

    test('every provider failing is reported per provider', () async {
      final results = await VehicleProviders.loadAll(providers: [
        _FakeProvider('liftkit', throws: true),
        _FakeProvider('vauto', throws: true),
      ]);

      expect(results.every((r) => r.failed), isTrue);
      expect(results.map((r) => r.error), everyElement(isNotNull));
    });

    test('a healthy run reports no errors', () async {
      final results = await VehicleProviders.loadAll(providers: [
        _FakeProvider('vauto', vehicles: [_vehicle('A1', 'vauto:1')]),
      ]);

      expect(results.single.failed, isFalse);
      expect(results.single.vehicles, hasLength(1));
    });
  });
}
