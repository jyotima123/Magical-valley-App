import 'package:flutter/foundation.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Single entry point for all auth-related signals: deep links, Supabase
/// auth-state changes, and app-start checks.
///
/// Runs [handlers] in order and stops at the first one that reports it
/// handled the signal. Dispatches are serialized so a deep link and the
/// Supabase event it triggers can never be processed out of order.
class AuthSignalChain {
  AuthSignalChain({
    required this.authBloc,
    required List<AuthSignalHandler> handlers,
  }) : _handlers = handlers;

  final AuthBloc authBloc;
  final List<AuthSignalHandler> _handlers;
  Future<void> _queue = Future.value();

  /// Queues [signal] for processing after any signal already in flight.
  Future<void> dispatch(AuthSignal signal) {
    final result = _queue.then((_) => _process(signal));
    // Keep the queue alive even if a handler throws.
    _queue = result.catchError((_) {});
    return result;
  }

  Future<void> _process(AuthSignal signal) async {
    for (final handler in _handlers) {
      try {
        if (await handler.handle(signal, authBloc)) return;
      } catch (e) {
        debugPrint('⚠️ AuthSignalChain: ${handler.runtimeType} failed: $e');
        return;
      }
    }
    debugPrint('AuthSignalChain: no handler matched $signal');
  }
}
