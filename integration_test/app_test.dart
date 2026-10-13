// test/integration_test/app_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';

void main() {
  // Only include integration test setup in debug/profile builds
  assert(() {
    if (const bool.fromEnvironment('INTEGRATION_TEST')) {
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    }
    return true;
  }());

  group('App Integration Tests', () {
    testWidgets('Complete user flow: skip intro, login, and verify token', (
      tester,
    ) async {
      // Test credentials - replace with your test account
      const testEmail = 'test@example.com';
      const testPassword = 'testPassword123';

      // Start the app
      await app.main();
      await tester.pumpAndSettle();

      // Step 1: Skip onboarding/intro
      await _skipOnboarding(tester);

      // Step 2: Navigate to login form
      await _navigateToLogin(tester);

      // Step 3: Fill login form and submit
      await _performLogin(tester, testEmail, testPassword);

      // Step 4: Verify successful login (check if we're on the home screen)
      await _verifyLoginSuccess(tester);

      // Step 5: Verify API token is valid
      await _verifyTokenValidity(tester);
    });

    testWidgets('Login with invalid credentials should show error', (
      tester,
    ) async {
      const invalidEmail = 'invalid@example.com';
      const invalidPassword = 'wrongpassword';

      await app.main();
      await tester.pumpAndSettle();

      await _skipOnboarding(tester);
      await _navigateToLogin(tester);
      await _performLogin(tester, invalidEmail, invalidPassword);

      // Verify error message is shown
      await _verifyLoginError(tester);
    });
  });
}

// Helper function to skip onboarding
Future<void> _skipOnboarding(WidgetTester tester) async {
  // Look for onboarding elements and skip them
  // This depends on your OnboardingScreen implementation
  // You might need to tap "Skip" or "Next" buttons

  // Wait for onboarding screen to load
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Look for skip button or navigation elements
  final skipButton = find.text('Skip');
  if (skipButton.evaluate().isNotEmpty) {
    await tester.tap(skipButton);
    await tester.pumpAndSettle();
  }

  // If there are multiple onboarding screens, you might need to tap multiple times
  // Or look for a "Get Started" button
  final getStartedButton = find.text('Get Started');
  if (getStartedButton.evaluate().isNotEmpty) {
    await tester.tap(getStartedButton);
    await tester.pumpAndSettle();
  }
}

// Helper function to navigate to login form
Future<void> _navigateToLogin(WidgetTester tester) async {
  // Look for the LOGIN button on the welcome screen
  final loginButton = find.text('LOGIN');
  expect(loginButton, findsOneWidget);

  await tester.tap(loginButton);
  await tester.pumpAndSettle();

  // Wait for the login form animation to complete
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

// Helper function to perform login
Future<void> _performLogin(
  WidgetTester tester,
  String email,
  String password,
) async {
  // Reveal email login form if necessary
  final continueWithEmailText = find.text('CONTINUE WITH EMAIL');
  if (continueWithEmailText.evaluate().isNotEmpty) {
    final continueWithEmailButton = find.ancestor(
      of: continueWithEmailText,
      matching: find.byType(ElevatedButton),
    );
    if (continueWithEmailButton.evaluate().isNotEmpty) {
      await tester.tap(continueWithEmailButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
  }

  if (find.widgetWithText(TextField, 'Enter your email').evaluate().isEmpty) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  // Find email field by looking for the hint text
  final emailField = find.widgetWithText(TextField, 'Enter your email');
  expect(emailField, findsOneWidget);

  // Find password field
  final passwordField = find.widgetWithText(TextField, 'Enter your password');
  expect(passwordField, findsOneWidget);

  // Enter credentials
  await tester.enterText(emailField, email);
  await tester.enterText(passwordField, password);

  // Dismiss keyboard if needed
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  // Find and tap login button
  final loginSubmitButton = find.widgetWithText(ElevatedButton, 'LOGIN');
  expect(loginSubmitButton, findsOneWidget);

  await tester.tap(loginSubmitButton);
  await tester.pumpAndSettle();

  // Wait for API call to complete
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

// Helper function to verify login success
Future<void> _verifyLoginSuccess(WidgetTester tester) async {
  // Check if we're on the RealChatScreen (home screen)
  // You might need to adjust this based on your RealChatScreen implementation

  // Look for elements that indicate successful login
  // This could be a specific widget, text, or app bar title

  // Option 1: Check for absence of login form
  final loginForm = find.text('LOGIN');
  expect(loginForm, findsNothing);

  // Option 2: Check for presence of home screen elements
  // Replace with actual widgets from your RealChatScreen
  // final homeScreenIndicator = find.byType(RealChatScreen);
  // expect(homeScreenIndicator, findsOneWidget);

  // Option 3: Check for specific text or widgets that appear after login
  // This depends on your RealChatScreen implementation
}

// Helper function to verify token validity
Future<void> _verifyTokenValidity(WidgetTester tester) async {
  // Get the current user from the API to verify token
  final apiService = SupabaseApiService.instance;
  final apiRepository = ApiRepository(apiService);

  try {
    final userResult = await apiRepository.getCurrentUser();

    // Verify the API call was successful
    expect(userResult, isNotNull);
    expect(userResult!.isSuccess, isTrue);

    // Additional checks on the user data
    if (userResult.userData != null) {
      expect(userResult.email, isNotNull);
      expect(userResult.userId, isNotNull);

      // You can add more specific checks based on your User model
      print('✅ Token is valid. User ID: ${userResult.userId}');
      print('✅ User email: ${userResult.email}');
    }
  } catch (e) {
    fail('Token validation failed: $e');
  }
}

// Helper function to verify login error
Future<void> _verifyLoginError(WidgetTester tester) async {
  // Look for error messages
  // This could be a SnackBar, error text, or alert dialog

  // Option 1: Check for SnackBar
  final snackBar = find.byType(SnackBar);
  if (snackBar.evaluate().isNotEmpty) {
    expect(snackBar, findsOneWidget);
  }

  // Option 2: Check for error text in the form
  final errorText = find.textContaining('error');
  if (errorText.evaluate().isNotEmpty) {
    expect(errorText, findsOneWidget);
  }

  // Option 3: Check that we're still on the login screen
  final loginButton = find.widgetWithText(ElevatedButton, 'LOGIN');
  expect(loginButton, findsOneWidget);
}
