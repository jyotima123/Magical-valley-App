import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage the last used login method
class LastLoginMethodService {
  LastLoginMethodService._();

  static final LastLoginMethodService instance = LastLoginMethodService._();

  SharedPreferences? _prefs;
  static const String _lastLoginMethodKey = 'last_login_method';

  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Get the last used login method
  /// Returns null if no method has been used yet
  Future<String?> getLastLoginMethod() async {
    final prefs = await _getPrefs();
    return prefs.getString(_lastLoginMethodKey);
  }

  /// Save the last used login method
  /// Valid methods: 'apple', 'facebook', 'email'
  Future<void> saveLastLoginMethod(String method) async {
    final prefs = await _getPrefs();
    await prefs.setString(_lastLoginMethodKey, method.toLowerCase());
  }

  /// Clear the last used login method
  Future<void> clearLastLoginMethod() async {
    final prefs = await _getPrefs();
    await prefs.remove(_lastLoginMethodKey);
  }
}

