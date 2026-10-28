# Realtime Messaging Setup Guide

## Current Status

Your code already has realtime subscriptions set up correctly:
- ✅ `streamDirectMessages()` - Streams messages for a conversation
- ✅ `streamDirectMessageConversations()` - Streams conversations list
- ✅ RLS policies are configured correctly
- ✅ The UI subscribes to these streams

## What's Missing

**Supabase Realtime must be explicitly enabled on the database tables.** The migration file creates the tables but doesn't enable realtime.

## Required Steps

### 1. Enable Realtime on `direct_messages` Table

Run this SQL in your Supabase SQL Editor:

```sql
-- Enable realtime for direct_messages table
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;
```

### 2. Enable Realtime on `direct_message_conversations` Table

Run this SQL in your Supabase SQL Editor:

```sql
-- Enable realtime for direct_message_conversations table
ALTER PUBLICATION supabase_realtime ADD TABLE direct_message_conversations;
```

### 3. Verify Realtime is Enabled

Check which tables have realtime enabled:

```sql
SELECT 
    schemaname,
    tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
AND tablename IN ('direct_messages', 'direct_message_conversations');
```

You should see both tables listed.

## Alternative: Enable via Supabase Dashboard

1. Go to **Database** → **Replication** in your Supabase Dashboard
2. Find `direct_messages` table
3. Toggle **Enable Realtime** to ON
4. Repeat for `direct_message_conversations` table

## How It Works

Once realtime is enabled:

1. **When a message is sent:**
   - The message is inserted into `direct_messages` table
   - Supabase Realtime broadcasts the change
   - All clients subscribed to that conversation receive the update via the stream
   - The UI automatically updates with the new message

2. **When a conversation is updated:**
   - The `updated_at` field changes (via trigger)
   - Supabase Realtime broadcasts the change
   - The conversations list stream receives the update
   - The UI shows the updated last message and timestamp

## Troubleshooting

### Messages not appearing in realtime

1. **Check if realtime is enabled:**
   ```sql
   SELECT tablename 
   FROM pg_publication_tables 
   WHERE pubname = 'supabase_realtime' 
   AND tablename = 'direct_messages';
   ```

2. **Check RLS policies:**
   - Ensure the user has SELECT permission on `direct_messages`
   - The RLS policies in `042_direct_messages.sql` should handle this

3. **Check Supabase client connection:**
   - Verify the Supabase client is properly initialized
   - Check network connectivity

4. **Check stream subscription:**
   - Look for `streamDirectMessages` print statements in logs
   - Verify the subscription is active (not cancelled)

### Common Issues

**Issue:** Stream subscription is set up but no updates arrive
- **Solution:** Verify realtime is enabled on the table (Step 1-2 above)

**Issue:** "Permission denied" errors in stream
- **Solution:** Check RLS policies allow SELECT for the current user

**Issue:** Stream works but messages appear out of order
- **Solution:** The code already orders by `created_at DESC` - this should be fine

## Code Reference

The realtime subscriptions are set up in:
- `lib/modules/chat/direct_messages_screen.dart` (lines 307-347, 1147-1187)
- `lib/services/api/supabase_api_service.dart` (lines 4238-4256, 4259-4334)

## Testing

After enabling realtime:

1. Open the app on two devices (or two browser tabs with different users)
2. Send a message from one device
3. The message should appear immediately on the other device without refresh
4. Check the logs for `streamDirectMessages` to confirm the stream is receiving updates
