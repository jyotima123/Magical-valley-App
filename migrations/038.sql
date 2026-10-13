CREATE OR REPLACE FUNCTION notify_post_created()
RETURNS TRIGGER AS $$
DECLARE
  channel_name text;
  author_name text;
  supabase_url text := 'https://jivehzyxobdggekoyrzh.supabase.co';
  service_role_key text;
  post_content text;
  post_title text;
  vault_secret record;
BEGIN
  -- Get service role key from Vault
  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;
  
  IF service_role_key IS NULL THEN
    RAISE EXCEPTION 'Service role key not found in Vault';
  END IF;
  
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
  
  -- Call the edge function
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
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
