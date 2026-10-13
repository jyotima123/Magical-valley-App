-- ============================================================================
-- Migration 064: Route DM notifications to dedicated send-dm-notification function
-- ============================================================================
-- Previously, migration 046 set up notify_direct_message_created() to call
-- send-fcm-notification (the channel-post function) with notificationType=
-- 'direct_message'. That created two problems:
--
--   1. It coupled DM and post notifications in a single edge function.
--   2. It looped through admin_organizations without filtering out superadmins,
--      so superadmins would receive DM push notifications.
--
-- This migration replaces that function with a lean version that calls the new
-- dedicated send-dm-notification edge function.  All recipient logic (user →
-- org-admins-only / admin → user, superadmin exclusion) now lives inside that
-- edge function, keeping the trigger simple and the concerns separated.
--
-- ⚠️  REMEMBER: supabase_url must match the environment.
--     QA:         https://yavxzgcgoasicjprzfcv.supabase.co
--     Production: https://jivehzyxobdggekoyrzh.supabase.co
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_direct_message_created()
RETURNS TRIGGER AS $$
DECLARE
  supabase_url    text := 'https://jivehzyxobdggekoyrzh.supabase.co';
  service_role_key text;
  message_preview text;
BEGIN
  -- Fetch service role key from Supabase Vault
  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF service_role_key IS NULL THEN
    RAISE WARNING 'notify_direct_message_created: service_role_key not found in Vault';
    RETURN NEW;
  END IF;

  -- Truncate message body for the notification preview (edge function also truncates,
  -- but we keep this short to avoid sending large payloads over the network).
  message_preview := LEFT(COALESCE(NEW.content, ''), 200);

  -- Delegate ALL recipient logic to send-dm-notification:
  --   • If sender == conversation.user_id → notify org admins only (role='admin', not 'superadmin')
  --   • Otherwise                         → notify the conversation user only
  PERFORM net.http_post(
    url     := supabase_url || '/functions/v1/send-dm-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body    := jsonb_build_object(
      'conversationId',  NEW.conversation_id,
      'senderId',        NEW.sender_id,
      'messageContent',  message_preview
    )
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Never let a notification failure block the message insert
    RAISE WARNING 'notify_direct_message_created: notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-create the trigger (originally created in migration 046)
DROP TRIGGER IF EXISTS direct_message_notification ON direct_messages;
CREATE TRIGGER direct_message_notification
  AFTER INSERT ON direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_direct_message_created();
