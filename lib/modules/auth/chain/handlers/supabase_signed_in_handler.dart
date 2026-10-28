import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';
import 'package:mvc_app/services/amplitude_service.dart';

/// Reacts to an ambient Supabase `signedIn` event (e.g. email/password
/// login, token refresh establishing a session) by re-checking auth status
/// so the app routes to the correct screen.
class SupabaseSignedInHandler extends AuthSignalHandler {
  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.supabaseAuthEvent) return false;
    if (signal.supabaseEvent != AuthChangeEvent.signedIn) return false;
    if (signal.session == null) return false;

    AmplitudeService.instance.logEvent(
      'user_signed_in',
      eventProperties: {
        'method': signal.session!.user.appMetadata['provider'] ?? 'email',
      },
    );

    authBloc.add(CheckAuthStatusEvent());
    return true;
  }
}
