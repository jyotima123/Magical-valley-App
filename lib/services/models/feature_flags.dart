// lib/services/models/feature_flags.dart
class FeatureFlags {
  final String? minRecommendedVersionAndroid;
  final String? minRecommendedVersionIos;
  final String? minRequiredVersionAndroid;
  final String? minRequiredVersionIos;
  final bool loginAppleEnabled;
  final bool loginEmailEnabled;
  final bool loginFacebookEnabled;
  final bool loginGoogleEnabled;
  final bool smsVerificationEnabled;

  FeatureFlags({
    this.minRecommendedVersionAndroid,
    this.minRecommendedVersionIos,
    this.minRequiredVersionAndroid,
    this.minRequiredVersionIos,
    this.loginAppleEnabled = true,
    this.loginEmailEnabled = true,
    this.loginFacebookEnabled = false,
    this.loginGoogleEnabled = false,
    this.smsVerificationEnabled = false,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    return FeatureFlags(
      minRecommendedVersionAndroid: json['min_recommended_version_android'] as String?,
      minRecommendedVersionIos: json['min_recommended_version_ios'] as String?,
      minRequiredVersionAndroid: json['min_required_version_android'] as String?,
      minRequiredVersionIos: json['min_required_version_ios'] as String?,
      loginAppleEnabled: json['login_apple_enabled'] as bool? ?? true,
      loginEmailEnabled: json['login_email_enabled'] as bool? ?? true,
      loginFacebookEnabled: json['login_facebook_enabled'] as bool? ?? false,
      loginGoogleEnabled: json['login_google_enabled'] as bool? ?? false,
      smsVerificationEnabled: json['sms_verification_enabled'] as bool? ?? false,
    );
  }
}

