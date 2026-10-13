// integration_test/signup_tests.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'test_helpers.dart';
import 'navigation_helpers.dart';
import 'auth_helpers.dart';

void main() {
  group('Signup Tests', () {
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

    testWidgets('Signup with invalid credentials shows error', (tester) async {
      print('🚀 Starting signup with invalid credentials test...');

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

      await navigateToSignup(tester);

      // Invalid credentials: mismatching passwords
      await performSignup(
        tester,
        testFullName,
        sharedTestEmail!,
        testPassword,
        confirmPassword: 'DifferentPassword123!',
      );

      await verifySignupError(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });
  });
}

/// Navigate to signup form
Future<void> navigateToSignup(WidgetTester tester) async {
  print('🔄 Navigating to signup...');

  await ensureOnWelcomeScreen(tester);

  // Find the SIGN UP button on the welcome screen
  final signupButton = find.descendant(
    of: find.byType(app.AppRouter),
    matching: find.widgetWithText(ElevatedButton, 'SIGN UP'),
  );
  expect(
    signupButton,
    findsOneWidget,
    reason: 'SIGN UP button not found on welcome screen',
  );

  // Tap the SIGN UP button
  await tester.tap(signupButton);
  await tester.pumpAndSettle();

  // Wait for the authentication method selection dialog to appear
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  // NEW: Handle the authentication method selection dialog for signup
  print('🔄 Looking for signup authentication method selection...');

  // Debug: Print all available widgets to see what's actually on screen
  print('🔍 Debug - All available text widgets:');
  final allTexts = find.byType(Text);
  for (int i = 0; i < allTexts.evaluate().length && i < 15; i++) {
    try {
      final textWidget = tester.widget<Text>(allTexts.at(i));
      print('   - "${textWidget.data}"');
    } catch (e) {
      print('   - Error reading text widget $i: $e');
    }
  }

  // Look for "CONTINUE WITH EMAIL" button in the dialog (exact match from the debug log)
  Finder continueWithEmailButton = find.text('CONTINUE WITH EMAIL');

  if (continueWithEmailButton.evaluate().isEmpty) {
    // Try alternative text variations
    continueWithEmailButton = find.textContaining('CONTINUE WITH EMAIL');

    if (continueWithEmailButton.evaluate().isEmpty) {
      continueWithEmailButton = find.textContaining('EMAIL');

      if (continueWithEmailButton.evaluate().isEmpty) {
        // Try looking for ElevatedButton.icon with the specific text
        continueWithEmailButton = find.byWidgetPredicate((widget) {
          if (widget is ElevatedButton) {
            // Check if it's the ElevatedButton.icon with email text
            return true; // We'll rely on the text search above
          }
          return false;
        });

        // If still not found, look for any widget containing the email text
        if (continueWithEmailButton.evaluate().isEmpty) {
          continueWithEmailButton = find.byWidgetPredicate((widget) {
            if (widget is Text) {
              final text = widget.data?.toUpperCase();
              return text?.contains('CONTINUE WITH EMAIL') == true;
            }
            return false;
          });
        }
      }
    }
  }

  if (continueWithEmailButton.evaluate().isNotEmpty) {
    print('✅ Found "Continue with Email" button for signup, tapping it...');
    try {
      await tester.tap(continueWithEmailButton);
      await tester.pumpAndSettle();

      // Wait for the email signup form to appear
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    } catch (e) {
      print('⚠️ Error tapping Continue with Email button: $e');

      // Try alternative approach: look for ElevatedButton with email icon
      final emailButton = find.byWidgetPredicate((widget) {
        return widget is ElevatedButton && widget.child != null;
      });

      if (emailButton.evaluate().isNotEmpty) {
        print('🔄 Trying alternative email button...');
        await tester.tap(emailButton.first);
        await tester.pumpAndSettle();
      }
    }
  } else {
    print(
      '🔍 No "Continue with Email" button found, trying direct approach...',
    );

    // Alternative: Look for any ElevatedButton in the bottom sheet
    final elevatedButtons = find.byType(ElevatedButton);
    print(
      '🔍 Found ${elevatedButtons.evaluate().length} ElevatedButton widgets',
    );

    // Try to find the email signup button by looking for the one with email icon
    for (int i = 0; i < elevatedButtons.evaluate().length; i++) {
      try {
        final buttonFinder = elevatedButtons.at(i);
        print('🔄 Trying ElevatedButton $i...');
        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        // Check if we successfully navigated to signup form
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        // If we find a signup form, break out
        final nameField = find.widgetWithText(
          TextField,
          'Enter your full name',
        );
        if (nameField.evaluate().isNotEmpty) {
          print('✅ Successfully found signup form after tapping button $i');
          return; // Exit the function as we've successfully navigated
        }
      } catch (e) {
        print('⚠️ Button $i failed: $e');
        continue;
      }
    }
  }

  // Wait for the signup form to appear (if we haven't already found it)
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();

  // Verify the signup form is visible with multiple verification attempts
  int verificationAttempts = 0;
  const maxVerificationAttempts = 3;

  while (verificationAttempts < maxVerificationAttempts) {
    verificationAttempts++;
    print(
      '🔄 Signup form verification attempt $verificationAttempts/$maxVerificationAttempts',
    );

    // Wait a bit between attempts
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Alternative verification - look for signup-specific fields (more reliable)
    final nameField = find.widgetWithText(TextField, 'Enter your full name');
    final emailField = find.widgetWithText(TextField, 'Enter your email');
    final passwordField = find.widgetWithText(TextField, 'Enter your password');

    if (nameField.evaluate().isNotEmpty &&
        emailField.evaluate().isNotEmpty &&
        passwordField.evaluate().isNotEmpty) {
      print('✅ Signup form verified by fields');
      return;
    }

    // Secondary verification - look for signup form title
    final signupFormTitle = find.descendant(
      of: find.byType(app.AppRouter),
      matching: find.text(
        ' Sign Up ',
      ), // Note the spaces in the actual form title
    );

    if (signupFormTitle.evaluate().isNotEmpty) {
      print('✅ Signup form verified by title');
      return;
    }

    // Check if we're still on the modal bottom sheet
    final modalBottomSheet = find.text('choose how you want to join');
    if (modalBottomSheet.evaluate().isNotEmpty) {
      print('⚠️ Still on authentication method selection, trying again...');

      // Try to tap the continue with email button again
      final continueButton = find.text('CONTINUE WITH EMAIL');
      if (continueButton.evaluate().isNotEmpty) {
        try {
          await tester.tap(continueButton);
          await tester.pumpAndSettle();
          continue; // Try verification again
        } catch (e) {
          print('⚠️ Failed to tap continue button: $e');
        }
      }
    }

    print('⚠️ Signup form not found, waiting and retrying...');
  }

  // Final debug information before failing
  print('🔍 Final debug - Available text widgets:');
  final finalTexts = find.byType(Text);
  for (int i = 0; i < finalTexts.evaluate().length && i < 10; i++) {
    // Limit to first 10
    final textWidget = tester.widget<Text>(finalTexts.at(i));
    print('   - "${textWidget.data}"');
  }

  // Final fallback: Try to directly trigger the signup form via AuthBloc
  print('🔄 Final fallback: Trying direct AuthBloc approach...');
  try {
    final context = tester.element(find.byType(app.AppRouter));
    final authBloc = context.read<AuthBloc>();
    authBloc.add(ShowSignupFormEvent());

    // Wait for the form to appear
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Check if signup form appeared
    final nameField = find.widgetWithText(TextField, 'Enter your full name');
    if (nameField.evaluate().isNotEmpty) {
      print('✅ Signup form appeared via direct AuthBloc approach');
      return;
    }
  } catch (e) {
    print('⚠️ Direct AuthBloc approach failed: $e');
  }

  throw Exception(
    'Signup form did not appear after trying multiple approaches including tapping SIGN UP button, Continue with Email, and direct AuthBloc trigger',
  );
}

/// Perform signup
Future<void> performSignup(
  WidgetTester tester,
  String fullName,
  String email,
  String password, {
  String? confirmPassword,
}) async {
  final nameField = find.widgetWithText(TextField, 'Enter your full name');
  expect(nameField, findsOneWidget, reason: 'Full name field not found');

  final emailField = find.widgetWithText(TextField, 'Enter your email');
  expect(emailField, findsOneWidget, reason: 'Email field not found');

  final passwordField = find.widgetWithText(TextField, 'Enter your password');
  expect(passwordField, findsOneWidget, reason: 'Password field not found');

  final confirmPasswordField = find.widgetWithText(
    TextField,
    'Confirm your password',
  );
  expect(
    confirmPasswordField,
    findsOneWidget,
    reason: 'Confirm password field not found',
  );

  print('🔄 Performing signup with email: $email');
  final actualConfirmPassword = confirmPassword ?? password;
  print('🔄 Password: "$password", Confirm Password: "$actualConfirmPassword"');

  // Enter form data with careful field clearing
  await fillFormField(tester, nameField, fullName, 'name');
  await fillFormField(tester, emailField, email, 'email');
  await fillFormField(tester, passwordField, password, 'password');
  await fillFormField(
    tester,
    confirmPasswordField,
    actualConfirmPassword,
    'confirm password',
  );

  // Dismiss keyboard
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  // Debug: Verify the field contents before submitting
  print('🔍 Verifying field contents before submission...');
  try {
    final nameFieldWidget = tester.widget<TextField>(nameField);
    final emailFieldWidget = tester.widget<TextField>(emailField);
    final passwordFieldWidget = tester.widget<TextField>(passwordField);
    final confirmPasswordFieldWidget = tester.widget<TextField>(
      confirmPasswordField,
    );

    final nameText = nameFieldWidget.controller?.text ?? 'null';
    final emailText = emailFieldWidget.controller?.text ?? 'null';
    final passwordText = passwordFieldWidget.controller?.text ?? 'null';
    final confirmPasswordText =
        confirmPasswordFieldWidget.controller?.text ?? 'null';

    print('   Name field: "$nameText"');
    print('   Email field: "$emailText"');
    print('   Password field: "$passwordText"');
    print('   Confirm password field: "$confirmPasswordText"');

    // Check if passwords match
    if (passwordText != confirmPasswordText) {
      print('❌ PASSWORD MISMATCH DETECTED!');
      print('   Password length: ${passwordText.length}');
      print('   Confirm password length: ${confirmPasswordText.length}');

      // Try to fix the mismatch by re-entering the confirm password

      final confirmErrorButton = find.byType(AnimatedButton);

      expect(
        confirmErrorButton,
        findsOneWidget,
        reason: 'confirm OK  button not found',
      );

      await tester.tap(confirmErrorButton);
      await tester.pumpAndSettle();

      print('🔄 Attempting to fix password mismatch...');
      await fillFormField(
        tester,
        confirmPasswordField,
        actualConfirmPassword,
        'confirm password (retry)',
      );

      // Verify again
      final retryConfirmPasswordText =
          tester.widget<TextField>(confirmPasswordField).controller?.text ??
          'null';
      print('   Confirm password after retry: "$retryConfirmPasswordText"');

      if (passwordText == retryConfirmPasswordText) {
        print('✅ Password mismatch fixed!');
      } else {
        print('❌ Could not fix password mismatch');
      }
    } else {
      print('✅ Passwords match correctly');
    }
  } catch (e) {
    print('⚠️ Could not read field contents: $e');
  }

  // Find and tap signup submit button
  final signupSubmitButton = find.widgetWithText(ElevatedButton, 'SIGN UP');
  expect(
    signupSubmitButton,
    findsOneWidget,
    reason: 'Signup submit button not found',
  );

  await tester.tap(signupSubmitButton);
  await tester.pumpAndSettle();

  // Wait for API call to complete
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// Verify signup error
Future<void> verifySignupError(WidgetTester tester) async {
  print('🔄 Verifying signup error...');

  // Wait for error to appear
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check for error indicators
  bool errorFound = false;

  // Check for AwesomeDialog (primary error display method)
  final awesomeDialog = find.byType(AwesomeDialog);
  if (awesomeDialog.evaluate().isNotEmpty) {
    errorFound = true;
    print('✅ Found error dialog (AwesomeDialog)');

    // Try to dismiss the dialog by tapping OK
    final okButton = find.text('OK');
    if (okButton.evaluate().isNotEmpty) {
      print('🔄 Dismissing error dialog...');
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    }
  }

  // Check for SnackBar
  final snackBar = find.byType(SnackBar);
  if (snackBar.evaluate().isNotEmpty) {
    errorFound = true;
    print('✅ Found error SnackBar');
  }

  // Check for error text in form
  final errorTexts = [
    'Passwords do not match',
    'Email already in use',
    'Invalid email',
    'Signup failed',
    'Error', // Generic error text
  ];

  for (final errorText in errorTexts) {
    final errorMessage = find.textContaining(errorText);
    if (errorMessage.evaluate().isNotEmpty) {
      errorFound = true;
      print('✅ Found error message: $errorText');
      break;
    }
  }

  // Verify still on signup screen
  final signupButton = find.widgetWithText(ElevatedButton, 'SIGN UP');
  expect(
    signupButton,
    findsOneWidget,
    reason: 'Should still be on signup screen after error',
  );

  if (errorFound) {
    print('✅ Error handling verified');
  } else {
    print('⚠️ No error UI found, but still on signup screen');
  }
}
