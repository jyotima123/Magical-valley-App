// integration_test/test_config.dart

import 'dart:async' show FutureOr;

class TestConfig {
  static const String testEmail = 'test@example.com';
  static const String testPassword = 'testPassword123';
  static const String invalidEmail = 'invalid@example.com';
  static const String invalidPassword = 'wrongpassword';

  // Test environment configuration
  static const String testEnvironment = 'qa';

  // Timeout configurations
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 10);
  static const Duration animationTimeout = Duration(milliseconds: 500);
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Setup code that runs before all tests
  // You can initialize test-specific configurations here

  await testMain();

  // Cleanup code that runs after all tests
}
