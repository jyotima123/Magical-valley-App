import 'package:mvc_app/modules/market/pets/petango_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the shelter feed is switched on, and what to call the shelter.
///
/// The `dealer_sources` row (migration 088) is the off switch, as it is for
/// LiftKit: a missing or inactive row takes the animals out of Pets without a
/// release.
class ShelterSource {
  final String displayName;

  const ShelterSource({required this.displayName});

  static const String _fallbackName = 'Twin Falls Animal Shelter';

  /// Null when the feed is off or not configured in this build.
  ///
  /// A registry that cannot be read is not a reason to hide the animals: the
  /// feed is assumed on, as the Cars tab assumes LiftKit.
  static Future<ShelterSource?> load() async {
    if (!PetangoApiService.isConfigured) return null;
    try {
      final row = await Supabase.instance.client
          .from('dealer_sources')
          .select('display_name, is_active')
          .eq('source', PetangoApiService.source)
          .maybeSingle();
      if (row == null || row['is_active'] != true) return null;
      return ShelterSource(
        displayName: row['display_name'] as String? ?? _fallbackName,
      );
    } catch (_) {
      return const ShelterSource(displayName: _fallbackName);
    }
  }
}
