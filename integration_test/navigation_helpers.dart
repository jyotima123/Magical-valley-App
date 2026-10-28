// integration_test/navigation_helpers.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/auth/auth_bloc.dart';
import 'package:mvc_app/modules/auth/auth_event.dart';
import 'package:mvc_app/modules/auth/onboarding_screen.dart';
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Wait for app to be ready
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

    print('⏳ Still loading... attempt ${waitAttempts + 1}/$maxWaitAttempts');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    waitAttempts++;
  }

  // Final settle
  await tester.pumpAndSettle();
  print('✅ App should be ready now');
}

/// Handle onboarding flow
Future<void> handleOnboarding(WidgetTester tester) async {
  print('🔄 Handling onboarding...');

  // Wait for app to load with longer timeout
  await tester.pumpAndSettle(const Duration(seconds: 3));

  // Check what type of screen we're on
  print('🔍 Checking screen type...');

  // Check for OnboardingScreen
  final onboardingScreen = find.byType(OnboardingScreen);
  if (onboardingScreen.evaluate().isNotEmpty) {
    print('📱 OnboardingScreen found, navigating through it...');
    await navigateThroughOnboarding(tester);
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
    return handleOnboarding(tester);
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

/// Navigate through onboarding screens
Future<void> navigateThroughOnboarding(WidgetTester tester) async {
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

/// Ensure we're on the welcome screen
Future<void> ensureOnWelcomeScreen(WidgetTester tester) async {
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
    await logoutUser(tester);
    await tester.pumpAndSettle();
    return;
  }

  // If we're on onboarding, navigate through it
  final onboardingScreen = find.byType(OnboardingScreen);
  if (onboardingScreen.evaluate().isNotEmpty) {
    print('🔄 Still on onboarding, navigating through it...');
    await navigateThroughOnboarding(tester);
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

/// Log out the user
Future<void> logoutUser(WidgetTester tester) async {
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
        await handleLogoutConfirmationDialog(tester);
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
        await handleLogoutConfirmationDialog(tester);
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

/// Handle logout confirmation dialog
Future<void> handleLogoutConfirmationDialog(WidgetTester tester) async {
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

/// Verify welcome screen
Future<void> verifyWelcomeScreen(WidgetTester tester) async {
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

/// Verify home screen
Future<void> verifyHomeScreen(WidgetTester tester) async {
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
