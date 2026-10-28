-- Allow organization admins to create direct message conversations on behalf of
-- any user for organizations they manage.
--
-- The existing INSERT policy ("Users can create their own conversations") only
-- passes when auth.uid() = user_id. When an admin initiates a conversation the
-- row's user_id is the regular user's ID, not the admin's, so that policy fails.
-- Superadmins already have an unrestricted INSERT policy (045); this fills the
-- gap for regular admins.

CREATE POLICY "Organization admins can create conversations for their org"
    ON direct_message_conversations
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = auth.uid()
            AND organization_id = direct_message_conversations.organization_id
        )
    );
