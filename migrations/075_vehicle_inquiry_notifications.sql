-- ============================================================================
-- Migration 075: Push notifications for vehicle inquiry messages
-- ============================================================================
-- Mirrors the direct-message notification setup (migration 064): every new
-- vehicle_inquiry_messages row calls the dedicated send-vehicle-inquiry-
-- notification edge function, which notifies the other participant (buyer or
-- seller) of the conversation.
--
-- ⚠️  REMEMBER: supabase_url must match the environment.
--     QA:         https://yavxzgcgoasicjprzfcv.supabase.co
--     Production: https://jivehzyxobdggekoyrzh.supabase.co
-- Defaults to QA because the Cars tab currently only exists in the QA flavour.
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_vehicle_inquiry_message_created()
RETURNS TRIGGER AS $$
DECLARE
  supabase_url    text := 'https://yavxzgcgoasicjprzfcv.supabase.co';
  service_role_key text;
  message_preview text;
BEGIN
  -- Fetch service role key from Supabase Vault
  SELECT decrypted_secret INTO service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF service_role_key IS NULL THEN
    RAISE WARNING 'notify_vehicle_inquiry_message_created: service_role_key not found in Vault';
    RETURN NEW;
  END IF;

  -- Truncate message body for the notification preview (edge function also
  -- truncates, but keep the payload small).
  message_preview := LEFT(COALESCE(NEW.content, ''), 200);

  -- Recipient logic (notify the other participant) lives in the edge function.
  PERFORM net.http_post(
    url     := supabase_url || '/functions/v1/send-vehicle-inquiry-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || service_role_key
    ),
    body    := jsonb_build_object(
      'conversationId', NEW.conversation_id,
      'senderId',       NEW.sender_id,
      'messageContent', message_preview,
      'messageType',    NEW.message_type
    )
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Never let a notification failure block the message insert
    RAISE WARNING 'notify_vehicle_inquiry_message_created: notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS vehicle_inquiry_message_notification ON vehicle_inquiry_messages;
CREATE TRIGGER vehicle_inquiry_message_notification
  AFTER INSERT ON vehicle_inquiry_messages
  FOR EACH ROW
  EXECUTE FUNCTION notify_vehicle_inquiry_message_created();
