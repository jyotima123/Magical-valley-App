import 'package:flutter/material.dart';
import 'package:mvc_app/widgets/app_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FirstRunKeys {
  static const String introLoginDialog = 'intro_login_dialog_shown_v1';
  static const String appTour = 'app_tour_shown_v1';
}

/// Keys of the hint dialogs whose text lives in the `first_run_hints` table
/// (migration 082). Each must match a row's `key` there.
class FirstRunHintKeys {
  static const String chatFollow = 'chat_follow_hint';
  static const String editUser = 'edit_user_hint';
  static const String profileSettings = 'profile_settings_hint';
  static const String createOrganization = 'create_organization_hint';
  static const String createPost = 'create_post_hint';
  static const String market = 'market_hint';

  /// The boolean flags these hints used before their text moved to the
  /// database. Users who already saw a hint are not shown it again just
  /// because it moved.
  static const Map<String, String> legacyShownFlags = {
    chatFollow: 'chat_follow_hint_shown_v1',
    editUser: 'edit_user_hint_shown_v1',
    profileSettings: 'profile_settings_hint_shown_v1',
    createOrganization: 'create_organization_hint_shown_v1',
    createPost: 'create_post_hint_shown_v1',
  };
}

/// One row of `first_run_hints`.
class FirstRunHint {
  final String key;
  final String heading;
  final String? subheading;

  /// Kept exactly as the database sent it. Postgres timestamps carry
  /// microseconds, so converting to milliseconds would make the stored value
  /// always older than the database's and re-show the hint on every visit.
  final String contentUpdatedAt;

  const FirstRunHint({
    required this.key,
    required this.heading,
    this.subheading,
    required this.contentUpdatedAt,
  });

  factory FirstRunHint.fromJson(Map<String, dynamic> json) => FirstRunHint(
    key: json['key'] as String,
    heading: json['heading'] as String,
    subheading: json['subheading'] as String?,
    contentUpdatedAt: json['content_updated_at'] as String,
  );
}

class FirstRunService {
  FirstRunService._();

  static final FirstRunService instance = FirstRunService._();

  static const String _hintSeenPrefix = 'first_run_hint_seen_';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<bool> shouldShow(String key) async {
    final prefs = await _getPrefs();
    return !(prefs.getBool(key) ?? false);
  }

  Future<void> markShown(String key) async {
    final prefs = await _getPrefs();
    await prefs.setBool(key, true);
  }

  /// Fetches the hint [key] and returns it if the user has not seen this
  /// version of its text, or null otherwise. Also null when the hint is
  /// missing, inactive or cannot be fetched (e.g. offline); the next visit
  /// tries again.
  Future<FirstRunHint?> hintToShow(String key) async {
    try {
      final row = await Supabase.instance.client
          .from('first_run_hints')
          .select('key, heading, subheading, content_updated_at')
          .eq('key', key)
          .eq('is_active', true)
          .maybeSingle();
      if (row == null) return null;
      final hint = FirstRunHint.fromJson(row);

      final prefs = await _getPrefs();
      final seenAt = prefs.getString('$_hintSeenPrefix$key');
      if (seenAt == null) {
        final legacyFlag = FirstRunHintKeys.legacyShownFlags[key];
        if (legacyFlag != null && (prefs.getBool(legacyFlag) ?? false)) {
          // Seen before the move to the database: treat the current text as
          // seen, so only later edits re-show it.
          await markHintSeen(hint);
          return null;
        }
        return hint;
      }
      final isNewer = DateTime.parse(
        hint.contentUpdatedAt,
      ).isAfter(DateTime.parse(seenAt));
      return isNewer ? hint : null;
    } catch (e) {
      debugPrint('⚠️ FirstRunService.hintToShow($key) failed: $e');
      return null;
    }
  }

  Future<void> markHintSeen(FirstRunHint hint) async {
    final prefs = await _getPrefs();
    await prefs.setString(
      '$_hintSeenPrefix${hint.key}',
      hint.contentUpdatedAt,
    );
  }

  /// Shows the hint [key] with [icon] if its current text is new to the user,
  /// and remembers the version shown. The icon stays in the app because
  /// release builds only ship icons referenced in code.
  Future<void> maybeShowHint(
    BuildContext context, {
    required String key,
    required IconData icon,
  }) async {
    final hint = await hintToShow(key);
    if (hint == null || !context.mounted) return;

    await AppDialog.show(
      context: context,
      icon: icon,
      heading: hint.heading,
      subheading: hint.subheading,
      dismissible: true,
    );

    await markHintSeen(hint);
  }
}
