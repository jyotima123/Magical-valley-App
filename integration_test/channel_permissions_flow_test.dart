// integration_test/channel_permissions_flow_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/main.dart' as app;

import 'test_helpers.dart';
import 'navigation_helpers.dart';
import 'auth_helpers.dart';

void main() {
  group('Channel Permissions Flow', () {
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

    testWidgets('Regular, Admin, Superadmin end-to-end flow', (tester) async {
      final regEmail = const String.fromEnvironment('REG_EMAIL');
      final regPassword = const String.fromEnvironment('REG_PASSWORD');
      final admEmail = const String.fromEnvironment('ADM_EMAIL');
      final admPassword = const String.fromEnvironment('ADM_PASSWORD');
      final supEmail = const String.fromEnvironment('SUP_EMAIL');
      final supPassword = const String.fromEnvironment('SUP_PASSWORD');

      // Launch app
      await app.main();
      await waitForAppToBeReady(tester);

      await handleOnboarding(tester);
      await ensureOnWelcomeScreen(tester);

      // 1) Login as regular user
      await navigateToLogin(tester);
      await performLogin(tester, regEmail, regPassword);
      await verifyHomeScreen(tester);

      // 1. Explore button visible (assumption: button text contains 'Explore channels')
      await tester.pumpAndSettle();
      final exploreBtn = find.widgetWithText(ElevatedButton, 'Explore channels');
      expect(exploreBtn, findsOneWidget, reason: 'Regular user not following any channel should see Explore channels button');

      // 2. Follow first channel (assumptions: a list of channels exists, with a Follow action)
      await tester.tap(exploreBtn);
      await tester.pumpAndSettle();

      // Tap first channel tile (by type or first ListTile)
      final firstTile = find.byType(ListTile).first;
      expect(firstTile, findsOneWidget);
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      // Tap Follow button (assumption: button text contains 'Follow')
      final followBtn = find.widgetWithText(ElevatedButton, 'Follow');
      if (followBtn.evaluate().isNotEmpty) {
        await tester.tap(followBtn);
        await tester.pumpAndSettle();
      }

      // 3. Go back to channels page and verify messages are visible
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Assumption: messages list present (look for any ListView in chat or specific message widget text)
      final messagesList = find.byType(ListView);
      expect(messagesList, findsWidgets, reason: 'Messages should be visible after following a channel');

      // 4. Verify non-admin cannot see author names and cannot see Admin section
      // Reuse author visibility logic from chat test assumptions
      // Expect no 'Manage' or 'Admin' section buttons/tabs
      final manageTab = find.textContaining('Manage');
      final adminText = find.textContaining('Admin');
      expect(manageTab, findsNothing);
      expect(adminText, findsNothing);

      // Attempt to locate author labels; we assert they are not present
      final authorLabel = find.textContaining('by ');
      expect(authorLabel, findsNothing, reason: 'Regular users should not see author names');

      // Logout
      await logoutUser(tester);
      await ensureOnWelcomeScreen(tester);

      // 5) Login as admin user
      await navigateToLogin(tester);
      await performLogin(tester, admEmail, admPassword);
      await verifyHomeScreen(tester);

      // Ensure admin can create post in managed channel but not in others (assumptions about UI)
      // We check presence of a 'New post' or '+' action only inside managed channel
      // Navigate to first channel (managed via test setup)
      await tester.pumpAndSettle();
      final channelsList = find.byType(ListTile);
      expect(channelsList, findsWidgets);
      await tester.tap(channelsList.first);
      await tester.pumpAndSettle();

      // Inside managed channel, expect create post action
      final createPostBtn = find.textContaining('New post').evaluate().isNotEmpty
          ? find.textContaining('New post')
          : find.byIcon(Icons.add);
      expect(createPostBtn, findsOneWidget, reason: 'Admin should see create post in managed channel');

      // Go back and pick a different channel (if available) and ensure create post is not visible
      await tester.pageBack();
      await tester.pumpAndSettle();
      if (channelsList.evaluate().length > 1) {
        await tester.tap(channelsList.at(1));
        await tester.pumpAndSettle();
        final createElse = find.textContaining('New post').evaluate().isNotEmpty
            ? find.textContaining('New post')
            : find.byIcon(Icons.add);
        expect(createElse, findsNothing, reason: 'Admin should not see create post in other channels');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // Logout admin
      await logoutUser(tester);
      await ensureOnWelcomeScreen(tester);

      // 6) Login as superadmin and verify Manage section visible
      await navigateToLogin(tester);
      await performLogin(tester, supEmail, supPassword);
      await verifyHomeScreen(tester);
      await tester.pumpAndSettle();

      final manageVisible = find.textContaining('Manage');
      expect(manageVisible, findsWidgets, reason: 'Superadmin should see Manage section');

      // Done
      await tester.pumpAndSettle();
    });
  });
}


