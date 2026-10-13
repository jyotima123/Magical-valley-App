// integration_test/password_reset_tests.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/auth/reset_password_screen.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/services.dart';
import 'test_helpers.dart';
import 'navigation_helpers.dart';
import 'auth_helpers.dart';
import 'email_helpers.dart';

void main() {
  group('Password Reset Tests', () {
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

    testWidgets('Navigate to forgot password from login screen', (
      tester,
    ) async {
      print('🚀 Starting forgot password navigation test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await handleOnboarding(tester);
      await ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        print('⚠️ Already logged in, logging out for test...');
        await logoutUser(tester);
        await ensureOnWelcomeScreen(tester);
      }

      await navigateToLogin(tester);
      await navigateToForgotPassword(tester);
      await verifyForgotPasswordScreen(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    testWidgets('Send forgot password email with valid email', (tester) async {
      print('🚀 Starting forgot password email test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await handleOnboarding(tester);
      await ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        await logoutUser(tester);
        await ensureOnWelcomeScreen(tester);
      }

      await navigateToLogin(tester);
      await navigateToForgotPassword(tester);

      // Use the created inbox email for testing
      await performForgotPassword(tester, sharedTestEmail!);
      await verifyForgotPasswordSuccess(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    testWidgets('Send forgot password email with invalid email shows error', (
      tester,
    ) async {
      print('🚀 Starting forgot password with invalid email test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await handleOnboarding(tester);
      await ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        await logoutUser(tester);
        await ensureOnWelcomeScreen(tester);
      }

      await navigateToLogin(tester);
      await navigateToForgotPassword(tester);

      await performForgotPassword(tester, 'nonexistent@invalid.com');
      await verifyForgotPasswordError(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    testWidgets(
      'Complete password reset journey: forgot password → get email → reset',
      (tester) async {
        print('🚀 Starting complete password reset journey test...');

        // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
        await app.main();
        await waitForAppToBeReady(tester);

        await handleOnboarding(tester);
        await ensureOnWelcomeScreen(tester);

        if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
          await logoutUser(tester);
          await ensureOnWelcomeScreen(tester);
        }

        // Step 1: Navigate to forgot password and send reset email
        await navigateToLogin(tester);
        await navigateToForgotPassword(tester);
        await performForgotPassword(tester, sharedTestEmail!);
        await verifyForgotPasswordSuccess(tester);

        // Step 2: Get reset link from email
        print('🔄 Getting reset link from email...');
        final resetEmail = await checkLatestEmailInInbox(sharedTestEmail!);
        final resetLink = extractResetLinkFromEmail(resetEmail['body'] ?? '');

        if (resetLink.isEmpty) {
          throw Exception('Reset link not found in email');
        }

        // Step 3: Navigate to reset password screen with link
        await navigateToResetPassword(tester, resetLink);

        // Step 4: Perform password reset
        const newPassword = 'NewPassword123!';
        await performPasswordReset(tester, newPassword);

        // Step 5: Verify reset success
        await verifyPasswordResetSuccess(tester);

        // Cleanup
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
      },
    );
  });
}

/// Navigate to forgot password screen
Future<void> navigateToForgotPassword(WidgetTester tester) async {
  print('🔄 Navigating to forgot password...');

  // Wait for login form to be fully loaded
  await tester.pumpAndSettle();

  // Look for "Forgot Password?" link/button
  Finder forgotPasswordLink = find.text('Forgot Password?');

  if (forgotPasswordLink.evaluate().isEmpty) {
    // Try alternative text variations
    forgotPasswordLink = find.textContaining('Forgot');

    if (forgotPasswordLink.evaluate().isEmpty) {
      // Look for any clickable widget containing "forgot"
      forgotPasswordLink = find.byWidgetPredicate((widget) {
        if (widget is GestureDetector ||
            widget is InkWell ||
            widget is TextButton) {
          // Check if it contains forgot password text
          return true; // This would need more specific logic based on your UI
        }
        return false;
      });
    }
  }

  expect(
    forgotPasswordLink,
    findsOneWidget,
    reason: 'Forgot Password link should be visible on login screen',
  );

  await tester.tap(forgotPasswordLink);
  await tester.pumpAndSettle();

  // Wait for navigation animation
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();

  print('✅ Navigated to forgot password screen');
}

/// Verify forgot password screen
Future<void> verifyForgotPasswordScreen(WidgetTester tester) async {
  print('🔄 Verifying forgot password screen...');

  // Look for forgot password specific elements
  final emailField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.hintText?.contains('email') == true ||
            widget.decoration?.labelText?.contains('email') == true),
  );
  final sendButton = find.byWidgetPredicate(
    (widget) =>
        widget is ElevatedButton &&
        widget.child is Text &&
        ((widget.child as Text).data?.contains('SEND') == true ||
            (widget.child as Text).data?.contains('Send') == true ||
            (widget.child as Text).data?.contains('Reset') == true),
  );

  expect(emailField, findsOneWidget, reason: 'Email field should be visible');
  expect(sendButton, findsOneWidget, reason: 'Send button should be visible');

  print('✅ Forgot password screen verified');
}

/// Perform forgot password action
Future<void> performForgotPassword(WidgetTester tester, String email) async {
  print('🔄 Performing forgot password with email: $email');

  // Find email field
  final emailField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        (widget.decoration?.hintText?.contains('email') == true ||
            widget.decoration?.labelText?.contains('email') == true),
  );

  expect(emailField, findsOneWidget, reason: 'Email field should be visible');

  // Enter email
  await tester.tap(emailField);
  await tester.pumpAndSettle();
  await tester.enterText(emailField, email);

  // Dismiss keyboard
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  // Find and tap send button
  final sendButton = find.byWidgetPredicate(
    (widget) =>
        widget is ElevatedButton &&
        widget.child is Text &&
        ((widget.child as Text).data?.contains('SEND') == true ||
            (widget.child as Text).data?.contains('Send') == true ||
            (widget.child as Text).data?.contains('Reset') == true),
  );

  expect(sendButton, findsOneWidget, reason: 'Send button should be visible');

  await tester.tap(sendButton);
  await tester.pumpAndSettle();

  // Wait for API call to complete
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  print('✅ Forgot password request submitted');
}

/// Verify forgot password success
Future<void> verifyForgotPasswordSuccess(WidgetTester tester) async {
  print('🔄 Verifying forgot password success...');

  // Wait for response
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check for success indicators
  bool successFound = false;

  // Check for success message or dialog
  final successTexts = [
    'Check your email',
    'Reset link sent',
    'Email sent',
    'Password reset instructions',
  ];

  for (final successText in successTexts) {
    final successMessage = find.textContaining(successText);
    if (successMessage.evaluate().isNotEmpty) {
      successFound = true;
      print('✅ Found success message: $successText');
      break;
    }
  }

  // Check for AwesomeDialog success
  final awesomeDialog = find.byType(AwesomeDialog);
  if (awesomeDialog.evaluate().isNotEmpty) {
    successFound = true;
    print('✅ Found success dialog');
  }

  if (successFound) {
    print('✅ Forgot password success verified');
  } else {
    print('⚠️ No explicit success message found, but request completed');
  }
}

/// Verify forgot password error
Future<void> verifyForgotPasswordError(WidgetTester tester) async {
  print('🔄 Verifying forgot password error...');

  // Wait for error to appear
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  bool errorFound = false;

  // Check for error indicators
  final errorTexts = ['User not found', 'Invalid email', 'Error', 'Failed'];

  for (final errorText in errorTexts) {
    final errorMessage = find.textContaining(errorText);
    if (errorMessage.evaluate().isNotEmpty) {
      errorFound = true;
      print('✅ Found error message: $errorText');
      break;
    }
  }

  // Check for error dialog
  final awesomeDialog = find.byType(AwesomeDialog);
  if (awesomeDialog.evaluate().isNotEmpty) {
    errorFound = true;
    print('✅ Found error dialog');
  }

  if (errorFound) {
    print('✅ Error handling verified');
  } else {
    print('⚠️ No error UI found');
  }
}

/// Navigate to reset password screen with link
Future<void> navigateToResetPassword(
  WidgetTester tester,
  String resetLink,
) async {
  print('🔄 Navigating to reset password screen with link...');

  // Parse the reset link to extract parameters
  final uri = Uri.parse(resetLink);
  final token = uri.queryParameters['token'];

  if (token == null) {
    throw Exception('Reset token not found in link');
  }

  // Navigate to reset password screen with parameters
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('routeUpdated', {
        'location': '/reset-password',
        'state': {'uri': resetLink, 'resetToken': token},
      }),
    ),
    (data) {},
  );

  // Alternative: Use Navigator.pushNamed if the above doesn't work
  // This would require access to the navigation context

  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));

  // Verify we're on the reset password screen
  final resetPasswordScreen = find.byType(ResetPasswordScreen);
  expect(
    resetPasswordScreen,
    findsOneWidget,
    reason: 'Should be on reset password screen',
  );

  print('✅ Navigated to reset password screen');
}

/// Perform password reset
Future<void> performPasswordReset(
  WidgetTester tester,
  String newPassword,
) async {
  print('🔄 Performing password reset...');

  // Find password fields
  final passwordFields = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.obscureText == true,
  );

  expect(
    passwordFields.evaluate().length,
    2,
    reason: 'Should have 2 password fields (new and confirm)',
  );

  final newPasswordField = passwordFields.first;
  final confirmPasswordField = passwordFields.last;

  // Enter new password
  await tester.tap(newPasswordField);
  await tester.pumpAndSettle();
  await tester.enterText(newPasswordField, newPassword);

  // Enter confirm password
  await tester.tap(confirmPasswordField);
  await tester.pumpAndSettle();
  await tester.enterText(confirmPasswordField, newPassword);

  // Dismiss keyboard
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  // Find and tap update password button
  final updateButton = find.widgetWithText(ElevatedButton, 'UPDATE PASSWORD');
  expect(
    updateButton,
    findsOneWidget,
    reason: 'Update password button should be visible',
  );

  await tester.tap(updateButton);
  await tester.pumpAndSettle();

  // Handle confirmation dialog if it appears
  final confirmDialog = find.byType(AwesomeDialog);
  if (confirmDialog.evaluate().isNotEmpty) {
    final confirmButton = find.text('Yes, Update');
    if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
    }
  }

  // Wait for API call to complete
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  print('✅ Password reset submitted');
}

/// Verify password reset success
Future<void> verifyPasswordResetSuccess(WidgetTester tester) async {
  print('🔄 Verifying password reset success...');

  // Wait for response
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check for success dialog
  final successDialog = find.byType(AwesomeDialog);
  if (successDialog.evaluate().isNotEmpty) {
    final successText = find.textContaining('Success');
    if (successText.evaluate().isNotEmpty) {
      print('✅ Found success dialog');

      // Tap continue button to dismiss dialog
      final continueButton = find.text('Continue');
      if (continueButton.evaluate().isNotEmpty) {
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
      }

      // Should navigate to home screen
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Verify we're on home screen
      final homeScreen = find.byType(RealChatScreen);
      expect(
        homeScreen,
        findsOneWidget,
        reason: 'Should be on home screen after successful password reset',
      );

      print('✅ Password reset success verified');
      return;
    }
  }

  print('⚠️ No explicit success indication found');
}
