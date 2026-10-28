import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';

/// Session exists but the user is unverified, and they had already chosen
/// email OTP on a previous run (BUG-001: inconsistent state on restart
/// mid-verification).
class PendingEmailOtpRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (!ctx.hasSession || ctx.isVerified) return null;

    final pending = await AuthPendingOtpService.instance.get();
    if (pending == null) return null;

    return AuthPendingEmailConfirmationState(
      email: pending.email,
      otpType: pending.otpType,
    );
  }
}
