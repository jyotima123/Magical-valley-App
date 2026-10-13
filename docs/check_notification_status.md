# Notification Flow Status Check

## ✅ What's Working

Based on the log you shared, the **database trigger IS working**:

```
"Processing notification for post: 1b8640a5-b49f-4c3f-afb1-fbe42ddfda7b in channel: dbe6ceb3-a1a0-4d5a-8e45-38a7bb508acd"
```

This confirms:
1. ✅ Trigger fires when post is created
2. ✅ Edge Function is called successfully
3. ✅ Payload (postId, channelId) is passed correctly

## 🔍 What to Check Next

Run these queries in Supabase SQL Editor to verify the full flow:

### 1. Check if notifications were logged (shows completion)

```sql
SELECT 
  post_id,
  channel_id,
  recipient_count,
  success_count,
  failure_count,
  sent_at
FROM notification_logs 
WHERE post_id = '1b8640a5-b49f-4c3f-afb1-fbe42ddfda7b'
ORDER BY sent_at DESC;
```

**Expected outcomes:**
- ✅ **If you see a row**: Edge Function completed! Check `success_count` vs `failure_count`
- ❌ **If no rows**: Edge Function errored before reaching the log insert
- ⚠️ **If `recipient_count = 0`**: No users to notify (see "Why No Recipients?" below)

### 2. Check Supabase Edge Function logs

Go to: **Supabase Dashboard → Edge Functions → send-fcm-notification → Logs**

Look for:
- ✅ **"Sent to X/Y" messages**: Notifications sent successfully
- ❌ **Error messages**: Firebase credential issues, API errors, etc.
- ⚠️ **"No followers"** or **"No FCM tokens"**: No recipients to send to

### 3. Check who should receive notifications for this channel

```sql
SELECT 
  uf.user_id,
  up.email,
  up.full_name,
  CASE WHEN uft.fcm_token IS NOT NULL THEN '✅ Has token' ELSE '❌ No token' END as token_status,
  COALESCE(np.notifications_enabled, true) as notifications_enabled
FROM user_follows uf
JOIN user_profiles up ON uf.user_id = up.id
LEFT JOIN user_fcm_tokens uft ON uf.user_id = uft.user_id
LEFT JOIN notification_preferences np ON (
  uf.user_id = np.user_id AND 
  uf.organization_id = np.channel_id
)
WHERE uf.organization_id = 'dbe6ceb3-a1a0-4d5a-8e45-38a7bb508acd';
```

## 🔍 Common Issues & Solutions

### Issue 1: No row in `notification_logs`
**Problem:** Edge Function crashed before completing

**Check:** Edge Function logs for errors (likely Firebase credentials or API issues)

**Solution:**
```bash
# Verify these environment variables are set in Edge Functions:
FIREBASE_PRIVATE_KEY
FIREBASE_CLIENT_EMAIL
FIREBASE_PROJECT_ID
```

---

### Issue 2: `recipient_count = 0`
**Problem:** No users to send notifications to

**Possible causes:**
- ❌ No users are following the channel
- ❌ Followers don't have FCM tokens registered
- ❌ All followers have muted notifications for this channel

**Solution:** Check query #3 above to see why

---

### Issue 3: `success_count = 0` but `recipient_count > 0`
**Problem:** FCM API rejecting all notification attempts

**Common causes:**
- Invalid Firebase credentials
- Expired/invalid FCM tokens
- Wrong Firebase project ID

**Solution:** Check Edge Function logs for Firebase API error responses

---

### Issue 4: Notifications sent but not received on device
**Problem:** Client-side issue

**Check:**
1. Device notification permissions enabled?
2. FCM token correctly registered?
3. App handling FCM messages correctly?

**Test:** Send a test notification from Firebase Console to isolate the issue

## 🧪 Quick Test

To verify the complete flow works:

```sql
-- 1. Make sure you're following a test channel
INSERT INTO user_follows (user_id, organization_id)
VALUES (auth.uid(), 'dbe6ceb3-a1a0-4d5a-8e45-38a7bb508acd')
ON CONFLICT (user_id, organization_id) DO NOTHING;

-- 2. Make sure you have an FCM token (this would normally come from your Flutter app)
-- You can check with:
SELECT * FROM user_fcm_tokens WHERE user_id = auth.uid();

-- 3. Create a test post
INSERT INTO posts (
  organization_id,
  created_by,
  title,
  content,
  status,
  post_type
) VALUES (
  'dbe6ceb3-a1a0-4d5a-8e45-38a7bb508acd',
  auth.uid(),
  'Test Notification',
  'Testing end-to-end notification flow',
  'active',
  'text'
);

-- 4. Immediately check if notification was logged
SELECT * FROM notification_logs ORDER BY sent_at DESC LIMIT 1;
```

## 📊 Monitoring Dashboard Query

Use this to monitor all recent notifications:

```sql
SELECT 
  p.title as post_title,
  o.name as channel_name,
  p.created_at as post_time,
  nl.recipient_count,
  nl.success_count,
  nl.failure_count,
  nl.sent_at as notification_time,
  CASE 
    WHEN nl.id IS NULL THEN '❌ Not sent'
    WHEN nl.success_count > 0 THEN '✅ Sent'
    WHEN nl.recipient_count = 0 THEN '⚠️ No recipients'
    ELSE '❌ Failed'
  END as status
FROM posts p
JOIN organizations o ON p.organization_id = o.id
LEFT JOIN notification_logs nl ON p.id = nl.post_id
WHERE p.created_at > NOW() - INTERVAL '1 hour'
ORDER BY p.created_at DESC;
```

## 🎯 Next Steps

1. **Run the verification queries** above to see where the flow is at
2. **Check Edge Function logs** for any error messages
3. **Share the results** if you need help debugging further

The fact that you're seeing "Processing notification..." means you're 90% there! 🎉

