import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';

/// A single link in the [AuthSignalChain].
///
/// Each handler inspects the [AuthSignal] and decides whether it owns it.
abstract class AuthSignalHandler {
  /// Returns true if this handler fully handled [signal] and the chain
  /// should stop here; false to let the next handler try.
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc);
}
