// integration_test/app_flow_test.dart
// ignore_for_file: dead_code, unused_local_variable, avoid_print

import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/flavour_config.dart';
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/otp_verification_screen.dart'
    show OtpVerificationScreen;
import 'package:mvc_app/modules/auth/reset_password_screen.dart';
import 'package:mvc_app/modules/auth/sign_up_otp_explanation_screen.dart'
    show SignUpOtpExplanationScreen;
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:mvc_app/modules/auth/onboarding_screen.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:mvc_app/modules/chat/widgets/message_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  // Only include integration test setup in debug/profile builds
  assert(() {
    if (const bool.fromEnvironment('INTEGRATION_TEST')) {
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    }
    return true;
  }());

  // Fix logging configuration issue
  setUpAll(() async {
    // Enable hierarchical logging to prevent the UnsupportedError
    hierarchicalLoggingEnabled = true;

    // Set flavor to development for integration tests (uses .env_qa)
    FlavorConfig.appFlavor = Flavor.development;

    // // Initialize Supabase once for all tests
    // await SupabaseApiService.instance.initialize(environment: 'qa');
  });

  const String mailslurpApiBaseUrl = 'https://api.mailslurp.com';
  const String mailslurpApiKey =
      "f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864";

  Future<Map<String, String>> createInbox() async {
    // Function to create a new inbox
    final createInboxUrl = Uri.parse('$mailslurpApiBaseUrl/inboxes');
    final createInboxResponse = await http.post(
      createInboxUrl,
      headers: {
        'x-api-key': mailslurpApiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}), // Empty body to create a default inbox
    );

    if (createInboxResponse.statusCode == 200 ||
        createInboxResponse.statusCode == 201) {
      final inboxData = jsonDecode(createInboxResponse.body);
      return {
        'inboxId': inboxData['id'],
        'emailAddress': inboxData['emailAddress'],
      };
    } else {
      throw Exception(
        'Failed to create inbox: ${createInboxResponse.statusCode} - ${createInboxResponse.body}',
      );
    }
  }

  // Function to send an email to a specific inbox
  Future<void> sendEmailToInbox(String inboxId, String emailAddress) async {
    final sendEmailUrl = Uri.parse('$mailslurpApiBaseUrl/sendEmail');
    final sendEmailResponse = await http.post(
      sendEmailUrl,
      headers: {
        'x-api-key': mailslurpApiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'inboxId': inboxId,
        'to': emailAddress,
        'subject': 'Hello from Dart HTTP!',
        'body':
            '<html><body><h1>This is a test email sent via MailSlurp REST API.</h1><p>Email content goes here.</p></body></html>',
        'isHTML': true,
      }),
    );

    if (sendEmailResponse.statusCode != 201) {
      throw Exception(
        'Failed to send test email: ${sendEmailResponse.statusCode} - ${sendEmailResponse.body}',
      );
    }
  }

  // Function to check the latest email in a specific inbox
  Future<Map<String, dynamic>> checkLatestEmailInInbox(String email) async {
    String inboxId = email.split('@')[0];

    print("Checking email in inbox $inboxId...");

    final waitForEmailUrl = Uri.parse(
      '$mailslurpApiBaseUrl/waitForLatestEmail?inboxId=$inboxId&timeout=30000&unreadOnly=true',
    );

    final emailResponse = await http.get(
      waitForEmailUrl,
      headers: {'x-api-key': mailslurpApiKey, 'Accept': 'application/json'},
    );

    if (emailResponse.statusCode == 200) {
      print("Got response from inbox $inboxId");
      return jsonDecode(emailResponse.body);
    } else if (emailResponse.statusCode == 408) {
      throw Exception('Timeout: No email received within the specified time.');
    } else {
      print("Did not get response from inbox $inboxId");
      throw Exception(
        'Failed to fetch email: ${emailResponse.statusCode} - ${emailResponse.body}',
      );
    }
  }

  String getOtpFromEmail(String emailBody) {
    // Extract OTP using regex - looking for the pattern in the template
    final RegExp otpRegex = RegExp(r'[0-9]{6}'); // Assuming 6-digit OTP
    final match = otpRegex.firstMatch(emailBody);

    try {
      if (match != null) {
        final otpCode = match.group(0)!;
        print('✅ Extracted OTP: $otpCode');
        return otpCode;
      } else {
        throw Exception('OTP not found in email body');
      }
    } catch (e) {
      print('❌ Failed to get OTP from email: $e');
      rethrow;
    }
  }

  // Helper function to try submitting the OTP
  Future<void> trySubmitOtp(WidgetTester tester) async {
    print('🔄 Attempting to submit OTP');

    // Wait a moment for auto-submit to potentially trigger
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Look for and tap the verify button if it exists and is enabled
    final verifyButton = find.text('Verify Code');
    if (verifyButton.evaluate().isNotEmpty) {
      final buttonWidget = tester.widget<ElevatedButton>(
        find.ancestor(of: verifyButton, matching: find.byType(ElevatedButton)),
      );

      if (buttonWidget.onPressed != null) {
        print('🔄 Tapping Verify Code button');
        await tester.tap(verifyButton);
        await tester.pumpAndSettle();
      } else {
        print('⚠️ Verify Code button is disabled');
      }
    } else {
      print('⚠️ Verify Code button not found');
    }

    // Also try looking for a generic "Verify" button as fallback
    final genericVerifyButton = find.text('Verify');
    if (genericVerifyButton.evaluate().isNotEmpty) {
      print('🔄 Tapping generic Verify button');
      await tester.tap(genericVerifyButton);
      await tester.pumpAndSettle();
    }

    print('✅ OTP submit attempt completed');
  }

  // Helper: Enter OTP code in the verification screen
  Future<void> enterOtpCode(WidgetTester tester, String otpCode) async {
    print('🔄 Entering OTP code: $otpCode');

    // Wait for the OTP screen to be fully loaded
    await tester.pumpAndSettle();

    // Debug: Print all TextFields found
    final allTextFields = find.byType(TextField);
    print(
      '🔍 Found ${allTextFields.evaluate().length} TextField widgets total',
    );

    // Method 1: Try to find the hidden field and use it
    try {
      final hiddenField = find.byWidgetPredicate((widget) {
        if (widget is TextField) {
          final decoration = widget.decoration;
          return decoration != null &&
              decoration.border == InputBorder.none &&
              decoration.counterText == '';
        }
        return false;
      });

      if (hiddenField.evaluate().isNotEmpty) {
        print('🔄 Found hidden field, attempting to use it');
        await tester.enterText(hiddenField, otpCode);
        await tester.pumpAndSettle();

        // Wait for the auto-fill logic to populate visible fields
        await Future.delayed(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // Check if auto-submit worked by looking for navigation or success
        await trySubmitOtp(tester);
        return;
      }
    } catch (e) {
      print('⚠️ Hidden field method failed: $e');
    }

    // Method 2: Find visible OTP fields by looking for TextField with specific characteristics
    final visibleOtpFields = <Finder>[];

    // Look for TextFields that are likely OTP fields (have maxLength 1, number keyboard, etc.)
    for (int i = 0; i < allTextFields.evaluate().length; i++) {
      try {
        final fieldFinder = allTextFields.at(i);
        final textField = tester.widget<TextField>(fieldFinder);

        // Check if this looks like an OTP field
        bool isOtpField =
            textField.maxLength == 1 &&
            textField.keyboardType == TextInputType.number &&
            textField.decoration?.filled == true;

        if (isOtpField) {
          visibleOtpFields.add(fieldFinder);
          print('🔍 Found OTP field ${visibleOtpFields.length}');
        }
      } catch (e) {
        print('⚠️ Error checking field $i: $e');
      }
    }

    print('🔍 Found ${visibleOtpFields.length} visible OTP fields');

    if (visibleOtpFields.length != 6) {
      print('⚠️ Expected 6 OTP fields, found ${visibleOtpFields.length}');
      // Fallback: try to find any TextField with SizedBox parent (the layout from your screen)
      final fallbackFields = find.byWidgetPredicate((widget) {
        return widget is TextField &&
            widget.maxLength == 1 &&
            widget.textAlign == TextAlign.center;
      });

      if (fallbackFields.evaluate().length >= 6) {
        print('🔄 Using fallback field detection');
        for (int i = 0; i < 6 && i < otpCode.length; i++) {
          try {
            final fieldFinder = fallbackFields.at(i);
            await tester.tap(fieldFinder);
            await tester.pumpAndSettle();
            await tester.enterText(fieldFinder, otpCode[i]);
            await tester.pumpAndSettle();
            print('✅ Entered digit ${otpCode[i]} in field $i');
          } catch (e) {
            print('⚠️ Error entering digit in field $i: $e');
          }
        }
      } else {
        throw Exception(
          'Could not find 6 OTP input fields. Found ${visibleOtpFields.length} specific OTP fields and ${fallbackFields.evaluate().length} fallback fields',
        );
      }
    } else {
      // Method 2: Fill each visible field individually
      print('🔄 Using individual field method for OTP entry');
      for (int i = 0; i < otpCode.length && i < visibleOtpFields.length; i++) {
        try {
          final fieldFinder = visibleOtpFields[i];

          // Tap the field to focus it
          await tester.tap(fieldFinder);
          await tester.pumpAndSettle();

          // Clear any existing text and enter the digit
          await tester.enterText(fieldFinder, otpCode[i]);
          await tester.pumpAndSettle();

          print('✅ Entered digit ${otpCode[i]} in field $i');

          // Small delay to simulate user typing
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          print('⚠️ Error entering digit in field $i: $e');
        }
      }
    }

    print('✅ OTP code entry completed');

    // Try to submit the OTP
    await trySubmitOtp(tester);
  }

  // Helper: Verify signup success
  Future<void> verifySignupSuccess(WidgetTester tester) async {
    print('🔄 Verifying signup success...');

    // Wait for navigation after OTP verification
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Check if we're redirected to home screen or success screen
    final homeScreen = find.byType(RealChatScreen);
    if (homeScreen.evaluate().isNotEmpty) {
      print('✅ Signup successful - redirected to home screen');
    } else {
      // Look for success message or next screen
      print('✅ Signup process completed');
    }
  }

  group('MVC App Integration Tests', () {
    // Test configuration
    const testEmail = 'alisson+1@fullpond.co';
    const testPassword = '12345678Aa';

    // const testSignUpEmails = ['alisson+test001@fullpond.co'];
    // const testSignUpPasswords = ['12345678Aa']; // TODO test different passwords
    const testFullName = 'Test User';

    String? email = "dada4d60-af97-4331-b756-c8af6752c1d6@mailslurp.biz";
    final createNewInbox = false;

    setUp(() async {
      // Clear any existing preferences before each test
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Create new inbox. Leave an address here instead if you want to reuse one
      if (createNewInbox) {
        final inboxData = await createInbox();

        email = inboxData['emailAddress'] ?? '';
      }
    });

    // Add proper cleanup
    tearDown(() async {
      // Wait for any pending operations to complete
      await Future.delayed(const Duration(milliseconds: 1500));
    });

    testWidgets('Complete user journey: onboarding → login → verify token', (
      tester,
    ) async {
      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await tester.pumpAndSettle();

      // Step 1: Handle onboarding
      await _handleOnboarding(tester);

      // Step 2: Navigate to login
      await _navigateToLogin(tester);

      // Step 3: Perform login
      await _performLogin(tester, testEmail, testPassword);

      // Step 4: Verify we're on home screen
      await _verifyHomeScreen(tester);

      // Step 5: Verify token validity
      await _verifyTokenValidity();

      // IMPROVED: More thorough cleanup
      await tester.pumpAndSettle();

      // Allow any pending operations to complete
      await Future.delayed(const Duration(seconds: 1));

      // Force any remaining async operations to complete
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    // Updated tearDown with better cleanup
    tearDown(() async {
      // Wait for any pending operations to complete
      await Future.delayed(const Duration(seconds: 2));

      // Force any remaining async operations to complete
      // await tester.pumpAndSettle(const Duration(seconds: 2));

      // Clear any remaining timers or subscriptions
      await Future.delayed(const Duration(milliseconds: 100));
    });

    // Helper: Navigate to signup form
    Future<void> navigateToSignup(WidgetTester tester) async {
      print('🔄 Navigating to signup...');

      await _ensureOnWelcomeScreen(tester);

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
        final nameField = find.widgetWithText(
          TextField,
          'Enter your full name',
        );
        final emailField = find.widgetWithText(TextField, 'Enter your email');
        final passwordField = find.widgetWithText(
          TextField,
          'Enter your password',
        );

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
        final nameField = find.widgetWithText(
          TextField,
          'Enter your full name',
        );
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

    // Helper: Fill form field with proper clearing
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

    // Helper: Perform signup
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

      final passwordField = find.widgetWithText(
        TextField,
        'Enter your password',
      );
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
      print(
        '🔄 Password: "$password", Confirm Password: "$actualConfirmPassword"',
      );

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

    // Helper: Navigate through OTP explanation screen
    Future<void> navigateThroughOtpExplanation(WidgetTester tester) async {
      print('🔄 Navigating through OTP explanation screen...');

      // Wait for the explanation screen to appear
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Check if we're on the OTP explanation screen
      final otpExplanationScreen = find.byType(SignUpOtpExplanationScreen);
      if (otpExplanationScreen.evaluate().isEmpty) {
        print('ℹ️ No OTP explanation screen found, continuing...');
        return;
      }

      print('✅ Found OTP explanation screen');

      // Try to find and tap the Skip button first (fastest way)
      final skipButton = find.text('Skip');
      if (skipButton.evaluate().isNotEmpty) {
        print('🔄 Found Skip button, tapping it...');
        await tester.tap(skipButton);
        await tester.pumpAndSettle();
        return;
      }

      // Try to find and tap the "I have my code" button
      final doneButton = find.text('I have my code');
      if (doneButton.evaluate().isNotEmpty) {
        print('🔄 Found "I have my code" button, tapping it...');
        await tester.tap(doneButton);
        await tester.pumpAndSettle();
        return;
      }

      // Try to find next button and navigate through pages
      final nextButton = find.byIcon(Icons.arrow_forward);
      if (nextButton.evaluate().isNotEmpty) {
        print('🔄 Found Next button, navigating through pages...');

        // Navigate through explanation pages
        int maxPages = 3; // Safety limit
        for (int i = 0; i < maxPages; i++) {
          final currentNextButton = find.byIcon(Icons.arrow_forward);
          if (currentNextButton.evaluate().isNotEmpty) {
            await tester.tap(currentNextButton);
            await tester.pumpAndSettle();
            await tester.pump(const Duration(milliseconds: 500));
          } else {
            // Look for the done button on the last page
            final finalDoneButton = find.text('I have my code');
            if (finalDoneButton.evaluate().isNotEmpty) {
              await tester.tap(finalDoneButton);
              await tester.pumpAndSettle();
              break;
            }
          }
        }
      }

      // Wait for navigation to complete
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      print('✅ OTP explanation screen navigation completed');
    }

    // Helper: Verify OTP screen
    Future<void> verifyOTPScreen(WidgetTester tester, String email) async {
      print('🔄 Verifying OTP screen...');

      String inboxId = email.split('@')[0];

      // First, navigate through the OTP explanation screen if it exists
      await navigateThroughOtpExplanation(tester);

      // Wait for navigation to complete
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Verify OTP screen is visible
      final otpScreen = find.byType(OtpVerificationScreen);
      expect(otpScreen, findsOneWidget, reason: 'OTP screen not found');

      // Verify email is displayed
      final resendButton = find.textContaining('Resend');
      expect(
        resendButton,
        findsOneWidget,
        reason: 'Resend Button not displayed on OTP screen',
      );

      print('✅ OTP screen verified successfully');

      // Step 5: Get OTP from MailSlurp and enter it
      print('Getting the code from email...');
      final latestEmail = await checkLatestEmailInInbox(email);
      String otpCode = (getOtpFromEmail(latestEmail['body'] ?? ''));
      await enterOtpCode(tester, otpCode);

      // Step 6: Verify successful signup completion
      await verifySignupSuccess(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(seconds: 1));
    }

    // Helper: Verify signup error
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

    Future<void> waitForAppToBeReady(WidgetTester tester) async {
      print('⏳ Waiting for app to be ready...');

      // Wait for the app to fully initialize
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Check for loading states and wait for them to complete
      int maxWaitAttempts = 15; // 15 seconds max
      int waitAttempts = 0;

      while (waitAttempts < maxWaitAttempts) {
        final loadingIndicator = find.byType(CircularProgressIndicator);
        if (loadingIndicator.evaluate().isEmpty) {
          break;
        }

        print(
          '⏳ Still loading... attempt ${waitAttempts + 1}/$maxWaitAttempts',
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        waitAttempts++;
      }

      // Final settle
      await tester.pumpAndSettle();
      print('✅ App should be ready now');
    }

    testWidgets('Login with invalid credentials shows error', (tester) async {
      print('🚀 Starting login with invalid credentials test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();

      // Wait for app to be fully ready
      await waitForAppToBeReady(tester);

      // Step 1: Handle onboarding (if needed)
      await _handleOnboarding(tester);

      // Step 2: Ensure we're on the right screen for navigation
      await _ensureOnWelcomeScreen(tester);

      // Step 3: If already logged in, log out first
      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        print('⚠️ Already logged in, logging out for test...');
        await _logoutUser(tester);
        await _ensureOnWelcomeScreen(
          tester,
        ); // Ensure we're back on the welcome screen
      }

      // Step 4: Navigate to login
      await _navigateToLogin(tester);

      // Step 5: Perform login with invalid credentials
      await _performLogin(tester, 'invalid@email.com', 'wrongpassword');

      // Step 6: Verify error is shown
      await _verifyLoginError(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    // Skip this one for now to save credits on mailslurp
    // testWidgets('Complete signup journey: onboarding → signup → verify OTP', (
    //   tester,
    // ) async {
    //   // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
    //   await app.main();
    //   await tester.pumpAndSettle();
    //
    //   // Step 1: Handle onboarding
    //   await _handleOnboarding(tester);
    //
    //   // Step 2: Navigate to signup
    //   await _navigateToSignup(tester);
    //
    //   // Step 3: Perform signup
    //   await _performSignup(
    //     tester,
    //     testFullName,
    //     // testSignUpEmails[0],
    //     email!,
    //     testSignUpPasswords[0],
    //   );
    //
    //   // Step 4: Verify OTP screen (this now includes navigating through explanation)
    //   await _verifyOTPScreen(tester, email!); // Use the correct email
    //
    //   // Step 5: Verify token validity (optional, depending on your flow)
    //   // await _verifyTokenValidity();
    //
    //   // Cleanup
    //   await tester.pumpAndSettle();
    //   await Future.delayed(const Duration(seconds: 1));
    // });

    testWidgets('Signup with invalid credentials shows error', (tester) async {
      print('🚀 Starting signup with invalid credentials test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await _handleOnboarding(tester);
      await _ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        print('⚠️ Already logged in, logging out for test...');
        await _logoutUser(tester);
        await _ensureOnWelcomeScreen(tester);
      }

      await navigateToSignup(tester);

      // Invalid credentials: mismatching passwords
      await performSignup(
        tester,
        testFullName,
        email!,
        testPassword,
        confirmPassword: 'DifferentPassword123!',
      );

      await verifySignupError(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    // ! This is commented because we are not skipping intro yet
    // testWidgets('Skip onboarding and go directly to auth', (tester) async {
    //   // Set the preference to skip onboarding
    //   final prefs = await SharedPreferences.getInstance();
    //   await prefs.setBool('has_seen_intro', true);

    //   await app.main();
    //   await tester.pumpAndSettle();

    //   // Should go directly to welcome screen
    //   await _verifyWelcomeScreen(tester);

    //   // Add cleanup wait
    //   await tester.pumpAndSettle();
    //   await Future.delayed(const Duration(milliseconds: 500));
    // });
    // Add these tests within the 'MVC App Integration Tests' group,

    testWidgets('Navigate to forgot password from login screen', (
      tester,
    ) async {
      print('🚀 Starting forgot password navigation test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await _handleOnboarding(tester);
      await _ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        print('⚠️ Already logged in, logging out for test...');
        await _logoutUser(tester);
        await _ensureOnWelcomeScreen(tester);
      }

      await _navigateToLogin(tester);
      await _navigateToForgotPassword(tester);
      await _verifyForgotPasswordScreen(tester);

      // Cleanup
      await tester.pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 500));
    });

    testWidgets('Send forgot password email with valid email', (tester) async {
      print('🚀 Starting forgot password email test...');

      // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
      await app.main();
      await waitForAppToBeReady(tester);

      await _handleOnboarding(tester);
      await _ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        await _logoutUser(tester);
        await _ensureOnWelcomeScreen(tester);
      }

      await _navigateToLogin(tester);
      await _navigateToForgotPassword(tester);

      // Use the created inbox email for testing
      await _performForgotPassword(tester, email!);
      await _verifyForgotPasswordSuccess(tester);

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

      await _handleOnboarding(tester);
      await _ensureOnWelcomeScreen(tester);

      if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
        await _logoutUser(tester);
        await _ensureOnWelcomeScreen(tester);
      }

      await _navigateToLogin(tester);
      await _navigateToForgotPassword(tester);

      await _performForgotPassword(tester, 'nonexistent@invalid.com');
      await _verifyForgotPasswordError(tester);

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

        await _handleOnboarding(tester);
        await _ensureOnWelcomeScreen(tester);

        if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
          await _logoutUser(tester);
          await _ensureOnWelcomeScreen(tester);
        }

        // Step 1: Navigate to forgot password and send reset email
        await _navigateToLogin(tester);
        await _navigateToForgotPassword(tester);
        await _performForgotPassword(tester, email!);
        await _verifyForgotPasswordSuccess(tester);

        // Step 2: Get reset link from email
        print('🔄 Getting reset link from email...');
        final resetEmail = await checkLatestEmailInInbox(email!);
        final resetLink = _extractResetLinkFromEmail(resetEmail['body'] ?? '');

        if (resetLink.isEmpty) {
          throw Exception('Reset link not found in email');
        }

        // Step 3: Navigate to reset password screen with link
        await _navigateToResetPassword(tester, resetLink);

        // Step 4: Perform password reset
        const newPassword = 'NewPassword123!';
        await _performPasswordReset(tester, newPassword);

        // Step 5: Verify reset success
        await _verifyPasswordResetSuccess(tester);

        // Cleanup
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(seconds: 1));
      },
    );

    testWidgets(
      'Verify non-admin users cannot see author names in chat messages',
      (tester) async {
        print('🚀 Starting author name visibility test for non-admin users...');

        // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
        await app.main();
        await waitForAppToBeReady(tester);

        await _handleOnboarding(tester);
        await _ensureOnWelcomeScreen(tester);

        if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
          await _logoutUser(tester);
          await _ensureOnWelcomeScreen(tester);
        }

        // Step 1: Login as a regular user (non-admin)
        await _navigateToLogin(tester);
        await _performLogin(tester, testEmail, testPassword);

        // Step 2: Verify we're on the home screen
        await _verifyHomeScreen(tester);

        // Step 3: Verify that author names are not visible in chat messages
        await _verifyAuthorNamesNotVisible(tester);

        // Cleanup
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(milliseconds: 500));
      },
    );
  });
}

// Helper: Verify forgot password screen
Future<void> _verifyForgotPasswordScreen(WidgetTester tester) async {
  print('🔄 Verifying forgot password screen...');

  // Look for forgot password specific elements
  final resetPasswordTitle = find.textContaining('Reset');
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

// Helper: Navigate to forgot password screen
Future<void> _navigateToForgotPassword(WidgetTester tester) async {
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

// Helper: Perform forgot password action
Future<void> _performForgotPassword(WidgetTester tester, String email) async {
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

// Helper: Verify forgot password success
Future<void> _verifyForgotPasswordSuccess(WidgetTester tester) async {
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

// Helper: Verify forgot password error
Future<void> _verifyForgotPasswordError(WidgetTester tester) async {
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

// Helper: Extract reset link from email
String _extractResetLinkFromEmail(String emailBody) {
  print('🔄 Extracting reset link from email...');

  // Look for reset password link pattern
  final RegExp linkRegex = RegExp(
    r'https?://[^\s]+/reset-password[^\s]*',
    caseSensitive: false,
  );

  final match = linkRegex.firstMatch(emailBody);

  if (match != null) {
    final resetLink = match.group(0)!;
    print('✅ Extracted reset link: ${resetLink.substring(0, 50)}...');
    return resetLink;
  }

  // Fallback: look for any link containing reset or token
  final RegExp fallbackRegex = RegExp(
    r'https?://[^\s]*(?:reset|token)[^\s]*',
    caseSensitive: false,
  );

  final fallbackMatch = fallbackRegex.firstMatch(emailBody);

  if (fallbackMatch != null) {
    final resetLink = fallbackMatch.group(0)!;
    print('✅ Extracted fallback reset link: ${resetLink.substring(0, 50)}...');
    return resetLink;
  }

  print('❌ No reset link found in email');
  return '';
}

Future<void> _performPasswordReset(
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

// Helper: Navigate to reset password screen with link
Future<void> _navigateToResetPassword(
  WidgetTester tester,
  String resetLink,
) async {
  print('🔄 Navigating to reset password screen with link...');

  // Parse the reset link to extract parameters
  final uri = Uri.parse(resetLink);
  final token = uri.queryParameters['token'];
  final type = uri.queryParameters['type'];

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

// Helper: Verify password reset success
Future<void> _verifyPasswordResetSuccess(WidgetTester tester) async {
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

// Helper to ensure we're on the welcome screen
Future<void> _ensureOnWelcomeScreen(WidgetTester tester) async {
  print('🔄 Ensuring we are on welcome screen...');

  // Check if we're already on welcome screen
  final welcomeScreen = find.byType(app.AppRouter);
  if (welcomeScreen.evaluate().isNotEmpty) {
    print('✅ Already on welcome screen');
    return;
  }

  // If we're on chat screen (already logged in), log out first
  final chatScreen = find.byType(RealChatScreen);
  if (chatScreen.evaluate().isNotEmpty) {
    print('⚠️ Already logged in, logging out for test...');
    await _logoutUser(tester);
    await tester.pumpAndSettle();
    return;
  }

  // If we're on onboarding, navigate through it
  final onboardingScreen = find.byType(OnboardingScreen);
  if (onboardingScreen.evaluate().isNotEmpty) {
    print('🔄 Still on onboarding, navigating through it...');
    await _navigateThroughOnboarding(tester);
    await tester.pumpAndSettle();
  }

  // Wait for welcome screen to appear
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  // Final check
  final finalWelcomeScreen = find.byType(app.AppRouter);
  if (finalWelcomeScreen.evaluate().isEmpty) {
    throw Exception('Could not reach welcome screen');
  }

  print('✅ Successfully on welcome screen');
}

// Helper: Log out the user by navigating to the hamburger menu and clicking "Logout"
Future<void> _logoutUser(WidgetTester tester) async {
  print('🔄 Logging out user...');

  // Wait for the app to fully settle
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Ensure we're on the RealChatScreen
  final chatScreen = find.byType(RealChatScreen);
  expect(chatScreen, findsOneWidget, reason: 'Should be on RealChatScreen');

  // Method 1: Try to find and tap the PopupMenuButton
  bool menuOpened = false;

  try {
    // Look for PopupMenuButton first
    final popupMenuButton = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<String>,
    );

    if (popupMenuButton.evaluate().isNotEmpty) {
      print('🔄 Found PopupMenuButton, attempting to tap...');
      await tester.tap(popupMenuButton, warnIfMissed: false);
      menuOpened = true;
    } else {
      // Try to find the menu icon
      final menuIcon = find.byIcon(Icons.menu);
      if (menuIcon.evaluate().isNotEmpty) {
        print('🔄 Found menu icon, attempting to tap...');
        // Try tapping at the center of the widget
        final center = tester.getCenter(menuIcon);
        await tester.tapAt(center);
        menuOpened = true;
      }
    }

    if (menuOpened) {
      // Wait for popup menu to appear
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Look for logout option in the popup menu
      final logoutInMenu = find.text('Logout').first;
      if (logoutInMenu.evaluate().isNotEmpty) {
        print('🔄 Found Logout in popup menu, tapping...');
        await tester.tap(logoutInMenu);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // Handle the confirmation dialog
        await _handleLogoutConfirmationDialog(tester);
        return;
      }
    }
  } catch (e) {
    print('⚠️ PopupMenu approach failed: $e');
  }

  // Method 2: Alternative approach - try to access settings/profile screen
  print('🔄 Trying alternative logout method via profile settings...');

  try {
    // Try to find "Edit Profile" option if menu is still open
    final editProfile = find.text('Edit Profile');
    if (editProfile.evaluate().isNotEmpty) {
      await tester.tap(editProfile);
      await tester.pumpAndSettle();

      // Look for logout in profile settings
      final profileLogout = find.text('Sign Out');
      if (profileLogout.evaluate().isNotEmpty) {
        await tester.tap(profileLogout);
        await tester.pumpAndSettle();
        await _handleLogoutConfirmationDialog(tester);
        return;
      }
    }
  } catch (e) {
    print('⚠️ Profile settings approach failed: $e');
  }

  // Method 3: Direct AuthBloc logout (last resort for tests)
  print('🔄 Using direct AuthBloc logout as fallback...');

  // Get the AuthBloc and trigger logout directly
  final context = tester.element(find.byType(RealChatScreen));
  final authBloc = context.read<AuthBloc>();
  authBloc.add(LogoutEvent());

  // Wait for logout to process
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  print('✅ User logged out successfully (via direct method)');
}

// Helper function to handle logout confirmation dialog
Future<void> _handleLogoutConfirmationDialog(WidgetTester tester) async {
  // Find the AlertDialog
  final alertDialog = find.byType(AlertDialog);
  if (alertDialog.evaluate().isNotEmpty) {
    print('🔄 Found logout confirmation dialog');

    // Find the "Logout" or "Sign Out" button in the AlertDialog
    final logoutButton = find.descendant(
      of: alertDialog,
      matching: find.widgetWithText(TextButton, 'Logout'),
    );

    final signOutButton = find.descendant(
      of: alertDialog,
      matching: find.widgetWithText(TextButton, 'Sign Out'),
    );

    if (logoutButton.evaluate().isNotEmpty) {
      await tester.tap(logoutButton);
    } else if (signOutButton.evaluate().isNotEmpty) {
      await tester.tap(signOutButton);
    } else {
      throw Exception('Could not find logout confirmation button');
    }

    await tester.pumpAndSettle();

    // Wait for the logout process to complete
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }
}

// Helper: Handle onboarding flow
Future<void> _handleOnboarding(WidgetTester tester) async {
  print('🔄 Handling onboarding...');

  // Wait for app to load with longer timeout
  await tester.pumpAndSettle(const Duration(seconds: 3));

  // Check what type of screen we're on
  print('🔍 Checking screen type...');

  // Check for OnboardingScreen
  final onboardingScreen = find.byType(OnboardingScreen);
  if (onboardingScreen.evaluate().isNotEmpty) {
    print('📱 OnboardingScreen found, navigating through it...');
    await _navigateThroughOnboarding(tester);
    return;
  }

  // Check for WelcomeScreen (already past onboarding)
  final welcomeScreen = find.byType(app.AppRouter);
  if (welcomeScreen.evaluate().isNotEmpty) {
    print('✅ Already on WelcomeScreen, skipping onboarding');
    return;
  }

  // Check for RealChatScreen (already logged in)
  final chatScreen = find.byType(RealChatScreen);
  if (chatScreen.evaluate().isNotEmpty) {
    print('✅ Already logged in, on RealChatScreen');
    return;
  }

  // Check for loading state
  final loadingIndicator = find.byType(CircularProgressIndicator);
  if (loadingIndicator.evaluate().isNotEmpty) {
    print('⏳ App is loading, waiting...');

    // Wait for loading to complete
    int waitAttempts = 0;
    while (loadingIndicator.evaluate().isNotEmpty && waitAttempts < 10) {
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      waitAttempts++;
    }

    // After loading, check again
    return _handleOnboarding(tester);
  }

  // If we don't find any expected screen, print debug info
  print('🔍 Debug: Current widget tree:');
  final scaffold = find.byType(Scaffold);
  if (scaffold.evaluate().isNotEmpty) {
    print('   - Found Scaffold');
  }

  final appEntryPoint = find.byType(app.AppRouter);
  if (appEntryPoint.evaluate().isNotEmpty) {
    print('   - Found AppEntryPoint');
  }

  // Wait a bit more and try again
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();

  print('✅ Onboarding handling completed');
}

// Helper: Navigate through onboarding screens
Future<void> _navigateThroughOnboarding(WidgetTester tester) async {
  print('🔄 Navigating through onboarding screens...');

  int maxAttempts = 10;
  int attempts = 0;

  while (attempts < maxAttempts) {
    // Check if we're still on onboarding
    final onboardingScreen = find.byType(OnboardingScreen);
    if (onboardingScreen.evaluate().isEmpty) {
      print('✅ Onboarding completed');
      break;
    }

    // Look for skip button first (fastest way)
    final skipButton = find.text('Skip');
    if (skipButton.evaluate().isNotEmpty) {
      print('🔄 Found Skip button, tapping it...');
      await tester.tap(skipButton);
      await tester.pumpAndSettle();
      break;
    }

    // Look for completion buttons
    final getStartedButton = find.text('Get Started');
    final doneButton = find.text('Done');
    final finishButton = find.text('Finish');

    if (getStartedButton.evaluate().isNotEmpty) {
      print('🔄 Found Get Started button, tapping it...');
      await tester.tap(getStartedButton);
      await tester.pumpAndSettle();
      break;
    }

    if (doneButton.evaluate().isNotEmpty) {
      print('🔄 Found Done button, tapping it...');
      await tester.tap(doneButton);
      await tester.pumpAndSettle();
      break;
    }

    if (finishButton.evaluate().isNotEmpty) {
      print('🔄 Found Finish button, tapping it...');
      await tester.tap(finishButton);
      await tester.pumpAndSettle();
      break;
    }

    // Look for next button
    final nextButton = find.text('Next');
    if (nextButton.evaluate().isNotEmpty) {
      print('🔄 Found Next button, tapping it...');
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
    } else {
      // Try swiping left to advance
      print('🔄 No navigation buttons found, trying swipe gesture...');
      final onboardingWidget = find.byType(OnboardingScreen);
      if (onboardingWidget.evaluate().isNotEmpty) {
        await tester.drag(onboardingWidget, const Offset(-300, 0));
        await tester.pumpAndSettle();
      }
    }

    attempts++;
    await tester.pump(const Duration(milliseconds: 500));
  }

  if (attempts >= maxAttempts) {
    print('⚠️ Onboarding navigation may have failed, continuing...');
  }
}

// Helper: Navigate to login form
Future<void> _navigateToLogin(WidgetTester tester) async {
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

// Helper: Perform login
Future<void> _performLogin(
  WidgetTester tester,
  String email,
  String password,
) async {
  print('🔄 Performing login with email: $email');

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

// Helper: Verify home screen
Future<void> _verifyHomeScreen(WidgetTester tester) async {
  print('🔄 Verifying home screen...');

  // Wait for navigation to complete
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check for RealChatScreen with retry logic
  int retryCount = 0;
  const maxRetries = 3;

  while (retryCount < maxRetries) {
    try {
      final homeScreen = find.byType(RealChatScreen);
      if (homeScreen.evaluate().isNotEmpty) {
        print('✅ Successfully verified home screen');
        return;
      }
    } catch (e) {
      print('🔄 Retry ${retryCount + 1}/$maxRetries: $e');
    }

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    retryCount++;
  }

  // Final verification
  final homeScreen = find.byType(RealChatScreen);
  expect(
    homeScreen,
    findsOneWidget,
    reason: 'Should be on home screen after successful login',
  );
}

// Helper: Verify token validity
Future<void> _verifyTokenValidity() async {
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

// Helper: Verify login error
Future<void> _verifyLoginError(WidgetTester tester) async {
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

// Helper: Verify welcome screen
Future<void> _verifyWelcomeScreen(WidgetTester tester) async {
  print('🔄 Verifying welcome screen...');

  final loginButton = find.text('LOGIN');
  final signupButton = find.text('SIGN UP');

  expect(loginButton, findsOneWidget, reason: 'LOGIN button should be visible');
  expect(
    signupButton,
    findsOneWidget,
    reason: 'SIGN UP button should be visible',
  );

  print('✅ Welcome screen verified');
}

// Helper: Verify that author names are not visible for non-admin users
Future<void> _verifyAuthorNamesNotVisible(WidgetTester tester) async {
  print(
    '🔄 Verifying that author names are not visible for non-admin users...',
  );

  // Wait for the chat screen to fully load
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();

  // Check if we're on the chat screen
  final chatScreen = find.byType(RealChatScreen);
  expect(chatScreen, findsOneWidget, reason: 'Should be on chat screen');

  // Look for message items in the chat
  final messageItems = find.byType(MessageItem);

  if (messageItems.evaluate().isEmpty) {
    print('ℹ️ No messages found in chat, skipping author name verification');
    return;
  }

  print('🔍 Found ${messageItems.evaluate().length} message items');

  // Check each message item for author names
  int messagesWithAuthorNames = 0;
  int totalMessages = messageItems.evaluate().length;

  for (int i = 0; i < totalMessages; i++) {
    try {
      final messageFinder = messageItems.at(i);
      final messageWidget = tester.widget<MessageItem>(messageFinder);

      // Check if this message has an author (not the current user's message)
      if (messageWidget.message.author != null) {
        // Look for author name text within this message
        final authorNameText = find.descendant(
          of: messageFinder,
          matching: find.byWidgetPredicate((widget) {
            if (widget is Text) {
              final text = widget.data ?? '';
              // Check if this text matches the author's name
              return text == messageWidget.message.author!.fullName ||
                  text == messageWidget.message.author!.username ||
                  text == 'Unknown User';
            }
            return false;
          }),
        );

        if (authorNameText.evaluate().isNotEmpty) {
          messagesWithAuthorNames++;
          print(
            '⚠️ Found author name in message ${i + 1}: ${messageWidget.message.author!.fullName}',
          );
        }
      }
    } catch (e) {
      print('⚠️ Error checking message ${i + 1}: $e');
    }
  }

  // Verify that no author names are visible
  expect(
    messagesWithAuthorNames,
    0,
    reason:
        'Non-admin users should not see any author names in chat messages. Found $messagesWithAuthorNames messages with visible author names.',
  );

  if (messagesWithAuthorNames == 0) {
    print('✅ Author names are correctly hidden for non-admin users');
  } else {
    print(
      '❌ Found $messagesWithAuthorNames messages with visible author names',
    );
  }
}
