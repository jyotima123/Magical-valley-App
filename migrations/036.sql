-- ============================================================================
-- NOTIFICATION TRIGGER SETUP
-- ============================================================================
-- This script sets up automatic push notifications when posts are created

-- 1. First, create the notification_logs table if it doesn't exist
CREATE TABLE IF NOT EXISTS notification_logs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id uuid NOT NULL,
  channel_id uuid NOT NULL,
  recipient_count integer NOT NULL DEFAULT 0,
  success_count integer NOT NULL DEFAULT 0,
  failure_count integer NOT NULL DEFAULT 0,
  sent_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Enable RLS on notification_logs
ALTER TABLE notification_logs ENABLE ROW LEVEL SECURITY;

-- 3. Create policy for service role to insert logs
DROP POLICY IF EXISTS "Service role can insert logs" ON notification_logs;
CREATE POLICY "Service role can insert logs" ON notification_logs
  FOR INSERT WITH CHECK (true); -- Edge function uses service role

-- 4. Create the function that calls the Edge Function
CREATE OR REPLACE FUNCTION notify_post_created()
RETURNS TRIGGER AS $$
DECLARE
  channel_name text;
  author_name text;
  supabase_url text;
  service_role_key text;
  post_content text;
  post_title text;
BEGIN
  -- Get environment variables (you'll need to set these in Supabase Vault)
  -- For now, we'll use the public URL - replace with your actual project URL
  supabase_url := current_setting('app.settings.supabase_url', true);
  service_role_key := current_setting('app.settings.service_role_key', true);
  
  -- Get channel/organization name
  SELECT name INTO channel_name
  FROM organizations 
  WHERE id = NEW.organization_id;
  
  -- Get author name
  SELECT full_name INTO author_name
  FROM user_profiles 
  WHERE id = NEW.created_by;
  
  -- Prepare post content
  post_title := COALESCE(NEW.title, '');
  post_content := COALESCE(NEW.content, '');
  
  -- Call the edge function to send notifications
  -- Note: You'll need the pg_net extension enabled for this
  PERFORM
    net.http_post(
      url := supabase_url || '/functions/v1/send-fcm-notification',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body := jsonb_build_object(
        'postId', NEW.id,
        'channelId', NEW.organization_id,
        'title', 'New post in ' || COALESCE(channel_name, 'a channel'),
        'body', COALESCE(author_name, 'Someone') || ' posted: ' || 
                LEFT(
                  CASE 
                    WHEN post_title != '' THEN post_title
                    WHEN post_content != '' THEN post_content
                    ELSE 'New content'
                  END, 
                  100
                ),
        'authorName', COALESCE(author_name, 'Unknown User')
      )
    );
    
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Create the trigger (drop first if exists)
DROP TRIGGER IF EXISTS post_created_notification ON posts;
CREATE TRIGGER post_created_notification
  AFTER INSERT ON posts
  FOR EACH ROW
  WHEN (NEW.status = 'active') -- Only send notifications for active posts
  EXECUTE FUNCTION notify_post_created();

-- ============================================================================
-- CONFIGURATION STEPS
-- ============================================================================
-- After running this script, you need to:
--
-- 1. Enable pg_net extension in Supabase Dashboard:
--    Database → Extensions → Enable "pg_net"
--
-- 2. Set configuration variables in Supabase SQL Editor:
--    Run these commands (replace with your actual values):
--
--    ALTER DATABASE postgres SET app.settings.supabase_url = 'https://yavxzgcgoasicjprzfcv.supabase.co';
--    ALTER DATABASE postgres SET app.settings.service_role_key = 'your-service-role-key-here';
--
-- 3. Make sure FCM_SERVER_KEY is set in Edge Functions environment variables
--
-- ============================================================================
