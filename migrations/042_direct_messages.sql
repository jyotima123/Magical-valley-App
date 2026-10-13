-- ============================================================================
-- DIRECT MESSAGES SYSTEM
-- Allows users to have direct message conversations with organizations
-- ============================================================================

-- 1. Create direct_message_conversations table
-- Each conversation is between one user and one organization
CREATE TABLE IF NOT EXISTS direct_message_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure one conversation per user-organization pair
    UNIQUE(user_id, organization_id)
);

-- 2. Create direct_messages table
-- Stores individual messages within conversations
CREATE TABLE IF NOT EXISTS direct_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES direct_message_conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'pdf')),
    file_url TEXT,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure file_url is provided for non-text messages
    CONSTRAINT file_required_for_media CHECK (
        (message_type = 'text') OR 
        (message_type IN ('image', 'pdf') AND file_url IS NOT NULL)
    )
);

-- 3. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_dm_conversations_user ON direct_message_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_dm_conversations_org ON direct_message_conversations(organization_id);
CREATE INDEX IF NOT EXISTS idx_dm_conversations_updated ON direct_message_conversations(updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_dm_messages_conversation ON direct_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_dm_messages_sender ON direct_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_dm_messages_created ON direct_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dm_messages_read ON direct_messages(is_read) WHERE is_read = false;

-- 4. Add updated_at triggers
CREATE TRIGGER trigger_dm_conversations_updated_at 
    BEFORE UPDATE ON direct_message_conversations 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_dm_messages_updated_at 
    BEFORE UPDATE ON direct_messages 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 5. Trigger to update conversation updated_at when a message is added
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE direct_message_conversations
    SET updated_at = NOW()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_conversation_on_message
    AFTER INSERT ON direct_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- 6. Enable RLS (Row Level Security)
ALTER TABLE direct_message_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

-- 7. RLS Policies for direct_message_conversations

-- Users can view their own conversations
CREATE POLICY "Users can view their own conversations" 
    ON direct_message_conversations 
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Users can create their own conversations
CREATE POLICY "Users can create their own conversations" 
    ON direct_message_conversations 
    FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

-- Organization admins can view conversations with their organization
CREATE POLICY "Organization admins can view conversations with their org" 
    ON direct_message_conversations 
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM admin_organizations 
            WHERE user_id = auth.uid() 
            AND organization_id = direct_message_conversations.organization_id
        )
    );

-- 8. RLS Policies for direct_messages

-- Users can view messages in their own conversations
CREATE POLICY "Users can view messages in their conversations" 
    ON direct_messages 
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM direct_message_conversations 
            WHERE id = direct_messages.conversation_id 
            AND user_id = auth.uid()
        )
    );

-- Organization admins can view messages in conversations with their organization
CREATE POLICY "Organization admins can view messages in their org conversations" 
    ON direct_messages 
    FOR SELECT 
    USING (
        EXISTS (
            SELECT 1 FROM direct_message_conversations dmc
            JOIN admin_organizations ao ON ao.organization_id = dmc.organization_id
            WHERE dmc.id = direct_messages.conversation_id 
            AND ao.user_id = auth.uid()
        )
    );

-- Users can send messages in their own conversations
CREATE POLICY "Users can send messages in their conversations" 
    ON direct_messages 
    FOR INSERT 
    WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM direct_message_conversations 
            WHERE id = conversation_id 
            AND user_id = auth.uid()
        )
    );

-- Organization admins can send messages in conversations with their organization
CREATE POLICY "Organization admins can send messages in their org conversations" 
    ON direct_messages 
    FOR INSERT 
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM admin_organizations ao
            JOIN direct_message_conversations dmc ON dmc.organization_id = ao.organization_id
            WHERE dmc.id = conversation_id 
            AND ao.user_id = auth.uid()
        )
    );

-- Users can update their own messages (for marking as read, etc.)
CREATE POLICY "Users can update messages in their conversations" 
    ON direct_messages 
    FOR UPDATE 
    USING (
        EXISTS (
            SELECT 1 FROM direct_message_conversations 
            WHERE id = conversation_id 
            AND user_id = auth.uid()
        )
    );

-- Organization admins can update messages in conversations with their organization
CREATE POLICY "Organization admins can update messages in their org conversations" 
    ON direct_messages 
    FOR UPDATE 
    USING (
        EXISTS (
            SELECT 1 FROM admin_organizations ao
            JOIN direct_message_conversations dmc ON dmc.organization_id = ao.organization_id
            WHERE dmc.id = conversation_id 
            AND ao.user_id = auth.uid()
        )
    );

-- 9. Function to get unread count for a conversation
CREATE OR REPLACE FUNCTION get_conversation_unread_count(p_conversation_id UUID, p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_unread_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_unread_count
    FROM direct_messages dm
    JOIN direct_message_conversations dmc ON dmc.id = dm.conversation_id
    WHERE dm.conversation_id = p_conversation_id
    AND dm.is_read = false
    AND dm.sender_id != p_user_id;
    
    RETURN COALESCE(v_unread_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. View for direct message conversations with last message and unread count
CREATE OR REPLACE VIEW direct_message_conversations_view AS
SELECT 
    dmc.id,
    dmc.user_id,
    dmc.organization_id,
    dmc.created_at,
    dmc.updated_at,
    o.name AS organization_name,
    o.logo_url AS organization_logo_url,
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
        SELECT dm2.created_at
        FROM direct_messages dm2
        WHERE dm2.conversation_id = dmc.id
        ORDER BY dm2.created_at DESC
        LIMIT 1
    ) AS last_message_created_at,
    (
        SELECT get_conversation_unread_count(dmc.id, dmc.user_id)
    ) AS unread_count
FROM direct_message_conversations dmc
JOIN organizations o ON o.id = dmc.organization_id;

