import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Swallows ambient Supabase auth events (signedIn/signedOut) while a
/// link-driven flow is actively managing its own session lifecycle.
///
/// Without this guard, e.g. the password-reset flow's
/// verifyOTP(recovery) -> setNewPassword -> signOut sequence fires
/// signedIn/signedOut events that would race CheckAuthStatusEvent against
/// the screen the user is actually looking at (BUG-007 and related races).
/// Must run first in the chain.
class FlowGuardHandler extends AuthSignalHandler {
  /// Set while a reset-password link is being processed (token verification,
  /// mismatched-account sign-out) — i.e. before AuthPasswordResetState exists
  /// to check against. The signOut of the previous user fires a signedOut
  /// event that would otherwise queue NavigateToHomeEvent and bounce the user
  /// to the Welcome screen mid-flow (the BUG-008/BUG-009 1st-attempt bounce).
  /// Cleared by AuthBloc.onChange once the flow leaves its states.
  static bool linkFlowActive = false;

  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.supabaseAuthEvent) return false;

    if (linkFlowActive) return true;

    final state = authBloc.state;
    return state is AuthPasswordResetState ||
        state is AuthPendingPhoneVerificationState;
  }
}
