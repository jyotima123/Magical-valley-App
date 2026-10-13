-- Check if trigger exists
SELECT 
  trigger_name, 
  event_manipulation, 
  action_statement,
  action_timing
FROM information_schema.triggers 
WHERE trigger_name = 'post_created_notification';

-- Check if function exists
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'notify_post_created';
