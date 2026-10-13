import 'package:mvc_app/services/api_repository.dart';

/// A snapshot of the current session/profile used by [AuthRestorationChain]
/// to decide which screen the user should land on.
class RestorationContext {
  final AuthResult? user;
  final UserProfile? profile;
  final String provider;
  final bool isPhoneVerified;
  final ApiRepository apiRepository;

  const RestorationContext({
    required this.user,
    required this.profile,
    required this.provider,
    required this.isPhoneVerified,
    required this.apiRepository,
  });

  bool get hasSession => user != null && user!.isSuccess;

  /// Social logins (Apple, Google, Facebook, ...) are pre-verified by the
  /// identity provider — they never need our OTP step.
  bool get isSocialLogin => provider != 'email';

  /// A confirmed phone counts as verified even if the profile update that
  /// writes verified_at failed (e.g. network error during OTP flow).
  bool get isVerified =>
      isSocialLogin || isPhoneVerified || profile?.verifiedAt != null;

  String get userId => user?.userId ?? '';
  String get email => user?.email ?? '';

  static Future<RestorationContext> build(ApiRepository apiRepository) async {
    final user = await apiRepository.getCurrentUser();

    UserProfile? profile;
    if (user != null && user.isSuccess && user.userId != null) {
      try {
        final profileResult = await apiRepository.getUserProfile(user.userId!);
        if (profileResult.isSuccess) profile = profileResult.data;
      } catch (e) {
        print('Error fetching user profile: $e');
      }
    }

    final appMeta = user?.userData?['app_metadata'] as Map<String, dynamic>?;
    final provider = appMeta?['provider'] as String? ?? 'email';
    final phoneConfirmedAt = user?.userData?['phone_confirmed_at'] as String?;

    return RestorationContext(
      user: user,
      profile: profile,
      provider: provider,
      isPhoneVerified: phoneConfirmedAt != null,
      apiRepository: apiRepository,
    );
  }
}
