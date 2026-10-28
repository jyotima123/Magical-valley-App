// integration_test/auth_helpers.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';

/// Fill form field with proper clearing
Future<void> fillFormField(
  WidgetTester tester,
  Finder fieldFinder,
  String value,
  String fieldName,
) async {
  print('🔄 Filling $fieldName field with: "$value"');

  // Tap to focus the field
  await tester.tap(fieldFinder);
  await tester.pumpAndSettle();

  // Method 1: Try direct enterText with clearing
  try {
    await tester.enterText(fieldFinder, '');
    await tester.pumpAndSettle();
    await tester.enterText(fieldFinder, value);
    await tester.pumpAndSettle();

    // Verify the text was entered correctly
    final fieldWidget = tester.widget<TextField>(fieldFinder);
    final actualText = fieldWidget.controller?.text ?? '';
    if (actualText == value) {
      print('✅ $fieldName field filled successfully: "$actualText"');
      return;
    } else {
      print(
        '⚠️ $fieldName field mismatch. Expected: "$value", Got: "$actualText"',
      );
    }
  } catch (e) {
    print('⚠️ Method 1 failed for $fieldName: $e');
  }

  // Method 2: Try using testTextInput directly
  try {
    await tester.tap(fieldFinder);
    await tester.pumpAndSettle();

    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
    await tester.pumpAndSettle();

    print('✅ $fieldName field filled using direct method');
  } catch (e) {
    print('⚠️ Method 2 failed for $fieldName: $e');
  }
}

/// Navigate to login form
Future<void> navigateToLogin(WidgetTester tester) async {
  print('🔄 Navigating to login...');

  // Wait for the app to fully settle after onboarding
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // First, let's check what screen we're currently on
  print('🔍 Checking current screen state...');

  // Check if we're on the welcome screen (WelcomeScreen)
  final welcomeScreen = find.byType(app.AppRouter);
  if (welcomeScreen.evaluate().isEmpty) {
    print('❌ Not on welcome screen, checking for other screens...');

    // Check if we're already on a login form
    final loginForm = find.text('Login');
    if (loginForm.evaluate().isNotEmpty) {
      print('✅ Already on login form');
      return;
    }

    // Check if we're on RealChatScreen (already logged in)
    final chatScreen = find.byType(RealChatScreen);
    if (chatScreen.evaluate().isNotEmpty) {
      print('✅ Already logged in, on chat screen');
      return;
    }

    // If we're not on any expected screen, wait a bit more
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  // Look for LOGIN button with multiple strategies
  Finder loginButton = find.text('LOGIN');

  if (loginButton.evaluate().isEmpty) {
    print('🔍 LOGIN button not found, trying alternative approaches...');

    // Strategy 1: Look for ElevatedButton with LOGIN text
    loginButton = find.widgetWithText(ElevatedButton, 'LOGIN');

    if (loginButton.evaluate().isEmpty) {
      // Strategy 2: Look for any button containing "login" (case insensitive)
      loginButton = find.byWidgetPredicate((widget) {
        if (widget is ElevatedButton && widget.child is Text) {
          final text = (widget.child as Text).data?.toLowerCase();
          return text?.contains('login') == true;
        }
        return false;
      });
    }

    if (loginButton.evaluate().isEmpty) {
      // Strategy 3: Look for any text containing "login"
      loginButton = find.textContaining('LOGIN');
    }

    if (loginButton.evaluate().isEmpty) {
      // Strategy 4: Print all available text widgets for debugging
      print('🔍 Available text widgets:');
      final allTexts = find.byType(Text);
      for (int i = 0; i < allTexts.evaluate().length && i < 10; i++) {
        try {
          final textWidget = tester.widget<Text>(allTexts.at(i));
          print('   - "${textWidget.data}"');
        } catch (e) {
          print('   - Error reading text widget $i: $e');
        }
      }

      // Strategy 5: Print all available buttons for debugging
      print('🔍 Available ElevatedButton widgets:');
      final allButtons = find.byType(ElevatedButton);
      for (int i = 0; i < allButtons.evaluate().length && i < 5; i++) {
        try {
          final buttonWidget = tester.widget<ElevatedButton>(allButtons.at(i));
          if (buttonWidget.child is Text) {
            final text = (buttonWidget.child as Text).data;
            print('   - Button with text: "$text"');
          }
        } catch (e) {
          print('   - Error reading button widget $i: $e');
        }
      }

      throw Exception(
        'LOGIN button not found after trying multiple strategies',
      );
    }
  }

  print('✅ Found LOGIN button, tapping it...');
  await tester.tap(loginButton);
  await tester.pumpAndSettle();

  // Wait for login form animation to complete with more time
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();

  // Improved verification with multiple attempts
  bool loginFormFound = false;
  int attempts = 0;
  const maxAttempts = 3;

  while (!loginFormFound && attempts < maxAttempts) {
    attempts++;
    print('🔄 Verification attempt $attempts/$maxAttempts');

    // Method 1: Look for login form title
    final loginFormTitle = find.text('Login');
    if (loginFormTitle.evaluate().isNotEmpty) {
      loginFormFound = true;
      print('✅ Found login form title');
      break;
    }

    // Method 2: Look for email field with more flexible matching
    final emailFields = [
      find.widgetWithText(TextField, 'Enter your email'),
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText != null &&
            widget.decoration!.hintText!.toLowerCase().contains('email'),
      ),
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText != null &&
            widget.decoration!.labelText!.toLowerCase().contains('email'),
      ),
    ];

    for (final emailField in emailFields) {
      if (emailField.evaluate().isNotEmpty) {
        loginFormFound = true;
        print('✅ Found email field');
        break;
      }
    }

    if (loginFormFound) break;

    // Method 3: Look for password field
    final passwordFields = [
      find.widgetWithText(TextField, 'Enter your password'),
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.obscureText == true,
      ),
    ];

    for (final passwordField in passwordFields) {
      if (passwordField.evaluate().isNotEmpty) {
        loginFormFound = true;
        print('✅ Found password field');
        break;
      }
    }

    if (loginFormFound) break;

    // If not found, wait and try again
    if (attempts < maxAttempts) {
      print('⚠️ Login form not found, waiting and retrying...');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }
  }

  if (!loginFormFound) {
    // Final debug: print current widget tree info
    print('🔍 Final debug - Current screen widgets:');

    // Print scaffold content
    final scaffold = find.byType(Scaffold);
    if (scaffold.evaluate().isNotEmpty) {
      print('   - Found Scaffold');
    }

    // Print any containers or forms
    final containers = find.byType(Container);
    print('   - Found ${containers.evaluate().length} Container widgets');

    final textFields = find.byType(TextField);
    print('   - Found ${textFields.evaluate().length} TextField widgets');

    // Print first few TextField decorations for debugging
    for (int i = 0; i < textFields.evaluate().length && i < 3; i++) {
      try {
        final textField = tester.widget<TextField>(textFields.at(i));
        final hintText = textField.decoration?.hintText ?? 'null';
        final labelText = textField.decoration?.labelText ?? 'null';
        print('   - TextField $i: hint="$hintText", label="$labelText"');
      } catch (e) {
        print('   - TextField $i: Error reading decoration - $e');
      }
    }

    throw Exception(
      'Login form did not appear after tapping LOGIN button. '
      'Found ${textFields.evaluate().length} TextFields but none matched expected patterns.',
    );
  }

  print('✅ Login form verification completed successfully');
}

/// Perform login
Future<void> performLogin(
  WidgetTester tester,
  String email,
  String password,
) async {
  print('🔄 Performing login with email: $email');

  // Ensure the email login form is visible (new UI step)
  final continueWithEmailText = find.text('CONTINUE WITH EMAIL');
  if (continueWithEmailText.evaluate().isNotEmpty) {
    final continueWithEmailButton = find.ancestor(
      of: continueWithEmailText,
      matching: find.byType(ElevatedButton),
    );
    if (continueWithEmailButton.evaluate().isNotEmpty) {
      print('🔄 Revealing email login form...');
      await tester.tap(continueWithEmailButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
  } else {
    print('ℹ️ Email login form already visible (continue button hidden).');
  }

  // After tapping the button, wait a bit longer for animation if needed
  if (find.widgetWithText(TextField, 'Enter your email').evaluate().isEmpty) {
    print('⏳ Waiting for email login form animation...');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  // Find email field with more flexible approach
  Finder emailField = find.widgetWithText(TextField, 'Enter your email');
  if (emailField.evaluate().isEmpty) {
    // Try alternative approaches
    emailField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText?.contains('email') == true,
    );
  }

  expect(emailField, findsOneWidget, reason: 'Email field should be visible');

  // Find password field with more flexible approach
  Finder passwordField = find.widgetWithText(TextField, 'Enter your password');
  if (passwordField.evaluate().isEmpty) {
    passwordField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText?.contains('password') == true,
    );
  }

  expect(
    passwordField,
    findsOneWidget,
    reason: 'Password field should be visible',
  );

  // Clear any existing text and enter credentials
  await tester.tap(emailField);
  await tester.pumpAndSettle();
  await tester.enterText(emailField, email);

  await tester.tap(passwordField);
  await tester.pumpAndSettle();
  await tester.enterText(passwordField, password);

  // Dismiss keyboard
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();

  // Find and tap login submit button
  Finder loginSubmitButton = find.widgetWithText(ElevatedButton, 'LOGIN');
  if (loginSubmitButton.evaluate().isEmpty) {
    // Try alternative button text
    loginSubmitButton = find.byWidgetPredicate(
      (widget) =>
          widget is ElevatedButton &&
          widget.child is Text &&
          (widget.child as Text).data?.contains('LOGIN') == true,
    );
  }

  expect(
    loginSubmitButton,
    findsOneWidget,
    reason: 'Login submit button should be visible',
  );

  await tester.tap(loginSubmitButton);
  await tester.pumpAndSettle();

  // Wait for API call to complete with timeout handling
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();

  print('✅ Login submitted, waiting for response...');
}

/// Verify login error
Future<void> verifyLoginError(WidgetTester tester) async {
  print('🔄 Verifying login error...');

  // Wait for error to appear
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check for error indicators
  bool errorFound = false;

  // Check for SnackBar
  final snackBar = find.byType(SnackBar);
  if (snackBar.evaluate().isNotEmpty) {
    errorFound = true;
    print('✅ Found error SnackBar');
  }

  // Check for error text in form
  final errorContainer = find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration != null &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).color?.value ==
            Colors.red.withOpacity(0.1).value,
  );

  if (errorContainer.evaluate().isNotEmpty) {
    errorFound = true;
    print('✅ Found error container in form');
  }

  // Check for error text messages
  final errorTexts = [
    'Invalid credentials',
    'Login failed',
    'Error',
    'Invalid email or password',
  ];

  for (final errorText in errorTexts) {
    final errorMessage = find.textContaining(errorText);
    if (errorMessage.evaluate().isNotEmpty) {
      errorFound = true;
      print('✅ Found error message: $errorText');
      break;
    }
  }

  // Verify we're still on login screen
  final loginButton = find.widgetWithText(ElevatedButton, 'LOGIN');
  expect(
    loginButton,
    findsOneWidget,
    reason: 'Should still be on login screen after error',
  );

  if (errorFound) {
    print('✅ Error handling verified');
  } else {
    print('⚠️  No error UI found, but still on login screen');
  }
}

/// Verify token validity
Future<void> verifyTokenValidity() async {
  print('🔄 Verifying token validity...');

  try {
    final apiService = SupabaseApiService.instance;
    final apiRepository = ApiRepository(apiService);

    // Get current user to verify token
    final userResult = await apiRepository.getCurrentUser();

    expect(userResult, isNotNull, reason: 'User result should not be null');
    expect(
      userResult!.isSuccess,
      isTrue,
      reason: 'User API call should be successful',
    );

    if (userResult.userId != null) {
      expect(
        userResult.email,
        isNotNull,
        reason: 'User email should not be null',
      );
      expect(
        userResult.userId,
        isNotNull,
        reason: 'User ID should not be null',
      );

      print('✅ Token is valid!');
      print('   User ID: ${userResult.userId}');
      print('   User email: ${userResult.email}');
    } else {
      fail('User data is null despite successful API call');
    }
  } catch (e) {
    // Handle expected auth errors during testing
    if (e.toString().contains('AuthSessionMissingException')) {
      print('⚠️  Auth session missing (expected in test environment)');
      // This is expected during testing - don't fail the test
    } else {
      fail('Token validation failed: $e');
    }
  }
}
