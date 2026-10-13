// lib/services/read_status_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ReadStatusService {
  static const String _readStatusKey = 'chat_read_status';
  static ReadStatusService? _instance;
  SharedPreferences? _prefs;

  ReadStatusService._();

  static ReadStatusService get instance {
    _instance ??= ReadStatusService._();
    return _instance!;
  }

  /// Initialize the service with SharedPreferences
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get the last read timestamp for a specific organization/channel
  Future<DateTime?> getLastReadTime(String organizationId) async {
    await initialize();

    final readStatusJson = _prefs?.getString(_readStatusKey);
    if (readStatusJson == null) return null;

    try {
      final Map<String, dynamic> readStatus = json.decode(readStatusJson);
      final timestampString = readStatus[organizationId];

      if (timestampString != null) {
        return DateTime.parse(timestampString);
      }
    } catch (e) {
      print('🔍 ReadStatusService: Error parsing read status: $e');
    }

    return null;
  }

  /// Mark a channel as read by storing the current timestamp
  Future<void> markChannelAsRead(String organizationId) async {
    await initialize();

    final readStatusJson = _prefs?.getString(_readStatusKey);
    Map<String, dynamic> readStatus = {};

    if (readStatusJson != null) {
      try {
        readStatus = json.decode(readStatusJson);
      } catch (e) {
        print('🔍 ReadStatusService: Error parsing existing read status: $e');
        readStatus = {};
      }
    }

    // Store current timestamp as UTC
    readStatus[organizationId] = DateTime.now().toUtc().toIso8601String();

    try {
      await _prefs?.setString(_readStatusKey, json.encode(readStatus));
      print(
        '🔍 ReadStatusService: Marked channel $organizationId as read at ${DateTime.now().toUtc()}',
      );
    } catch (e) {
      print('🔍 ReadStatusService: Error saving read status: $e');
    }
  }

  /// Check if a channel has unread messages
  /// Returns true if the latest message timestamp is after the last read time
  Future<bool> hasUnreadMessages(
    String organizationId,
    DateTime? latestMessageTime,
  ) async {
    if (latestMessageTime == null) return false;

    final lastReadTime = await getLastReadTime(organizationId);
    if (lastReadTime == null) {
      // If we've never read this channel, it has unread messages if there are any messages
      return true;
    }

    // Compare timestamps - if latest message is after last read time, there are unread messages
    return latestMessageTime.isAfter(lastReadTime);
  }

  /// Get all read statuses (for debugging or migration purposes)
  Future<Map<String, DateTime>> getAllReadStatuses() async {
    await initialize();

    final readStatusJson = _prefs?.getString(_readStatusKey);
    if (readStatusJson == null) return {};

    try {
      final Map<String, dynamic> readStatus = json.decode(readStatusJson);
      final Map<String, DateTime> result = {};

      readStatus.forEach((key, value) {
        try {
          result[key] = DateTime.parse(value);
        } catch (e) {
          print('🔍 ReadStatusService: Error parsing timestamp for $key: $e');
        }
      });

      return result;
    } catch (e) {
      print('🔍 ReadStatusService: Error getting all read statuses: $e');
      return {};
    }
  }

  /// Clear all read statuses (useful for device reset or debugging)
  /// NOTE: This should NOT be called on logout - read status is device-based
  Future<void> clearAllReadStatuses() async {
    await initialize();

    try {
      await _prefs?.remove(_readStatusKey);
      print('🔍 ReadStatusService: Cleared all read statuses');
    } catch (e) {
      print('🔍 ReadStatusService: Error clearing read statuses: $e');
    }
  }

  /// Clear read status for a specific channel
  Future<void> clearChannelReadStatus(String organizationId) async {
    await initialize();

    final readStatusJson = _prefs?.getString(_readStatusKey);
    if (readStatusJson == null) return;

    try {
      final Map<String, dynamic> readStatus = json.decode(readStatusJson);
      readStatus.remove(organizationId);

      await _prefs?.setString(_readStatusKey, json.encode(readStatus));
      print(
        '🔍 ReadStatusService: Cleared read status for channel $organizationId',
      );
    } catch (e) {
      print('🔍 ReadStatusService: Error clearing channel read status: $e');
    }
  }
}
