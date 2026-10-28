# In-App DM Notification Banner

## Overview

When the user is on the Direct Messages screen and a new message arrives in a conversation they are **not** currently viewing, a card slides down from the top of the screen. Tapping it opens the conversation; the × button or a 4-second timeout dismisses it.

## How it works end-to-end

```
User sends DM
  └─► INSERT INTO direct_messages
        └─► Postgres trigger: notify_direct_message_created()     (migration 064)
              └─► net.http_post → send-dm-notification edge function
                    └─► FCM push → recipient device
                          └─► App foreground? → _showLocalNotification (dm_notifications channel)
                              App background/killed? → system tray notification
                                └─► User taps → _handleMessageOpenedApp → switchToDirectMessagesTab
```

On the **sender's own device**, the realtime `streamDirectMessageConversations` subscription fires (Supabase Realtime), which is already active on the DM screen. `_onConversationsUpdated()` detects the new `lastMessage.id` and shows the in-app banner — **no extra network call needed**.

## Trigger layer (migration 064)

`notify_direct_message_created()` is a Postgres trigger function that fires `AFTER INSERT ON direct_messages`. It:

1. Reads the Supabase service role key from Vault.
2. Calls `send-dm-notification` via `net.http_post` with:
   - `conversationId` — which conversation received the message
   - `senderId` — who sent it
   - `messageContent` — truncated to 200 chars for the notification preview
3. Returns `NEW` on success OR on any exception (notifications never block inserts).

The trigger intentionally contains **no recipient logic**. All routing decisions live in the edge function.

> **Migration 046** contained an older version of this trigger that called `send-fcm-notification` with `notificationType=direct_message` and looped over admins in SQL. Migration 064 replaces that with the simplified version above.

## Edge function (`send-dm-notification`)

Deployed as `supabase/functions/send-dm-notification/index.ts`. Accepts:

```json
{ "conversationId": "...", "senderId": "...", "messageContent": "..." }
```

Recipient logic:

| Sender | Recipients |
|---|---|
| `senderId == conversation.user_id` (regular user) | All users in `admin_organizations` for that org **where `user_profiles.role = 'admin'`** — superadmins are explicitly excluded |
| `senderId != conversation.user_id` (admin replying) | `conversation.user_id` only |

FCM data payload sent to all recipient tokens:

```json
{
  "notification_type": "direct_message",
  "conversation_id": "<uuid>",
  "click_action": "FLUTTER_NOTIFICATION_CLICK"
}
```

Android channel: `dm_notifications`. No notification-preference filtering (unlike channel posts).

## Flutter in-app banner (`direct_messages_screen.dart`)

### Detection

`_onConversationsUpdated(incoming)` is called on every Supabase Realtime emission from the conversations stream. It compares each conversation's `lastMessage.id` against `_lastKnownMessageIds` (seeded from the initial fetch so pre-existing messages never trigger banners). A banner is shown when:

- `lastMessage.id` is new (not previously seen)
- `lastMessage.createdBy != _currentUserId` (not own message)
- The conversation is **not** currently open (`_openConversationId` on narrow screen, `_selectedConversation` on wide screen)

Only one banner is shown at a time. A new incoming message replaces the current banner.

### Dismissal

| Trigger | Behaviour |
|---|---|
| User taps the banner | Navigates to the conversation, banner dismissed |
| User taps × | Banner dismissed |
| 4-second auto-dismiss | `Timer` fires `_dismissBanner()` |
| User taps any conversation in the list | `_dismissBanner()` called before opening |
| User navigates to a chat (narrow screen) | `_dismissBanner()` called, `_openConversationId` set |

### Animation

`AnimatedSwitcher` with a `SlideTransition` (slides in from `Offset(0, -1)`) and `FadeTransition`. The exit animation (slide back up + fade) is handled automatically by `AnimatedSwitcher` when the child changes to `SizedBox.shrink`.

## Deployment checklist

1. Deploy the edge function:
   ```bash
   supabase functions deploy send-dm-notification
   ```
2. Run migration 064 on the target environment (update `supabase_url` inside the SQL for QA vs production before running).
3. No new Vault secrets needed — the function reuses the existing Firebase credentials.
