-- ============================================================================
-- SUPERADMIN POLICIES FOR DIRECT MESSAGES
-- Allows superadmins to create, view, and manage all direct message conversations
-- and messages on behalf of any user
-- ============================================================================

-- ============================================================================
-- POLICIES FOR direct_message_conversations
-- ============================================================================

-- Superadmins can view all conversations
CREATE POLICY "Superadmins can view all conversations" 
    ON direct_message_conversations 
    FOR SELECT 
    USING (is_superadmin(auth.uid()));

-- Superadmins can create conversations for any user
CREATE POLICY "Superadmins can create conversations for any user" 
    ON direct_message_conversations 
    FOR INSERT 
    WITH CHECK (is_superadmin(auth.uid()));

-- Superadmins can update any conversation
CREATE POLICY "Superadmins can update any conversation" 
    ON direct_message_conversations 
    FOR UPDATE 
    USING (is_superadmin(auth.uid()));

-- ============================================================================
-- POLICIES FOR direct_messages
-- ============================================================================

-- Superadmins can view all messages
CREATE POLICY "Superadmins can view all messages" 
    ON direct_messages 
    FOR SELECT 
    USING (is_superadmin(auth.uid()));

-- Superadmins can send messages in any conversation
CREATE POLICY "Superadmins can send messages in any conversation" 
    ON direct_messages 
    FOR INSERT 
    WITH CHECK (is_superadmin(auth.uid()));

-- Superadmins can update any message
CREATE POLICY "Superadmins can update any message" 
    ON direct_messages 
    FOR UPDATE 
    USING (is_superadmin(auth.uid()));

