import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';

/// Must run first: a password-recovery session left over from an interrupted
/// reset flow (app killed on the reset screen — DL-108) is a real Supabase
/// session for the link's account and must never be restored as a normal
/// login. Sign it out and start over from the welcome screen.
class InterruptedRecoveryRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (!await AuthPendingOtpService.instance.isRecoveryPending()) return null;

    await AuthPendingOtpService.instance.clearRecoveryPending();
    if (ctx.hasSession) {
      try {
        await ctx.apiRepository.logout();
      } catch (e) {
        print('InterruptedRecoveryRestorationStep: logout failed: $e');
      }
    }
    return const AuthWelcomeState();
  }
}
