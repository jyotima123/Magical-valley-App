import 'package:mvc_app/modules/cars/liftkit_api_service.dart';
import 'package:mvc_app/modules/cars/providers/community_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/feed_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/liftkit_vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_source_registry.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// Builds the live set of providers from `dealer_sources` and fans out to them.
///
/// Adding a vendor that delivers files is a row in `dealer_sources` plus a
/// server-side mapper — no change here. Adding one that serves a live API also
/// needs an entry in [_apiProviders], because pulling at read time is by
/// definition client code.
class VehicleProviders {
  /// Live-API providers, keyed by `dealer_sources.provider`.
  static final Map<String, VehicleProvider Function()> _apiProviders = {
    'liftkit': () => LiftKitVehicleProvider(),
  };

  /// One provider instance per distinct `provider` in the registry.
  ///
  /// Feed vendors are collapsed into a single [FeedVehicleProvider] carrying
  /// every dealership they export for, so a vendor with forty rooftops is one
  /// query rather than forty.
  static Future<List<VehicleProvider>> build({List<VehicleSourceEntry>? entries}) async {
    final resolved = entries ?? await VehicleSourceRegistry.load();
    final providers = <VehicleProvider>[];
    final feedSources = <String, List<String>>{};
    final feedNames = <String, String>{};

    for (final entry in resolved) {
      switch (entry.kind) {
        case SourceKind.community:
          providers.add(CommunityVehicleProvider());
          break;

        case SourceKind.api:
          final factory = _apiProviders[entry.provider];
          // A registry row for a live provider we have no client for yet: the
          // row is ahead of the app build. Skipping is correct — the other
          // providers are unaffected, and the vendor appears once users update.
          if (factory != null) providers.add(factory());
          break;

        case SourceKind.feed:
          feedSources.putIfAbsent(entry.provider, () => []).add(entry.source);
          feedNames[entry.provider] = entry.displayName;
          break;
      }
    }

    for (final providerKey in feedSources.keys) {
      providers.add(FeedVehicleProvider(
        providerKey: providerKey,
        displayName: feedNames[providerKey] ?? providerKey,
        sources: feedSources[providerKey]!,
      ));
    }

    return providers;
  }

  /// Asks every provider for its inventory at the same time, and returns one
  /// result per provider.
  ///
  /// Errors are captured per provider rather than thrown: the caller decides
  /// what a partial result should look like, and a single vendor being down can
  /// never take the list down with it.
  static Future<List<ProviderFetch>> loadAll({
    bool forceRefresh = false,
    List<VehicleProvider>? providers,
  }) async {
    final resolved = providers ?? await build();

    return Future.wait(resolved.map((provider) async {
      try {
        final vehicles = await provider.fetchVehicles(forceRefresh: forceRefresh);
        return ProviderFetch(provider: provider, vehicles: vehicles);
      } on LiftKitException catch (e) {
        return ProviderFetch(provider: provider, error: e.message);
      } catch (_) {
        return ProviderFetch(
          provider: provider,
          error: 'Could not load ${provider.displayName} inventory.',
        );
      }
    }));
  }

  /// Every vehicle that loaded, as one list, newest first.
  ///
  /// One order for all of them: whose inventory a car came from decides nothing
  /// about where it appears, so a dealership that uploaded this morning and a
  /// neighbour who listed this afternoon interleave by date. Providers that
  /// failed contribute nothing here — the caller reports them separately.
  ///
  /// Shared by the Cars screen and the Market tab's Cars card so that "the
  /// newest cars" means the same list in both places.
  /// Cars that share a date keep the order they arrived in — a whole feed
  /// import carries one `created_at`, and List.sort is not stable, so without
  /// the tiebreak a dealership's inventory would come back shuffled
  /// differently on every load.
  static List<VehicleListing> mergeNewestFirst(List<ProviderFetch> results) {
    final merged = [
      for (final result in results)
        if (!result.failed) ...result.vehicles,
    ];

    final ordered = [
      for (var i = 0; i < merged.length; i++) (position: i, car: merged[i]),
    ];
    ordered.sort((a, b) {
      final byDate = b.car.createdAt.compareTo(a.car.createdAt);
      return byDate != 0 ? byDate : a.position.compareTo(b.position);
    });

    return [for (final entry in ordered) entry.car];
  }
}
