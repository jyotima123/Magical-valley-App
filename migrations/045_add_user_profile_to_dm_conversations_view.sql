-- ============================================================================
-- ADD USER PROFILE INFORMATION TO DIRECT MESSAGE CONVERSATIONS VIEW
-- This migration updates the direct_message_conversations_view to include
-- user profile information (username, full_name, profile_picture_url) so
-- admins can see user names without needing separate API calls.
-- ============================================================================

-- Drop the existing view first (we need to recreate it with new columns)
DROP VIEW IF EXISTS direct_message_conversations_view;

-- Recreate the view with user profile information included
CREATE VIEW direct_message_conversations_view AS
SELECT 
    dmc.id,
    dmc.user_id,
    dmc.organization_id,
    dmc.created_at,
    dmc.updated_at,
    o.name AS organization_name,
    o.logo_url AS organization_logo_url,
    -- User profile information (for admins viewing conversations)
    up.username AS user_username,
    up.full_name AS user_full_name,
    up.profile_picture_url AS user_profile_picture_url,
    -- Last message information
    (
        SELECT dm2.id
        FROM direct_messages dm2
        WHERE dm2.conversation_id = dmc.id
        ORDER BY dm2.created_at DESC
        LIMIT 1
    ) AS last_message_id,
    (
        SELECT dm2.content
        FROM direct_messages dm2
        WHERE dm2.conversation_id = dmc.id
        ORDER BY dm2.created_at DESC
        LIMIT 1
    ) AS last_message_content,
    (
        SELECT dm2.sender_id
        FROM direct_messages dm2
        WHERE dm2.conversation_id = dmc.id
        ORDER BY dm2.created_at DESC
        LIMIT 1
    ) AS last_message_sender_id,
    (
        SELECT dm2.created_at
        FROM direct_messages dm2
        WHERE dm2.conversation_id = dmc.id
        ORDER BY dm2.created_at DESC
        LIMIT 1
    ) AS last_message_created_at,
    -- Unread count
    (
        SELECT get_conversation_unread_count(dmc.id, dmc.user_id)
    ) AS unread_count
FROM direct_message_conversations dmc
JOIN organizations o ON o.id = dmc.organization_id
LEFT JOIN user_profiles up ON up.id = dmc.user_id;  -- LEFT JOIN in case profile doesn't exist

-- Grant access to the updated view
GRANT SELECT ON direct_message_conversations_view TO authenticated;

