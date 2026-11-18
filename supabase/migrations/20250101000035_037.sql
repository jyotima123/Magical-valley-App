-- added by export_supabase_migrations.py
SET search_path TO public, extensions;

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
