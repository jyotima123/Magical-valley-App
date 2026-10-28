# Notification Mute/Unmute Implementation Guide

This guide explains how to implement WhatsApp-style per-channel notification controls in your Flutter app with Supabase backend.

## Overview

The implementation filters notifications at the **server level** (Supabase Edge Function) based on user preferences stored in the database. This approach:

- ✅ Saves FCM quota by not sending to muted users
- ✅ Reduces network traffic
- ✅ Provides reliable cross-device sync
- ✅ Respects user privacy at the backend level

## Architecture

```
User Long-Press Channel
    ↓
Toggle Mute/Unmute (Local + Sync to Supabase)
    ↓
Preference Stored in notification_preferences table
    ↓
New Post Created → Trigger Fires
    ↓
Edge Function Queries Preferences
    ↓
Sends Notifications ONLY to Users with Enabled Notifications
```

## Setup Steps

### 1. Database Setup

Run the SQL script to create the notification preferences table:

```bash
# In Supabase SQL Editor, run:
supabase/notification_preferences_schema.sql
```

This creates:
- `notification_preferences` table to store user preferences
- RLS policies for security
- Helper function `get_notification_recipients()` for efficient queries
- Indexes for performance

### 2. Deploy Updated Edge Function

The Edge Function has been updated to filter recipients based on preferences:

```bash
# Deploy the updated function
supabase functions deploy send-fcm-notification
```

**Key changes:**
- Queries `notification_preferences` table
- Filters out users with `notifications_enabled = false`
- Defaults to enabled if no preference exists (backward compatible)
- Logs how many users were skipped

### 3. Flutter App Integration

The implementation is already complete in your app! Here's what was added:

#### A. Updated Service (`notification_preferences_service.dart`)

New Supabase sync methods:
- `_syncPreferenceToSupabase()` - Syncs individual preference changes
- `syncFromSupabase()` - Fetches all preferences from server (useful at login)
- `syncAllPreferencesToSupabase()` - Pushes all local preferences to server
- `deleteChannelPreferenceFromSupabase()` - Removes preference when unfollowing

#### B. Updated UI (`channels_list.dart`)

New features:
- Long-press gesture on channel to show mute/unmute menu
- Visual indicator (🔕 icon) for muted channels
- Snackbar feedback when toggling
- Automatic sync to Supabase on toggle

### 4. Testing the Implementation

#### Test locally:

1. **Mute a channel:**
   - Long-press on a channel in the list
   - Tap "Mute notifications"
   - Verify the 🔕 icon appears

2. **Verify database sync:**
   ```sql
   -- In Supabase SQL Editor
   SELECT * FROM notification_preferences 
   WHERE user_id = 'your-user-id';
   ```

3. **Test notification filtering:**
   - Create a new post in a muted channel
   - Verify you don't receive a notification
   - Unmute the channel
   - Create another post
   - Verify you DO receive a notification

4. **Check Edge Function logs:**
   ```bash
   supabase functions logs send-fcm-notification
   ```
   You should see logs like:
   ```
   Filtered results: 5 enabled, 2 muted
   Skipping user abc123 - notifications disabled for channel
   ```

### 5. Call Sync Methods in Your App

Add these calls to appropriate lifecycle methods:

#### On Login:
```dart
// In your login/auth flow
await NotificationPreferencesService.instance.syncFromSupabase();
```

#### On Logout:
```dart
// In your logout flow
await NotificationPreferencesService.instance.clearAllPreferences();
```

#### Periodic Sync (Optional):
```dart
// In your app initialization or periodic background task
await NotificationPreferencesService.instance.syncAllPreferencesToSupabase();
```

## Features

### ✅ Already Implemented

1. **Long-press to mute/unmute** - WhatsApp-style gesture
2. **Visual indicator** - Muted channels show 🔕 icon
3. **Local + Server sync** - Works offline, syncs when online
4. **Server-side filtering** - Edge Function respects preferences
5. **Snackbar feedback** - Users see confirmation when toggling
6. **Default to enabled** - New channels are unmuted by default
7. **Cross-device sync** - Preferences sync via Supabase

### User Experience

| Action | UI Response | Backend |
|--------|-------------|---------|
| Long-press channel | Bottom sheet appears | - |
| Tap "Mute" | Icon appears, snackbar shown | Syncs to Supabase |
| Tap "Unmute" | Icon removed, snackbar shown | Syncs to Supabase |
| New post in muted channel | No notification | Edge Function filters |
| New post in unmuted channel | Notification arrives | Edge Function sends |

## Database Schema

### notification_preferences table

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| user_id | uuid | References auth.users |
| channel_id | uuid | References organizations |
| notifications_enabled | boolean | Whether notifications are enabled |
| created_at | timestamp | When preference was created |
| updated_at | timestamp | When preference was last updated |

**Indexes:**
- `(user_id, channel_id)` - For fast lookups (unique)
- `(channel_id) WHERE notifications_enabled = true` - For Edge Function queries

## Advanced Configuration

### Customize the bottom sheet:

In `channels_list.dart`, modify `_showNotificationMenu()`:

```dart
// Add more options like:
- Mute for 1 hour
- Mute for 24 hours
- Mute forever
- Custom notification sound
```

### Add global settings:

Create a settings screen that uses:
```dart
await NotificationPreferencesService.instance.setGlobalNotificationEnabled(false);
```

### Batch operations:

Enable/disable multiple channels at once:
```dart
final channelIds = ['id1', 'id2', 'id3'];
await NotificationPreferencesService.instance.setEnabledChannels(channelIds.toSet());
```

## Troubleshooting

### Notifications still arriving after muting

1. Check if preference is in database:
   ```sql
   SELECT * FROM notification_preferences 
   WHERE channel_id = 'your-channel-id' 
   AND user_id = 'your-user-id';
   ```

2. Check Edge Function logs for filtering:
   ```bash
   supabase functions logs send-fcm-notification --tail
   ```

3. Verify RLS policies allow reads:
   ```sql
   -- Should return rows
   SELECT * FROM notification_preferences 
   WHERE auth.uid() = user_id;
   ```

### Icon not showing

1. Check `_loadNotificationState()` is being called
2. Verify `mounted` check in setState
3. Add debug logging:
   ```dart
   print('Notification enabled for ${widget.channel.id}: $_isNotificationEnabled');
   ```

### Sync not working

1. Verify user is logged in:
   ```dart
   print(Supabase.instance.client.auth.currentUser?.id);
   ```

2. Check network connectivity
3. Review Supabase logs for errors
4. Verify service role key is set in Edge Function environment

## Performance Considerations

- **Local-first:** UI reads from SharedPreferences (fast)
- **Async sync:** Supabase sync happens in background
- **Indexed queries:** Database uses indexes for fast lookups
- **Batch filtering:** Edge Function queries preferences once per notification batch

## Security

- **RLS enabled:** Users can only read/write their own preferences
- **Service role access:** Edge Function uses service role to read all preferences
- **User ID validation:** All queries validate `auth.uid()`

## Migration from Existing Implementation

If you had a previous notification system:

1. **Backfill preferences for existing users:**
   ```sql
   -- Enable notifications for all existing follows
   INSERT INTO notification_preferences (user_id, channel_id, notifications_enabled)
   SELECT user_id, organization_id, true
   FROM user_follows
   ON CONFLICT (user_id, channel_id) DO NOTHING;
   ```

2. **Sync local preferences to server:**
   ```dart
   // Run once for all users
   await NotificationPreferencesService.instance.syncAllPreferencesToSupabase();
   ```

## Next Steps

1. ✅ Run `notification_preferences_schema.sql` in Supabase
2. ✅ Deploy updated Edge Function
3. ✅ Test muting/unmuting in your app
4. ✅ Add `syncFromSupabase()` call at login
5. ✅ Monitor Edge Function logs

## Support

For issues or questions:
1. Check Edge Function logs: `supabase functions logs`
2. Check database: Query `notification_preferences` table
3. Add debug logging in Flutter service
4. Review this guide's troubleshooting section

---

**Implementation Status:** ✅ Complete - Ready to test!
