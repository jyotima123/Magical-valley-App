-- ============================================================================
-- DIRECT MESSAGE NOTIFICATION TRIGGER SETUP
-- ============================================================================
-- This script sets up automatic push notifications when direct messages are sent
--
-- Logic:
-- - When a user sends a message to an organization: notify all admins of that organization
-- - When an admin sends a message to a user: notify that user
-- ============================================================================

-- REMEMBER THAT THE supabase_url DEPENDS ON THE ENVIRONMENT
-- QA
-- supabase_url text := 'https://yavxzgcgoasicjprzfcv.supabase.co';

-- Production
-- supabase_url text := 'https://jivehzyxobdggekoyrzh.supabase.co';

-- 1. Create the notification function for direct messages
CREATE OR REPLACE FUNCTION notify_direct_message_created()
RETURNS TRIGGER AS $$
DECLARE
  conversation_user_id uuid;
  conversation_org_id uuid;
  organization_name text;
  sender_name text;
  recipient_user_id uuid;
  admin_user_id uuid;
  supabase_url text := 'https://jivehzyxobdggekoyrzh.supabase.co';
  service_role_key text;
  message_preview text;
BEGIN
  -- Get service role key from Vault
  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF service_role_key IS NULL THEN
    RAISE WARNING 'Service role key not found in Vault';
    RETURN NEW;
  END IF;

  -- Get conversation details
  SELECT user_id, organization_id
  INTO conversation_user_id, conversation_org_id
  FROM direct_message_conversations
  WHERE id = NEW.conversation_id;

  -- Get organization name
  SELECT name INTO organization_name
  FROM organizations
  WHERE id = conversation_org_id;

  -- Get sender name
  SELECT full_name INTO sender_name
  FROM user_profiles
  WHERE id = NEW.sender_id;

  -- Prepare message preview (truncate to 100 chars)
  message_preview := LEFT(COALESCE(NEW.content, ''), 100);

  -- Determine notification recipients based on who sent the message
  IF NEW.sender_id = conversation_user_id THEN
    -- User sent message to organization → notify all admins of that organization
    FOR admin_user_id IN
      SELECT ao.user_id
      FROM admin_organizations ao
      WHERE ao.organization_id = conversation_org_id
    LOOP
      -- Call the edge function for each admin
      PERFORM
        net.http_post(
          url := supabase_url || '/functions/v1/send-fcm-notification',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
          ),
          body := jsonb_build_object(
            'postId', NEW.id,
            'channelId', conversation_org_id,
            'recipientUserId', admin_user_id,
            'title', COALESCE(sender_name, 'User') || ' - ' || COALESCE(organization_name, 'Organization'),
            'body', message_preview,
            'authorName', COALESCE(sender_name, 'User'),
            'notificationType', 'direct_message',
            'conversationId', NEW.conversation_id
          )
        );
    END LOOP;
  ELSE
    -- Admin sent message to user → notify the user
    PERFORM
      net.http_post(
        url := supabase_url || '/functions/v1/send-fcm-notification',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_role_key
        ),
        body := jsonb_build_object(
          'postId', NEW.id,
          'channelId', conversation_org_id,
          'recipientUserId', conversation_user_id,
          'title', COALESCE(organization_name, 'Organization'),
          'body', message_preview,
          'authorName', COALESCE(organization_name, 'Organization'),
          'notificationType', 'direct_message',
          'conversationId', NEW.conversation_id
        )
      );
  END IF;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log the error but don't fail the message insert
    RAISE WARNING 'Direct message notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Create the trigger on direct_messages table
DROP TRIGGER IF EXISTS direct_message_notification ON direct_messages;
CREATE TRIGGER direct_message_notification
  AFTER INSERT ON direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_direct_message_created();

-- ============================================================================
-- NOTES:
-- ============================================================================
-- - The trigger fires after each direct message is inserted
-- - If the sender is the conversation user, all admins of the organization are notified
-- - If the sender is an admin, only the conversation user is notified
-- - Errors in notification sending don't prevent message creation
-- - The Edge Function should handle the 'notificationType' = 'direct_message' to route appropriately
-- ============================================================================
