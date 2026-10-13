import 'package:supabase_flutter/supabase_flutter.dart';

/// The kind of trigger that produced an [AuthSignal].
enum AuthSignalType {
  /// An incoming `app_links` deep link (reset-password, email-confirmation,
  /// login-callback, ...).
  deepLink,

  /// A Supabase `onAuthStateChange` event (signedIn, signedOut, ...).
  supabaseAuthEvent,

  /// The app just started (or resumed) and auth status should be checked.
  appStart,
}

/// A single auth-related event fed into the [AuthSignalChain].
///
/// This unifies the previously-separate deep-link switch and Supabase
/// auth-state listener into one stream of signals that handlers can react
/// to in a defined order.
class AuthSignal {
  final AuthSignalType type;
  final Uri? uri;
  final AuthChangeEvent? supabaseEvent;
  final Session? session;

  const AuthSignal._({
    required this.type,
    this.uri,
    this.supabaseEvent,
    this.session,
  });

  factory AuthSignal.deepLink(Uri uri) =>
      AuthSignal._(type: AuthSignalType.deepLink, uri: uri);

  factory AuthSignal.supabaseAuthEvent(AuthChangeEvent event, Session? session) =>
      AuthSignal._(
        type: AuthSignalType.supabaseAuthEvent,
        supabaseEvent: event,
        session: session,
      );

  const AuthSignal.appStart() : this._(type: AuthSignalType.appStart);

  @override
  String toString() {
    switch (type) {
      case AuthSignalType.deepLink:
        return 'AuthSignal.deepLink($uri)';
      case AuthSignalType.supabaseAuthEvent:
        return 'AuthSignal.supabaseAuthEvent($supabaseEvent)';
      case AuthSignalType.appStart:
        return 'AuthSignal.appStart()';
    }
  }
}
