# App Banner

A global slide-down banner that overlays all tabs. Used for DM notifications and any snackbar-style alert (info, warning, error, success).

## How it works

The banner lives inside `MainScaffold`'s `Scaffold.body` Stack as the topmost child, so it renders above every tab's content regardless of which tab is active. It auto-dismisses after a configurable duration (default 4 s) or when the user taps ×.

## Showing a banner

Call `showBanner()` on `mainScaffoldKey.currentState` from anywhere in the app:

```dart
mainScaffoldKey.currentState?.showBanner(
  title: 'Your title',
  body: 'Optional subtitle line',   // omit or pass '' to show title only
  icon: Icons.info_outline,
  onTap: () { /* navigate or do something */ },
);
```

All parameters except `title` are optional and have sensible defaults.

## Full parameter reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `title` | `String` | required | Bold top line |
| `body` | `String` | `''` | Smaller second line — hidden when empty |
| `icon` | `IconData` | `Icons.info_outline` | Avatar icon |
| `backgroundColor` | `Color` | `Colors.white` | Card background |
| `titleColor` | `Color` | `AppTheme.black` | Title text colour |
| `bodyColor` | `Color` | `AppTheme.secondaryHeadingColor` | Body text and × icon colour |
| `iconColor` | `Color` | `AppTheme.accentPrimary` | Avatar circle colour |
| `onTap` | `VoidCallback?` | `null` | Called when the card is tapped |
| `duration` | `Duration` | `4 seconds` | Auto-dismiss delay |

## Dismissing programmatically

```dart
mainScaffoldKey.currentState?.dismissBanner();
```

## Common variants

```dart
// Info (default style)
mainScaffoldKey.currentState?.showBanner(
  title: 'Heads up',
  body: 'Something changed in your feed.',
);

// Success
mainScaffoldKey.currentState?.showBanner(
  title: 'Saved',
  icon: Icons.check_circle_outline,
  iconColor: Colors.green,
  backgroundColor: const Color(0xFFF1F8E9),
  titleColor: Colors.green,
);

// Warning
mainScaffoldKey.currentState?.showBanner(
  title: 'Slow connection',
  body: 'Some content may not load.',
  icon: Icons.warning_amber_rounded,
  iconColor: Colors.amber,
  backgroundColor: const Color(0xFFFFFDE7),
  titleColor: const Color(0xFFF57F17),
);

// Error
mainScaffoldKey.currentState?.showBanner(
  title: 'Upload failed',
  body: 'Please try again.',
  icon: Icons.error_outline,
  iconColor: Colors.red,
  backgroundColor: const Color(0xFFFFEBEE),
  titleColor: Colors.red,
);

// With navigation on tap
mainScaffoldKey.currentState?.showBanner(
  title: 'New message',
  body: 'Tap to open the conversation.',
  icon: Icons.forum,
  onTap: () {
    mainScaffoldKey.currentState?.switchToDirectMessagesTab(
      conversationId: conversationId,
    );
  },
);
```

## DM notifications

DM banners are handled automatically — no manual call needed. When a new direct message arrives via Supabase Realtime:

- **User is on the DM tab** → the in-screen banner inside `DirectMessagesScreen` appears.
- **User is on any other tab** → `_onConversationsUpdated` calls `mainScaffoldKey.currentState?.showDMBanner(...)`, which triggers the global banner with the sender name, message preview, and a tap action that switches to the DM tab and opens the conversation.
