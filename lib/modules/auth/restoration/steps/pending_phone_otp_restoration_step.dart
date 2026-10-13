import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';
import 'package:mvc_app/services/auth_pending_otp_service.dart';

/// Session exists but the user is unverified, and they were mid-SMS-OTP
/// verification on a previous run (BUG-004: app killed while waiting for
/// SMS; BUG-005: app killed right after submitting the OTP code).
class PendingPhoneOtpRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (!ctx.hasSession || ctx.isVerified) return null;

    final pendingPhone = await AuthPendingOtpService.instance.getPhone();
    if (pendingPhone == null) return null;

    return AuthPendingPhoneVerificationState(
      phoneNumber: pendingPhone.phoneNumber,
      email: pendingPhone.email,
      errorMessage:
          'Your verification code may have expired. Tap "Resend" to get a new one.',
    );
  }
}
