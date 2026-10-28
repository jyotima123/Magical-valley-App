import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Handles `<scheme>://reset-password?token=...` deep links.
class PasswordResetLinkHandler extends AuthSignalHandler {
  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.deepLink) return false;
    if (signal.uri?.host != 'reset-password') return false;

    authBloc.add(PasswordResetLinkReceivedEvent(uri: signal.uri!));
    return true;
  }
}
