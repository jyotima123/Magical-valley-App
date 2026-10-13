import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/auth_restoration_step.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';

/// Resolves the [AuthState] to emit for `CheckAuthStatusEvent` by running
/// [steps] in order and taking the first non-null result.
///
/// Falls back to [AuthWelcomeState] if no step matches.
class AuthRestorationChain {
  AuthRestorationChain(this._steps);

  final List<AuthRestorationStep> _steps;

  Future<AuthState> resolve(RestorationContext ctx) async {
    for (final step in _steps) {
      final result = await step.evaluate(ctx);
      if (result != null) return result;
    }
    return const AuthWelcomeState();
  }
}
