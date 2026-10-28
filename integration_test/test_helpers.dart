// integration_test/test_helpers.dart
import 'package:integration_test/integration_test.dart';
import 'package:mvc_app/flavour_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

// Test configuration constants
const String MAILSLURP_API_BASE_URL = 'https://api.mailslurp.com';
const String MAILSLURP_API_KEY =
    "f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864";

// Test data constants
const String testEmail = 'alisson+1@fullpond.co';
const String testPassword = '12345678Aa';
const String testFullName = 'Test User';
const String testSignUpEmail = 'alisson+test001@fullpond.co';
const String testSignUpPassword = '12345678Aa';

// Shared test email for reuse
String? sharedTestEmail = "dada4d60-af97-4331-b756-c8af6752c1d6@mailslurp.biz";

/// Setup function to be called at the beginning of each test file
Future<void> setupIntegrationTest() async {
  // Only include integration test setup in debug/profile builds
  assert(() {
    if (const bool.fromEnvironment('INTEGRATION_TEST')) {
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    }
    return true;
  }());

  // Enable hierarchical logging to prevent the UnsupportedError
  hierarchicalLoggingEnabled = true;

  // Set flavor to development for integration tests (uses .env_qa)
  FlavorConfig.appFlavor = Flavor.development;
}

/// Setup function for individual tests
Future<void> setupTest() async {
  // Clear any existing preferences before each test
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

/// Cleanup function for individual tests
Future<void> cleanupTest() async {
  // Wait for any pending operations to complete
  await Future.delayed(const Duration(milliseconds: 1500));
}

/// Suppress upgrader warnings during tests
void suppressUpgraderWarnings() {
  // // Override print to filter out upgrader warnings
  // final originalPrint = print;
  // // Note: This is a simplified approach - in practice you might want to use
  // // a more sophisticated logging solution for test environments
  // print = (Object? object) {
  //   final message = object.toString();
  //   // Skip upgrader-related warnings during tests
  //   if (message.contains('upgrader:') &&
  //       (message.contains('debugDisplayAlways') ||
  //           message.contains('debugDisplayOnce') ||
  //           message.contains('debugLogging'))) {
  //     return; // Suppress these messages
  //   }
  //   originalPrint(object);
  // };
}
