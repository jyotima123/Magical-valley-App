// lib/testability/screen_state_registry.dart
import 'screen_state.dart';

/// Singleton that always holds the latest [ScreenState].
/// Screens push updates here; [TestabilityServer] reads from here.
class ScreenStateRegistry {
  ScreenStateRegistry._();
  static final instance = ScreenStateRegistry._();

  ScreenState _current = const ScreenState(
    screen: 'unknown',
    subState: 'initializing',
  );

  void update(ScreenState state) => _current = state;

  ScreenState get current => _current;
}
