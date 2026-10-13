# Notification System Debug Guide

## Current Issue
The Edge Function is not being triggered when posts are created, and there are errors in the query logic.

## Root Causes Found

### 1. Edge Function Query Issue
The error log shows:
```
Could not find a relationship between 'user_follows' and 'user_fcm_tokens' in the schema cache
```

This means an old version of the Edge Function is deployed that tries to use `!inner` join between these tables.

### 2. Database Trigger Not Configured
The trigger needs `pg_net` extension and database settings that may not be configured.

---

## Step-by-Step Fix

### Step 1: Verify/Redeploy Edge Function

First, make sure the correct version of your Edge Function is deployed:

```bash
# From your project root
cd supabase/functions
supabase functions deploy send-fcm-notification
```

The correct version should query the tables separately (as in your index.ts file), not using `!inner` join.

### Step 2: Enable pg_net Extension

Run this in Supabase SQL Editor:

```sql
-- Enable the pg_net extension (required for HTTP requests from database)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Verify it's enabled
SELECT * FROM pg_extension WHERE extname = 'pg_net';
```

### Step 3: Configure Database Settings

Run these commands in Supabase SQL Editor (replace with your actual values):

```sql
-- Set Supabase URL
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://yavxzgcgoasicjprzfcv.supabase.co';

-- Set service role key (get this from Supabase Dashboard → Settings → API)
ALTER DATABASE postgres SET app.settings.service_role_key = 'your-service-role-key-here';

-- Verify settings were saved
SHOW app.settings.supabase_url;
SHOW app.settings.service_role_key;
```

### Step 4: Set Edge Function Environment Variables

In Supabase Dashboard → Edge Functions → send-fcm-notification → Settings:

Set these environment variables:
- `FIREBASE_PRIVATE_KEY` - Your Firebase private key
- `FIREBASE_CLIENT_EMAIL` - Your Firebase client email
- `FIREBASE_PROJECT_ID` - Your Firebase project ID
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Your service role key

### Step 5: Grant Permissions for net.http_post

Run this in Supabase SQL Editor:

```sql
-- Grant permission to use pg_net
GRANT USAGE ON SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA net TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA net TO postgres, anon, authenticated, service_role;
```

### Step 6: Recreate the Trigger

Run the setup script again:

```sql
-- Drop existing trigger and function
DROP TRIGGER IF EXISTS post_created_notification ON posts;
DROP FUNCTION IF EXISTS notify_post_created();

-- Recreate from supabase/setup_notification_trigger.sql
-- (The script is already correct, just run it again)
```

### Step 7: Test the Setup

#### A. Test Database Trigger Function Manually

```sql
-- Test if the function can be called (without actually triggering HTTP)
SELECT notify_post_created();
```

#### B. Test with a Real Post Insert

```sql
-- Insert a test post (replace with valid IDs)
INSERT INTO posts (
  organization_id,
  created_by,
  title,
  content,
  status,
  post_type
) VALUES (
  '14deab1d-0cde-4030-a604-045feeb63705', -- Valid channel ID
  auth.uid(), -- Current user
  'Test Post',
  'Testing notifications',
  'active',
  'text'
);

-- Check if HTTP request was queued
SELECT * FROM net.http_request_queue ORDER BY id DESC LIMIT 5;

-- Check notification logs (should appear after Edge Function runs)
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 5;
```

#### C. Check Edge Function Logs

In Supabase Dashboard → Edge Functions → send-fcm-notification → Logs

Look for:
- Any incoming requests
- Error messages
- Success responses

---

## Common Issues & Solutions

### Issue: "Could not find a relationship"
**Solution**: Redeploy the Edge Function (Step 1) - the old version is running

### Issue: "net.http_post" does not exist
**Solution**: Enable pg_net extension (Step 2)

### Issue: Trigger fires but no HTTP request
**Solution**: Check database settings (Step 3) and permissions (Step 5)

### Issue: HTTP request sent but Edge Function fails
**Solution**: Check Edge Function logs and verify environment variables (Step 4)

### Issue: No rows in notification_logs
**Solution**: 
1. Check if the post INSERT succeeded
2. Verify the trigger is active: `SELECT * FROM pg_trigger WHERE tgname = 'post_created_notification';`
3. Check if user_follows exist for the organization
4. Check if users have FCM tokens

---

## Verification Queries

### Check if trigger exists and is enabled:
```sql
SELECT 
  trigger_name,
  event_manipulation,
  action_statement,
  action_timing,
  action_orientation,
  tgenabled::char
FROM information_schema.triggers 
WHERE trigger_name = 'post_created_notification';
```

### Check if function exists:
```sql
SELECT 
  proname,
  prosrc,
  prorettype::regtype
FROM pg_proc 
WHERE proname = 'notify_post_created';
```

### Check database settings:
```sql
SELECT name, setting 
FROM pg_settings 
WHERE name LIKE 'app.settings%';
```

### Check if users are following the organization:
```sql
SELECT 
  uf.user_id,
  up.email,
  ft.fcm_token IS NOT NULL as has_token
FROM user_follows uf
JOIN user_profiles up ON uf.user_id = up.id
LEFT JOIN user_fcm_tokens ft ON uf.user_id = ft.user_id
WHERE uf.organization_id = 'your-org-id-here';
```

### Check pg_net queue:
```sql
-- Check pending requests
SELECT * FROM net.http_request_queue WHERE status = 'pending';

-- Check recent requests (success/failure)
SELECT * FROM net._http_response ORDER BY created DESC LIMIT 10;
```

---

## Testing Checklist

- [ ] pg_net extension is enabled
- [ ] Database settings are configured (supabase_url, service_role_key)
- [ ] Edge Function is deployed with correct code
- [ ] Edge Function environment variables are set
- [ ] Trigger function exists and is enabled
- [ ] Trigger is attached to posts table
- [ ] At least one user follows the test organization
- [ ] That user has an FCM token registered
- [ ] Test post insert completes successfully
- [ ] HTTP request appears in net.http_request_queue
- [ ] Edge Function logs show incoming request
- [ ] notification_logs table shows results

---

## Alternative Approach: Bypass Database Trigger

If the database trigger approach is too complex, you can call the Edge Function directly from your Flutter app after creating a post:

```dart
// In your chat_service.dart after successful post creation:
Future<void> _sendNotification(String postId, String channelId) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'send-fcm-notification',
      body: {
        'postId': postId,
        'channelId': channelId,
        'title': 'New post in $channelName',
        'body': '$authorName posted: $preview',
        'authorName': authorName,
      },
    );
    print('Notification sent: ${response.data}');
  } catch (e) {
    print('Failed to send notification: $e');
    // Don't throw - notification failure shouldn't break post creation
  }
}
```

This is simpler and doesn't require pg_net or database triggers.

