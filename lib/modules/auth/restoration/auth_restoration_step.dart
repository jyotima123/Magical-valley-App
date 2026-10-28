import 'package:mvc_app/modules/auth/auth_state.dart';
import 'package:mvc_app/modules/auth/restoration/restoration_context.dart';

/// A single step in [AuthRestorationChain].
abstract class AuthRestorationStep {
  /// Returns the [AuthState] to emit, or null to let the next step decide.
  Future<AuthState?> evaluate(RestorationContext ctx);
}
