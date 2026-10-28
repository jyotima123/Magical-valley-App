// integration_test/login_tests.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'test_helpers.dart';
import 'navigation_helpers.dart';
import 'auth_helpers.dart';

class RoleTestCredentials {
  const RoleTestCredentials._({
    required this.role,
    required this.description,
    required this.email,
    required this.password,
  });

  final String role;
  final String description;
  final String email;
  final String password;

  bool get isConfigured => email.isNotEmpty && password.isNotEmpty;

  static const String _regularEmail =
      String.fromEnvironment('LOGIN_TEST_REGULAR_EMAIL');
  static const String _regularPassword =
      String.fromEnvironment('LOGIN_TEST_REGULAR_PASSWORD');
  static const String _superadminEmail =
      String.fromEnvironment('LOGIN_TEST_SUPERADMIN_EMAIL');
  static const String _superadminPassword =
      String.fromEnvironment('LOGIN_TEST_SUPERADMIN_PASSWORD');
  static const String _adminEmail =
      String.fromEnvironment('LOGIN_TEST_ADMIN_EMAIL');
  static const String _adminPassword =
      String.fromEnvironment('LOGIN_TEST_ADMIN_PASSWORD');

  static RoleTestCredentials regular() => const RoleTestCredentials._(
        role: 'regular',
        description: 'Regular',
        email: _regularEmail,
        password: _regularPassword,
      );

  static RoleTestCredentials superadmin() => const RoleTestCredentials._(
        role: 'superadmin',
        description: 'Superadmin',
        email: _superadminEmail,
        password: _superadminPassword,
      );

  static RoleTestCredentials admin() => const RoleTestCredentials._(
        role: 'admin',
        description: 'Admin',
        email: _adminEmail,
        password: _adminPassword,
      );
}

Future<void> _runLoginFlowForUser(
  WidgetTester tester,
  RoleTestCredentials user,
) async {
  print('🔐 Starting login flow for ${user.role} user (${user.email})');

  await app.main();
  await tester.pumpAndSettle();

  await waitForAppToBeReady(tester);
  await handleOnboarding(tester);
  await ensureOnWelcomeScreen(tester);
  await navigateToLogin(tester);
  await performLogin(tester, user.email, user.password);
  await verifyHomeScreen(tester);
  await verifyTokenValidity();
  await logoutUser(tester);

  // Wait for logout to complete and ensure we're back on welcome screen.
  await tester.pumpAndSettle(const Duration(seconds: 2));
  await ensureOnWelcomeScreen(tester);
  await tester.pumpAndSettle();
  print('✅ Completed login & logout flow for ${user.role} user (${user.email})');
}

void main() {
  group('Login Tests', () {
    setUpAll(() async {
      await setupIntegrationTest();
      suppressUpgraderWarnings();
    });

    setUp(() async {
      await setupTest();
    });

    tearDown(() async {
      await cleanupTest();
    });

    testWidgets('Complete user journey: onboarding → login → verify token', (
      tester,
    ) async {
      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await tester.pumpAndSettle();

      // Step 1: Handle onboarding
      await handleOnboarding(tester);

      // Step 2: Navigate to login
      await navigateToLogin(tester);

      // Step 3: Perform login
      await performLogin(tester, testEmail, testPassword);

      // Step 4: Verify we're on home screen
      await verifyHomeScreen(tester);

      // Step 5: Verify token validity
      await verifyTokenValidity();

      // IMPROVED: More thorough cleanup
      await tester.pumpAndSettle();

      // Allow any pending operations to complete
      await Future.delayed(const Duration(seconds: 1));

      // Force any remaining async operations to complete
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('Login with invalid credentials shows error', (tester) async {
      print('🚀 Starting login with invalid credentials test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();

      // Wait for app to be fully ready
      await waitForAppToBeReady(tester);

      // Step 1: Handle onboarding (if needed)
      await handleOnboarding(tester);

      // Step 2: Ensure we're on the right screen for navigation
      await ensureOnWelcomeScreen(tester);

      // Step 3: If already logged in, log out first
      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        print('⚠️ Already logged in, logging out for test...');
        await logoutUser(tester);
        await ensureOnWelcomeScreen(
          tester,
        ); // Ensure we're back on the welcome screen
      }

      // Step 4: Navigate to login
      await navigateToLogin(tester);

      // Step 5: Perform login with invalid credentials
      await performLogin(tester, 'invalid@email.com', 'wrongpassword');

      // Step 6: Verify error is shown
      await verifyLoginError(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });
  });

  group('Role-based login flows', () {
    testWidgets('Regular user can login and logout', (tester) async {
      final user = RoleTestCredentials.regular();
      if (!user.isConfigured) {
        print(
          '⚠️ Missing LOGIN_TEST_REGULAR_EMAIL / LOGIN_TEST_REGULAR_PASSWORD. '
          'Skipping regular role test.',
        );
        return;
      }

      await _runLoginFlowForUser(tester, user);
    });

    testWidgets('Superadmin user can login and logout', (tester) async {
      final user = RoleTestCredentials.superadmin();
      if (!user.isConfigured) {
        print(
          '⚠️ Missing LOGIN_TEST_SUPERADMIN_EMAIL / LOGIN_TEST_SUPERADMIN_PASSWORD. '
          'Skipping superadmin role test.',
        );
        return;
      }

      await _runLoginFlowForUser(tester, user);
    });

    testWidgets('Admin user can login and logout for assigned organization', (
      tester,
    ) async {
      final user = RoleTestCredentials.admin();
      if (!user.isConfigured) {
        print(
          '⚠️ Missing LOGIN_TEST_ADMIN_EMAIL / LOGIN_TEST_ADMIN_PASSWORD. '
          'Skipping admin role test.',
        );
        return;
      }

      await _runLoginFlowForUser(tester, user);
    });
  });
}
