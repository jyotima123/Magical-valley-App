import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How a source reaches us, which decides where its stored rows may be read.
enum SourceKind {
  /// Listed in-app by a user.
  community,

  /// Pulled live from the provider at read time. Stored rows are shadow rows,
  /// materialized on first buyer contact, and must stay out of the browse list
  /// or every contacted car appears twice — once stale.
  api,

  /// Delivered as a file and ingested. The stored rows are the inventory.
  feed,
}

/// One active row of `dealer_sources`.
class VehicleSourceEntry {
  /// The `vehicle_listings.source` value, e.g. `community`, `liftkit`,
  /// `vauto:48213`.
  final String source;

  /// Which integration handles it. Many sources share a provider — one per
  /// dealership that vendor exports for.
  final String provider;

  final SourceKind kind;
  final String displayName;

  const VehicleSourceEntry({
    required this.source,
    required this.provider,
    required this.kind,
    required this.displayName,
  });

  factory VehicleSourceEntry.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String;
    return VehicleSourceEntry(
      source: source,
      provider: json['provider'] as String? ?? source,
      kind: _parseKind(json['kind'] as String?),
      displayName: json['display_name'] as String? ?? source,
    );
  }

  static SourceKind _parseKind(String? raw) {
    switch (raw) {
      case 'community':
        return SourceKind.community;
      case 'api':
        return SourceKind.api;
      default:
        return SourceKind.feed;
    }
  }
}

/// Reads the set of live inventory providers from `dealer_sources`.
class VehicleSourceRegistry {
  /// Used when the registry itself cannot be read. The Cars tab losing its
  /// network is not a reason to show an empty app: community listings and the
  /// one provider we have always had are assumed, and anything newer is simply
  /// missing until the next successful load.
  static const List<VehicleSourceEntry> _fallback = [
    VehicleSourceEntry(
      source: kCommunitySource,
      provider: kCommunitySource,
      kind: SourceKind.community,
      displayName: 'Community',
    ),
    VehicleSourceEntry(
      source: 'liftkit',
      provider: 'liftkit',
      kind: SourceKind.api,
      displayName: 'LiftKit',
    ),
  ];

  static Future<List<VehicleSourceEntry>> load() async {
    try {
      final rows = await Supabase.instance.client
          .from('dealer_sources')
          .select('source, provider, kind, display_name')
          .eq('is_active', true);

      final entries = (rows as List)
          .map((e) => VehicleSourceEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      return entries.isEmpty ? _fallback : entries;
    } catch (_) {
      return _fallback;
    }
  }
}
