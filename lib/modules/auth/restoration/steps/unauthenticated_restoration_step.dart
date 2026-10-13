import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';

/// Terminal step for the no-session case: restores a pending OTP screen if
/// the user was mid-verification when the app was killed, otherwise sends
/// them to the welcome screen.
class UnauthenticatedRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (ctx.hasSession) return null;

    // BUG-002 / BUG-003: app was killed while waiting on (or right after
    // resending) an email OTP — restore the OTP screen instead of bouncing
    // to the welcome screen.
    final pending = await AuthPendingOtpService.instance.get();
    if (pending != null) {
      return AuthPendingEmailConfirmationState(
        email: pending.email,
        otpType: pending.otpType,
        errorMessage:
            'Your verification code may have expired. Tap "Resend" to get a new one.',
      );
    }

    // SMS OTP pending but the session is gone — all SMS operations require
    // an authenticated session, so clear the stale state and send the user
    // to welcome to log in again before retrying phone verification.
    final pendingPhone = await AuthPendingOtpService.instance.getPhone();
    if (pendingPhone != null) {
      await AuthPendingOtpService.instance.clearPhone();
    }

    return const AuthWelcomeState();
  }
}
