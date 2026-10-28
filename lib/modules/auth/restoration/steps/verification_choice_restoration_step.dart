import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';

/// Fallback for a verified-pending session with no in-progress OTP flow:
/// let the user choose how to verify (email vs SMS).
class VerificationChoiceRestorationStep extends AuthRestorationStep {
  @override
  Future<AuthState?> evaluate(RestorationContext ctx) async {
    if (!ctx.hasSession || ctx.isVerified) return null;

    return AuthVerificationMethodChoiceState(email: ctx.email);
  }
}
