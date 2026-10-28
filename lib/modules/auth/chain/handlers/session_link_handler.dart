import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Handles deep links that carry a PKCE `code` to be exchanged for a
/// session: `email-confirmation` (signup magic link) and `login-callback`
/// (OAuth provider redirect, e.g. Apple/Google).
///
/// Both link types are processed identically — exchange the code for a
/// session, then let [AuthSignalChain] dispatch
/// [SessionLinkReceivedEvent]'s follow-up `CheckAuthStatusEvent` route the
/// user based on the resulting session.
class SessionLinkHandler extends AuthSignalHandler {
  static const _hosts = {'email-confirmation', 'login-callback'};

  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.deepLink) return false;
    if (!_hosts.contains(signal.uri?.host)) return false;

    authBloc.add(SessionLinkReceivedEvent(uri: signal.uri!));
    return true;
  }
}
