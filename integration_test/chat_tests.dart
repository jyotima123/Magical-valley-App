// integration_test/chat_tests.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;
import 'package:mvc_app/modules/chat/real_chat_scree.dart';
import 'package:mvc_app/modules/chat/widgets/message_item.dart';
import 'test_helpers.dart';
import 'navigation_helpers.dart';
import 'auth_helpers.dart';

void main() {
  group('Chat Tests', () {
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

    testWidgets(
      'Verify non-admin users cannot see author names in chat messages',
      (tester) async {
        print('🚀 Starting author name visibility test for non-admin users...');

        // Launch the app (using QA environment due to FlavorConfig.appFlavor = Flavor.development)
        await app.main();
        await waitForAppToBeReady(tester);

        await handleOnboarding(tester);
        await ensureOnWelcomeScreen(tester);

        if (find.byType(RealChatScreen).evaluate().isNotEmpty) {
          await logoutUser(tester);
          await ensureOnWelcomeScreen(tester);
        }

        // Step 1: Login as a regular user (non-admin)
        await navigateToLogin(tester);
        await performLogin(tester, testEmail, testPassword);

        // Step 2: Verify we're on the home screen
        await verifyHomeScreen(tester);

        // Step 3: Verify that author names are not visible in chat messages
        await verifyAuthorNamesNotVisible(tester);

        // Cleanup
        await tester.pumpAndSettle();
        await Future.delayed(const Duration(milliseconds: 500));
      },
    );
  });
}

/// Verify that author names are not visible for non-admin users
Future<void> verifyAuthorNamesNotVisible(WidgetTester tester) async {
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
