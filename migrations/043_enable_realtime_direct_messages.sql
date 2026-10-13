-- ============================================================================
-- ENABLE REALTIME FOR DIRECT MESSAGES
-- This enables Supabase Realtime for the direct messaging tables
-- ============================================================================

-- Enable realtime for direct_messages table
-- This allows the .stream() method in the Flutter app to receive real-time updates
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;

-- Enable realtime for direct_message_conversations table
-- This allows the conversations list to update in real-time when new messages arrive
ALTER PUBLICATION supabase_realtime ADD TABLE direct_message_conversations;

-- Verify that realtime is enabled (this is just for reference, won't fail if already enabled)
-- You can run this query separately to check:
-- SELECT 
--     schemaname,
--     tablename
-- FROM pg_publication_tables
-- WHERE pubname = 'supabase_realtime'
-- AND tablename IN ('direct_messages', 'direct_message_conversations');
