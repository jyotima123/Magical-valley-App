import 'package:shared_preferences/shared_preferences.dart';

/// Persists in-progress OTP verification state (email and SMS) across app
/// restarts so the user can resume mid-flow after the app is killed.
///
/// Email OTP: call [save]/[clear]/[get].
/// SMS OTP:   call [savePhone]/[clearPhone]/[getPhone].
class AuthPendingOtpService {
  AuthPendingOtpService._();
  static final AuthPendingOtpService instance = AuthPendingOtpService._();

  static const _keyEmail = 'pending_otp_email';
  static const _keyType = 'pending_otp_type';
  static const _keySmsPhone = 'pending_sms_phone';
  static const _keySmsEmail = 'pending_sms_email';
  static const _keyRecoveryPending = 'pending_password_recovery';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Email OTP ────────────────────────────────────────────────────────────

  Future<void> save(String email, String otpType) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyType, otpType);
  }

  Future<void> clear() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyType);
  }

  /// Returns the persisted email-OTP state, or null if none exists.
  Future<({String email, String otpType})?> get() async {
    final prefs = await _getPrefs();
    final email = prefs.getString(_keyEmail);
    if (email == null || email.isEmpty) return null;
    final otpType = prefs.getString(_keyType) ?? 'signup';
    return (email: email, otpType: otpType);
  }

  // ── SMS OTP ──────────────────────────────────────────────────────────────

  /// Persists the phone number and account email while the user is on the SMS
  /// OTP screen (BUG-004 / BUG-005: app killed before OTP is confirmed).
  Future<void> savePhone(String phoneNumber, String email) async {
    final prefs = await _getPrefs();
    await prefs.setString(_keySmsPhone, phoneNumber);
    await prefs.setString(_keySmsEmail, email);
  }

  Future<void> clearPhone() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keySmsPhone);
    await prefs.remove(_keySmsEmail);
  }

  /// Returns the persisted SMS-OTP state, or null if none exists.
  Future<({String phoneNumber, String email})?> getPhone() async {
    final prefs = await _getPrefs();
    final phone = prefs.getString(_keySmsPhone);
    if (phone == null || phone.isEmpty) return null;
    final email = prefs.getString(_keySmsEmail) ?? '';
    return (phoneNumber: phone, email: email);
  }

  // ── Password recovery (reset-password deep link) ─────────────────────────

  /// Marks a password-recovery flow as in progress. A recovery token is
  /// verified at link-open time, which creates a real Supabase session for
  /// the link's account; if the app is killed before the flow finishes, this
  /// marker tells the restoration chain to sign that session out instead of
  /// silently logging the user in without a password (DL-108).
  Future<void> saveRecoveryPending() async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyRecoveryPending, true);
  }

  Future<void> clearRecoveryPending() async {
    final prefs = await _getPrefs();
    await prefs.remove(_keyRecoveryPending);
  }

  Future<bool> isRecoveryPending() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyRecoveryPending) ?? false;
  }
}
