# 🚀 Notification Fix - Quick Start Guide

## 🎯 What Was Wrong

Your Firebase initialization was missing the platform-specific configuration, causing FCM tokens to be invalid and notifications to never arrive.

## ✅ What I Fixed

### Files Changed:
1. **`lib/main.dart`**
   - Added import: `package:mvc_app/firebase_options.dart`
   - Fixed: `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`

2. **`lib/services/fcm_service.dart`**
   - Added import: `package:mvc_app/firebase_options.dart`
   - Fixed background handler to use same options

## 🧪 Quick Test (5 minutes)

### 1. Rebuild Your App
```bash
flutter clean && flutter pub get && flutter run
```

### 2. Check Token is Saved
After logging in, run this in Supabase SQL Editor:
```sql
SELECT fcm_token FROM user_fcm_tokens 
WHERE user_id = (
  SELECT id FROM user_profiles 
  WHERE email = 'your-email@example.com'
);
```
✅ Should return a long token (100+ characters)

### 3. Test Direct from Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com) → `spencer-notifications` project
2. **Cloud Messaging** → **Send test message**
3. Paste your FCM token from Step 2
4. Click **Test**

**Result:**
- ✅ **Notification arrives** = App is configured correctly! 
- ❌ **No notification** = See platform-specific setup below

### 4. Test End-to-End

1. Follow a channel in your app
2. Create a post in that channel (via app or SQL):
   ```sql
   INSERT INTO posts (organization_id, created_by, title, content, status, post_type)
   VALUES ('channel-id', auth.uid(), 'Test', 'Hello!', 'active', 'text');
   ```
3. Check your device for notification

## ⚠️ If Notifications Still Don't Work

### For iOS: APNs Configuration Required

Firebase **requires** APNs (Apple Push Notifications) configured:

1. Go to [Firebase Console](https://console.firebase.google.com) → Project Settings → **Cloud Messaging**
2. Scroll to **Apple app configuration**
3. **If empty:** You need to upload an APNs Authentication Key

**To get APNs key:**
1. [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list) → **Keys**
2. Click **+** to create new key
3. Name it "APNs Key" and enable **Apple Push Notifications service (APNs)**
4. **Download** the `.p8` file (can only download once!)
5. Note the **Key ID** shown after creating
6. Note your **Team ID** (top right of Apple Developer page)
7. Upload to Firebase:
   - Upload `.p8` file
   - Enter Key ID
   - Enter Team ID

**Xcode Capabilities:**
Open `ios/Runner.xcworkspace` and verify:
- ✅ **Push Notifications** capability is added
- ✅ **Background Modes** → "Remote notifications" is checked

### For Android: Usually Works Automatically

Should work with `google-services.json` already in place.

**If not working:**
1. Verify notification permission is granted (Settings → Your App → Notifications)
2. For Android 13+: App must request `POST_NOTIFICATIONS` permission at runtime

### Device-Specific Issues

**All Devices:**
- Check Settings → Your App → Notifications are enabled
- Try uninstalling and reinstalling the app
- Make sure you accepted notification permissions prompt

**Xiaomi/MIUI:**
- Settings → Battery & Performance → Manage apps battery usage
- Set your app to "No restrictions"

**Samsung:**
- Settings → Apps → Your App → Battery
- Remove from "Sleeping apps"

## 📊 Verify Everything is Working

```sql
-- 1. Check FCM tokens exist
SELECT COUNT(*) as total_tokens FROM user_fcm_tokens;

-- 2. Check notifications are being sent
SELECT * FROM notification_logs 
ORDER BY sent_at DESC 
LIMIT 5;

-- 3. Check your token specifically
SELECT * FROM user_fcm_tokens uft
JOIN user_profiles up ON uft.user_id = up.id
WHERE up.email = 'your-email@example.com';
```

## 🎉 Success Criteria

1. ✅ Token appears in database
2. ✅ Firebase Console test notification arrives
3. ✅ Creating post triggers notification
4. ✅ Notification appears on device

## 📚 Additional Resources

- **Detailed debugging:** `FIREBASE_NOTIFICATION_DEBUG.md`
- **Testing queries:** `verify_notification_flow.sql`
- **Complete guide:** `NOTIFICATION_FIX_APPLIED.md`

## 💡 Pro Tips

1. **Test both foreground and background:**
   - Foreground = app is open
   - Background = app is minimized
   - Both should show notifications

2. **Check Edge Function logs:**
   - Supabase Dashboard → Edge Functions → send-fcm-notification → Logs
   - Look for "Sent to X/Y" messages

3. **Monitor notification success rate:**
   ```sql
   SELECT 
     SUM(success_count) as total_success,
     SUM(failure_count) as total_failures,
     ROUND(100.0 * SUM(success_count) / NULLIF(SUM(success_count + failure_count), 0), 2) as success_rate
   FROM notification_logs;
   ```

---

**Need help?** Share:
1. Flutter console logs during app startup
2. Results of the SQL queries above
3. Firebase Console test result (works/doesn't work)
4. Platform (iOS/Android)

