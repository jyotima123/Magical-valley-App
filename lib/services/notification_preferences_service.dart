import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferencesService {
  static final NotificationPreferencesService _instance =
      NotificationPreferencesService._internal();
  factory NotificationPreferencesService() => _instance;
  NotificationPreferencesService._internal();

  static NotificationPreferencesService get instance => _instance;

  final Logger _logger = Logger('NotificationPreferencesService');
  SharedPreferences? _prefs;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Keys for SharedPreferences
  //
  // NOTE: this stores the set of channels the user has EXPLICITLY turned
  // notifications OFF for (an opt-out/deny-list), not an opt-in allow-list.
  // Any channel id that has never been touched is treated as enabled by
  // default. This matches the server-side default used by the
  // send-fcm-notification Edge Function (`prefMap.get(...) ?? true`) and
  // the notification toggle UI, which also starts each switch in the "on"
  // position until it learns otherwise.
  //
  // This used to be stored as an "enabled channels" allow-list under the
  // key 'channel_notifications', which meant any channel without an
  // explicit entry (e.g. every channel on a fresh install, or after
  // android:allowBackup was disabled) was silently treated as disabled.
  // That key is intentionally abandoned rather than reinterpreted, so old
  // data can't be misread with the opposite meaning.
  static const String _disabledChannelsKey = 'disabled_channel_notifications';
  static const String _globalNotificationsKey = 'global_notifications_enabled';

  // Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _logger.info('Notification preferences service initialized');
    } catch (e) {
      _logger.severe(
        'Failed to initialize notification preferences service: $e',
      );
    }
  }

  // Get the set of channel IDs the user has explicitly disabled notifications for
  Future<Set<String>> getDisabledChannelIds() async {
    try {
      if (_prefs == null) await initialize();

      final jsonString = _prefs!.getString(_disabledChannelsKey);
      if (jsonString == null) return <String>{};

      final List<dynamic> channelList = jsonDecode(jsonString);
      return channelList.cast<String>().toSet();
    } catch (e) {
      _logger.warning('Failed to get disabled channel IDs: $e');
      return <String>{};
    }
  }

  Future<void> _saveDisabledChannelIds(Set<String> channelIds) async {
    if (_prefs == null) await initialize();
    final jsonString = jsonEncode(channelIds.toList());
    await _prefs!.setString(_disabledChannelsKey, jsonString);
  }

  // Check if notifications are enabled for a specific channel.
  // Defaults to true (enabled) unless the user explicitly disabled it or
  // global notifications are off.
  Future<bool> isChannelNotificationEnabled(String channelId) async {
    try {
      // First check if global notifications are enabled
      if (!await isGlobalNotificationEnabled()) {
        return false;
      }

      final disabledChannels = await getDisabledChannelIds();
      return !disabledChannels.contains(channelId);
    } catch (e) {
      _logger.warning('Failed to check channel notification status: $e');
      return true; // Default to enabled, consistent with the rest of this model
    }
  }

  // Enable notifications for a channel
  Future<void> enableChannelNotification(String channelId) async {
    try {
      final disabledChannels = await getDisabledChannelIds();
      disabledChannels.remove(channelId);
      await _saveDisabledChannelIds(disabledChannels);

      _logger.info('Enabled notifications for channel: $channelId');

      // Sync with Supabase
      await _syncPreferenceToSupabase(channelId, true);
    } catch (e) {
      _logger.severe('Failed to enable channel notification: $e');
    }
  }

  // Disable notifications for a channel
  Future<void> disableChannelNotification(String channelId) async {
    try {
      final disabledChannels = await getDisabledChannelIds();
      disabledChannels.add(channelId);
      await _saveDisabledChannelIds(disabledChannels);

      _logger.info('Disabled notifications for channel: $channelId');

      // Sync with Supabase
      await _syncPreferenceToSupabase(channelId, false);
    } catch (e) {
      _logger.severe('Failed to disable channel notification: $e');
    }
  }

  // Toggle notification for a channel
  Future<void> toggleChannelNotification(String channelId) async {
    final isEnabled = await isChannelNotificationEnabled(channelId);
    if (isEnabled) {
      await disableChannelNotification(channelId);
    } else {
      await enableChannelNotification(channelId);
    }
  }

  // Get global notification setting
  Future<bool> isGlobalNotificationEnabled() async {
    try {
      if (_prefs == null) await initialize();
      return _prefs!.getBool(_globalNotificationsKey) ??
          true; // Default to enabled
    } catch (e) {
      _logger.warning('Failed to get global notification setting: $e');
      return true;
    }
  }

  // Set global notification setting
  Future<void> setGlobalNotificationEnabled(bool enabled) async {
    try {
      if (_prefs == null) await initialize();
      await _prefs!.setBool(_globalNotificationsKey, enabled);
      _logger.info('Global notifications ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _logger.severe('Failed to set global notification setting: $e');
    }
  }

  // Clear all notification preferences (useful for logout)
  Future<void> clearAllPreferences() async {
    try {
      if (_prefs == null) await initialize();
      await _prefs!.remove(_disabledChannelsKey);
      await _prefs!.remove(_globalNotificationsKey);
      _logger.info('Cleared all notification preferences');
    } catch (e) {
      _logger.severe('Failed to clear notification preferences: $e');
    }
  }

  // Get all notification preferences as a map (useful for debugging or syncing)
  Future<Map<String, dynamic>> getAllPreferences() async {
    try {
      final disabledChannels = await getDisabledChannelIds();
      final globalEnabled = await isGlobalNotificationEnabled();

      return {
        'global_enabled': globalEnabled,
        'disabled_channels': disabledChannels.toList(),
      };
    } catch (e) {
      _logger.warning('Failed to get all preferences: $e');
      return {'global_enabled': true, 'disabled_channels': <String>[]};
    }
  }

  // Bulk-set the explicitly-disabled channels (useful for syncing from Supabase)
  Future<void> setDisabledChannels(Set<String> channelIds) async {
    try {
      await _saveDisabledChannelIds(channelIds);
      _logger.info('Set disabled channels: ${channelIds.length} channels');
    } catch (e) {
      _logger.severe('Failed to set disabled channels: $e');
    }
  }

  // Check if any channels have notifications enabled.
  // Per-channel defaults to enabled now, so this is effectively whether
  // global notifications are on.
  Future<bool> hasAnyChannelNotificationsEnabled() async {
    return await isGlobalNotificationEnabled();
  }

  // Get notification preferences for display in UI
  Future<Map<String, bool>> getChannelNotificationStates(
    List<String> channelIds,
  ) async {
    final states = <String, bool>{};
    for (final channelId in channelIds) {
      states[channelId] = await isChannelNotificationEnabled(channelId);
    }
    return states;
  }

  // ============================================================================
  // SUPABASE SYNC METHODS
  // ============================================================================

  /// Syncs a single notification preference to Supabase
  Future<void> _syncPreferenceToSupabase(String channelId, bool enabled) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _logger.warning('Cannot sync preference: User not logged in');
        return;
      }

      // Upsert the preference (insert or update if exists)
      await _supabase.from('notification_preferences').upsert({
        'user_id': userId,
        'channel_id': channelId,
        'notifications_enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      });

      _logger.info(
        'Synced preference to Supabase: channel=$channelId, enabled=$enabled',
      );
    } catch (e) {
      _logger.severe('Failed to sync preference to Supabase: $e');
      // Don't throw - local preference is already saved
    }
  }

  /// Fetches notification preferences from Supabase for a specific channel
  Future<bool?> fetchChannelPreferenceFromSupabase(String channelId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _logger.warning('Cannot fetch preference: User not logged in');
        return null;
      }

      final response = await _supabase
          .from('notification_preferences')
          .select('notifications_enabled')
          .eq('user_id', userId)
          .eq('channel_id', channelId)
          .maybeSingle();

      if (response == null) {
        return null; // No preference stored (defaults to enabled)
      }

      return response['notifications_enabled'] as bool?;
    } catch (e) {
      _logger.warning('Failed to fetch preference from Supabase: $e');
      return null;
    }
  }

  /// Syncs all local preferences to Supabase (useful after login)
  Future<void> syncAllPreferencesToSupabase() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _logger.warning('Cannot sync preferences: User not logged in');
        return;
      }

      final disabledChannels = await getDisabledChannelIds();

      // Get all channels the user follows to sync enabled ones too
      final allChannelsResponse = await _supabase
          .from('user_follows')
          .select('organization_id')
          .eq('user_id', userId);

      final allChannelIds = (allChannelsResponse as List)
          .map((row) => row['organization_id'] as String)
          .toSet();

      // Prepare batch upsert data
      final preferencesToSync = <Map<String, dynamic>>[];

      for (final channelId in allChannelIds) {
        final enabled = !disabledChannels.contains(channelId);
        preferencesToSync.add({
          'user_id': userId,
          'channel_id': channelId,
          'notifications_enabled': enabled,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (preferencesToSync.isNotEmpty) {
        await _supabase
            .from('notification_preferences')
            .upsert(preferencesToSync);
        _logger.info(
          'Synced ${preferencesToSync.length} preferences to Supabase',
        );
      }
    } catch (e) {
      _logger.severe('Failed to sync all preferences to Supabase: $e');
    }
  }

  /// Fetches all preferences from Supabase and updates local storage
  /// (useful after login to sync across devices/reinstalls). Only rows the
  /// user explicitly set to disabled are carried over locally — a channel
  /// with no row at all, or a row with notifications_enabled=true, is left
  /// enabled by default, matching the server's own default.
  Future<void> syncFromSupabase() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        _logger.warning('Cannot sync from Supabase: User not logged in');
        return;
      }

      final response = await _supabase
          .from('notification_preferences')
          .select('channel_id, notifications_enabled')
          .eq('user_id', userId);

      final disabledChannels = <String>{};

      for (final row in response as List) {
        final channelId = row['channel_id'] as String;
        final enabled = row['notifications_enabled'] as bool;

        if (!enabled) {
          disabledChannels.add(channelId);
        }
      }

      // Update local storage
      await setDisabledChannels(disabledChannels);
      _logger.info(
        'Synced ${disabledChannels.length} disabled channel preferences from Supabase',
      );
    } catch (e) {
      _logger.severe('Failed to sync from Supabase: $e');
    }
  }

  /// Deletes a channel preference from Supabase (when user unfollows)
  Future<void> deleteChannelPreferenceFromSupabase(String channelId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase
          .from('notification_preferences')
          .delete()
          .eq('user_id', userId)
          .eq('channel_id', channelId);

      _logger.info('Deleted preference from Supabase: channel=$channelId');
    } catch (e) {
      _logger.warning('Failed to delete preference from Supabase: $e');
    }
  }
}
