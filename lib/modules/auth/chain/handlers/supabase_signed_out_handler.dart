import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Reacts to a Supabase `signedOut` event by running widget-tree-dependent
/// cleanup (FCM, analytics) and routing the app back to the welcome screen.
class SupabaseSignedOutHandler extends AuthSignalHandler {
  SupabaseSignedOutHandler({this.onSignedOut});

  /// Side effects to run on sign-out (FCM cleanup, analytics reset) that
  /// depend on widget-tree context and so can't live in this handler.
  final VoidCallback? onSignedOut;

  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.supabaseAuthEvent) return false;
    if (signal.supabaseEvent != AuthChangeEvent.signedOut) return false;

    onSignedOut?.call();
    authBloc.add(NavigateToHomeEvent());
    return true;
  }
}
