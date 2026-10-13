import 'package:flutter/foundation.dart';
import 'package:mvc_app/main_scaffold.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal.dart';
import 'package:mvc_app/modules/auth/chain/auth_signal_handler.dart';

/// Handles `<scheme>://vehicle-inquiry/<conversationId>` deep links by opening
/// the Market inquiry chat — about a car or any other listing — on the Market
/// tab (also reachable from cars-chat
/// push notifications, which navigate through the same MainScaffold entry
/// point).
class VehicleInquiryLinkHandler extends AuthSignalHandler {
  @override
  Future<bool> handle(AuthSignal signal, AuthBloc authBloc) async {
    if (signal.type != AuthSignalType.deepLink) return false;
    final uri = signal.uri;
    if (uri?.host != 'vehicle-inquiry') return false;

    final conversationId = uri!.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : uri.queryParameters['id'];

    if (conversationId == null || conversationId.isEmpty) {
      debugPrint('VehicleInquiryLinkHandler: link missing conversation id');
      return true; // ours, but malformed — stop the chain
    }

    // Only navigate when signed in; otherwise drop the link and let the
    // normal auth flow take over.
    if (authBloc.state is AuthAuthenticatedState) {
      mainScaffoldKey.currentState
          ?.openVehicleInquiryConversation(conversationId);
    } else {
      debugPrint(
          'VehicleInquiryLinkHandler: not authenticated, dropping link');
    }
    return true;
  }
}
