# Direct Message Push Notifications

## Overview

DM push notifications are handled by a dedicated Supabase edge function (`send-dm-notification`) that is separate from the channel post notification function (`send-fcm-notification`). The separation keeps the targeting logic distinct and prevents any bleed-over between the two notification types.

## Architecture

### Edge Functions

| Function | Trigger | Recipients |
|---|---|---|
| `send-fcm-notification` | New channel post | All followers of the channel who have notifications enabled |
| `send-dm-notification` | New direct message | Either the regular user OR the org's admins (never superadmins) |

### Recipient Logic — `send-dm-notification`

The function determines recipients based on who sent the message relative to the conversation:

```
conversation: { user_id, organization_id }

if senderId == user_id (regular user messaging the org):
    → notify all users in admin_organizations where organization_id matches
      AND user_profiles.role = 'admin'   ← explicitly excludes 'superadmin'

if senderId != user_id (admin replying to the user):
    → notify conversation.user_id only
```

No notification preferences filtering is applied to DMs (unlike channel posts). No superadmins are ever notified.

### Notification Payload (FCM data fields)

```json
{
  "notification_type": "direct_message",
  "conversation_id": "<uuid>",
  "click_action": "FLUTTER_NOTIFICATION_CLICK"
}
```

The `conversation_id` is used by the app to deep-link directly into the correct conversation when the notification is tapped.

## Trigger Layer

### DB trigger (`migrations/064_dm_notification_dedicated_function.sql`)

`notify_direct_message_created()` is a Postgres trigger function that fires `AFTER INSERT ON direct_messages`. It:

1. Reads the service role key from Supabase Vault.
2. Calls `send-dm-notification` via `net.http_post` with `conversationId`, `senderId`, and `messageContent`.
3. Returns `NEW` in all cases — errors are caught and emitted as `WARNING` so they never block the message insert.

The trigger contains **no recipient logic**. It intentionally keeps the SQL minimal and delegates all routing to the edge function.

> Migration 046 contained an older version that called `send-fcm-notification` with `notificationType=direct_message` and looped through admins in SQL without filtering superadmins. Migration 064 replaces that entirely.

The Flutter client (`supabase_api_service.dart`) does **not** call the edge function directly. The DB trigger is the single, authoritative notification source.

## Flutter Integration

### In-app banner (`direct_messages_screen.dart`)

See `docs/IN_APP_DM_NOTIFICATIONS.md` for the full breakdown of the banner that appears on the DM screen when a new message arrives in a conversation the user is not currently viewing.

### Deep-link routing (`fcm_service.dart`)

`_handleMessageOpenedApp` and `_onNotificationTapped` both check `notification_type`:

```dart
if (notificationType == 'direct_message' && conversationId != null) {
  _navigateToDirectMessages(conversationId);
} else if (channelId != null) {
  _navigateToChannel(channelId, postId);
}
```

`_navigateToDirectMessages` calls `mainScaffoldKey.currentState!.switchToDirectMessagesTab(conversationId: conversationId)`, which opens the DM tab and navigates directly into the conversation.

### Foreground notifications (`fcm_service.dart`)

When the app is in the foreground and a DM arrives, `_showLocalNotification` uses the `dm_notifications` Android channel (instead of `post_notifications`). This allows users to configure DM and post notifications independently in system settings.

```dart
final isDM = message.data['notification_type'] == 'direct_message';
// uses 'dm_notifications' channel if isDM, otherwise 'post_notifications'
```

Both Android channels (`dm_notifications`, `post_notifications`) are registered at FCM service initialization.

## Deployment

1. **Run migration 064** on the target environment. Update the `supabase_url` variable inside the SQL to match QA or production before running.

2. **Deploy the edge function**:
   ```bash
   supabase functions deploy send-dm-notification
   ```

The function uses the same environment variables as `send-fcm-notification`:
- `FIREBASE_PRIVATE_KEY`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PROJECT_ID`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

No new secrets are needed.
