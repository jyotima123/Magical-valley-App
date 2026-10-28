import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Handles the initial check on app cold start (or resume), restoring
/// whatever auth/verification flow the user was in via
/// [AuthRestorationChain].
class AppStartHandler extends AuthSignalHandler {
  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.appStart) return false;

    authBloc.add(CheckAuthStatusEvent());
    return true;
  }
}
