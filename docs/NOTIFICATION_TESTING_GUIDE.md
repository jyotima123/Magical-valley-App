# 🔔 Push Notification Testing Guide

This guide explains how to test FCM (Firebase Cloud Messaging) push notifications in your app.

## Prerequisites

✅ FCM token storage is working (check logs for "FCM token stored in Supabase")  
✅ You have an FCM Server Key from Firebase Console  
✅ The Edge Function is deployed to Supabase  

---

## Method 1: Firebase Console (Easiest)

Perfect for quick testing without any setup!

### Steps:

1. **Get your FCM token from app logs:**
   ```
   [FCMService] FCM Token obtained: f6XV0SZWqEfeuv6_5utR...
   ```
   Copy the full token (it's quite long).

2. **Open Firebase Console:**
   - Go to: https://console.firebase.google.com/
   - Select your project
   - Navigate to **Cloud Messaging** (left sidebar under "Engage")

3. **Send test message:**
   - Click **"Send your first message"** or **"New notification"**
   - Fill in:
     - **Title**: "Test Notification"
     - **Text**: "Hello from Firebase! 👋"
   - Click **"Send test message"**
   - Paste your FCM token
   - Click the **+** button to add it
   - Click **"Test"**

4. **Check your device:**
   - You should receive a notification immediately!
   - If the app is in foreground, check console logs
   - If in background, you'll see a system notification

---

## Method 2: Using the Test Script

Use the provided bash script for quick testing.

### Steps:

1. **Edit the script configuration:**
   ```bash
   nano test_notification.sh
   ```
   
   Update these values:
   ```bash
   SUPABASE_PROJECT_REF="yavxzgcgoasicjprzfcv"  # Your project ref
   SUPABASE_ANON_KEY="eyJhb..."                  # Your anon key
   ORGANIZATION_ID="14deab1d..."                 # Channel you follow
   ```

2. **Run the script:**
   ```bash
   ./test_notification.sh
   ```

3. **Check the output:**
   - ✅ Success = notifications sent to all followers
   - ❌ Error = check the troubleshooting section

---

## Method 3: Using curl

Send a test notification directly with curl:

```bash
curl -X POST 'https://yavxzgcgoasicjprzfcv.supabase.co/functions/v1/send-fcm-notification' \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "postId": "test-123",
    "channelId": "14deab1d-0cde-4030-a604-045feeb63705",
    "title": "Test Notification",
    "body": "Testing push notifications!",
    "authorName": "Test User"
  }'
```

**Important:** Replace:
- `YOUR_ANON_KEY` with your Supabase anon key
- `channelId` with an organization ID you're following

---

## Method 4: Automatic Notifications (Production Setup)

Set up automatic notifications when posts are created.

### Steps:

1. **Enable pg_net extension:**
   - Open Supabase Dashboard
   - Go to **Database → Extensions**
   - Search for "pg_net" and enable it

2. **Run the trigger setup script:**
   ```bash
   # In Supabase SQL Editor, run:
   cat supabase/setup_notification_trigger.sql
   ```

3. **Configure environment variables:**
   In Supabase SQL Editor:
   ```sql
   ALTER DATABASE postgres SET app.settings.supabase_url = 'https://yavxzgcgoasicjprzfcv.supabase.co';
   ALTER DATABASE postgres SET app.settings.service_role_key = 'your-service-role-key';
   ```

4. **Test by creating a post:**
   - Open your app
   - Create a new post in any channel
   - All followers should receive a notification!

---

## Method 5: Postman/Insomnia

If you prefer GUI testing tools:

### Postman Setup:

1. **Create new request:**
   - Method: `POST`
   - URL: `https://yavxzgcgoasicjprzfcv.supabase.co/functions/v1/send-fcm-notification`

2. **Headers:**
   ```
   Authorization: Bearer YOUR_ANON_KEY
   Content-Type: application/json
   ```

3. **Body (JSON):**
   ```json
   {
     "postId": "test-post-123",
     "channelId": "14deab1d-0cde-4030-a604-045feeb63705",
     "title": "Test from Postman",
     "body": "This is a test notification!",
     "authorName": "Postman User"
   }
   ```

4. **Send** and check response!

---

## Verifying Setup

### 1. Check FCM tokens are stored:

Run this in Supabase SQL Editor:
```sql
SELECT 
  u.email,
  u.full_name,
  t.fcm_token,
  t.created_at
FROM user_fcm_tokens t
JOIN user_profiles u ON u.id = t.user_id
ORDER BY t.created_at DESC;
```

You should see your user's FCM token.

### 2. Check you're following an organization:

```sql
SELECT 
  u.email,
  o.name as organization_name,
  f.followed_at
FROM user_follows f
JOIN user_profiles u ON u.id = f.user_id
JOIN organizations o ON o.id = f.organization_id
WHERE u.email = 'your-email@example.com';
```

### 3. Check Edge Function is deployed:

```bash
supabase functions list
```

Should show `send-fcm-notification` in the list.

### 4. Check Edge Function logs:

```bash
supabase functions logs send-fcm-notification
```

---

## Troubleshooting

### ❌ "No FCM tokens found"

**Problem:** User doesn't have a stored FCM token  
**Solution:** 
- Restart the app
- Check logs for "FCM token stored in Supabase"
- Verify `user_fcm_tokens` table exists

### ❌ "No followers to notify"

**Problem:** No users are following the channel  
**Solution:** 
- Make sure you're following the organization in the app
- Check with SQL: `SELECT * FROM user_follows WHERE organization_id = 'your-org-id'`

### ❌ "FCM request failed"

**Problem:** Invalid FCM Server Key  
**Solution:**
- Get the correct key from Firebase Console → Project Settings → Cloud Messaging → Server Key
- Set it in Supabase: Project Settings → Edge Functions → Add `FCM_SERVER_KEY`
- Redeploy the function: `supabase functions deploy send-fcm-notification`

### ❌ "Function not found"

**Problem:** Edge Function not deployed  
**Solution:**
```bash
cd /Users/alisson/Documents/Projetos/mvc_app
supabase functions deploy send-fcm-notification
```

### ❌ "Permission denied"

**Problem:** RLS policies blocking access  
**Solution:**
- Check that RLS policies allow service role to access `user_fcm_tokens`
- Run: `SELECT * FROM user_fcm_tokens` in SQL Editor (should work)

### ❌ Notification not appearing on device

**Possible causes:**
1. **App in foreground:** Notifications may not show when app is open
2. **Permissions denied:** Check notification permissions in device settings
3. **Token expired:** Restart app to refresh FCM token
4. **Wrong token:** Verify the token in database matches current device token

---

## Testing Checklist

- [ ] FCM token stored successfully (check logs)
- [ ] Following at least one organization
- [ ] Edge Function deployed
- [ ] FCM_SERVER_KEY set in Supabase
- [ ] Can send test notification from Firebase Console
- [ ] Can send test notification using curl/script
- [ ] Notification appears on device
- [ ] Notification opens correct screen when tapped
- [ ] Works in both foreground and background
- [ ] Works on both iOS and Android

---

## Quick Reference

### Get your Supabase credentials:

```bash
# Project Reference (from URL)
# Example: yavxzgcgoasicjprzfcv from https://yavxzgcgoasicjprzfcv.supabase.co

# Anon Key
Supabase Dashboard → Project Settings → API → anon public

# Service Role Key  
Supabase Dashboard → Project Settings → API → service_role (secret!)
```

### Get your FCM Server Key:

```bash
Firebase Console → Project Settings → Cloud Messaging → Server Key (legacy)
```

### Deploy Edge Function:

```bash
supabase functions deploy send-fcm-notification
```

### View logs:

```bash
# Edge Function logs
supabase functions logs send-fcm-notification

# Flutter app logs
flutter logs

# Or in Android Studio / Xcode console
```

---

## Need Help?

Common commands:
```bash
# Deploy function
supabase functions deploy send-fcm-notification

# Test function locally
supabase functions serve send-fcm-notification

# View logs
supabase functions logs send-fcm-notification --follow

# List all functions
supabase functions list
```

---

Happy testing! 🎉

