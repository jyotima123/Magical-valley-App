import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';

/// Session exists and the user is verified (email OTP, phone OTP, or social
/// login) — route to the authenticated app.
class VerifiedSessionRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (!ctx.hasSession || !ctx.isVerified) return null;

    // Backfill verified_at for accounts whose profile never got it written:
    // social logins from before migration 059, or phone-verified users whose
    // post-verification profile update failed (network error mid-flow).
    if (ctx.profile != null && ctx.profile!.verifiedAt == null) {
      try {
        await ctx.apiRepository.updateUserProfile(ctx.userId, {
          'verified_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (e) {
        print('Warning: Failed to backfill verified_at: $e');
      }
    }

    return AuthAuthenticatedState(
      userId: ctx.userId,
      email: ctx.email,
      userData: ctx.user!.userData,
      userProfile: ctx.profile,
      managedOrganizations: const [],
    );
  }
}
