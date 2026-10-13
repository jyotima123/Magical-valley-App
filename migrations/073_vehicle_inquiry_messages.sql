-- ============================================================================
-- VEHICLE INQUIRY MESSAGES
-- User-to-user direct messaging scoped to a vehicle listing.
-- These conversations appear alongside org DMs in the chat list but live in
-- their own tables so the existing org DM system stays untouched.
-- ============================================================================

-- 1. Conversations ─────────────────────────────────────────────────────────────

CREATE TABLE vehicle_inquiry_conversations (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id      uuid        NOT NULL REFERENCES vehicle_listings(id) ON DELETE CASCADE,
    buyer_id        uuid        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    seller_id       uuid        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT vic_one_per_buyer_vehicle UNIQUE (vehicle_id, buyer_id)
);

CREATE INDEX idx_vic_buyer   ON vehicle_inquiry_conversations(buyer_id);
CREATE INDEX idx_vic_seller  ON vehicle_inquiry_conversations(seller_id);
CREATE INDEX idx_vic_vehicle ON vehicle_inquiry_conversations(vehicle_id);
CREATE INDEX idx_vic_updated ON vehicle_inquiry_conversations(updated_at DESC);

-- 2. Messages ──────────────────────────────────────────────────────────────────

CREATE TABLE vehicle_inquiry_messages (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid        NOT NULL REFERENCES vehicle_inquiry_conversations(id) ON DELETE CASCADE,
    sender_id       uuid        NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    content         text        NOT NULL,
    message_type    varchar(20) NOT NULL DEFAULT 'text'
                    CHECK (message_type IN ('text', 'image', 'pdf')),
    file_url        text,
    is_read         boolean     NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT vim_file_required_for_media CHECK (
        message_type = 'text' OR file_url IS NOT NULL
    )
);

CREATE INDEX idx_vim_conversation ON vehicle_inquiry_messages(conversation_id);
CREATE INDEX idx_vim_sender       ON vehicle_inquiry_messages(sender_id);
CREATE INDEX idx_vim_created      ON vehicle_inquiry_messages(created_at DESC);
CREATE INDEX idx_vim_unread       ON vehicle_inquiry_messages(is_read) WHERE is_read = false;

-- 3. Triggers ──────────────────────────────────────────────────────────────────

CREATE TRIGGER vic_updated_at
    BEFORE UPDATE ON vehicle_inquiry_conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER vim_updated_at
    BEFORE UPDATE ON vehicle_inquiry_messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION _update_vic_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE vehicle_inquiry_conversations
    SET updated_at = now()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vim_touch_conversation
    AFTER INSERT ON vehicle_inquiry_messages
    FOR EACH ROW EXECUTE FUNCTION _update_vic_on_message();

-- 4. Row-Level Security ────────────────────────────────────────────────────────

ALTER TABLE vehicle_inquiry_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_inquiry_messages      ENABLE ROW LEVEL SECURITY;

-- Conversations: both buyer and seller can view
CREATE POLICY "Participants can view vehicle inquiry conversations"
    ON vehicle_inquiry_conversations FOR SELECT
    USING (auth.uid() IN (buyer_id, seller_id));

-- Conversations: buyer creates (seller is derived from the listing)
CREATE POLICY "Buyers can create vehicle inquiry conversations"
    ON vehicle_inquiry_conversations FOR INSERT
    WITH CHECK (auth.uid() = buyer_id);

-- Messages: participants can read
CREATE POLICY "Participants can view vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations
            WHERE id = vehicle_inquiry_messages.conversation_id
            AND auth.uid() IN (buyer_id, seller_id)
        )
    );

-- Messages: participants can send (must be sender)
CREATE POLICY "Participants can send vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations
            WHERE id = conversation_id
            AND auth.uid() IN (buyer_id, seller_id)
        )
    );

-- Messages: participants can update (mark as read)
CREATE POLICY "Participants can update vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations
            WHERE id = conversation_id
            AND auth.uid() IN (buyer_id, seller_id)
        )
    );

-- Superadmins: full access
CREATE POLICY "Superadmins full access to vehicle inquiry conversations"
    ON vehicle_inquiry_conversations FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );

CREATE POLICY "Superadmins full access to vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );

-- 5. Unread count helper ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION get_vehicle_inquiry_unread_count(
    p_conversation_id uuid,
    p_user_id uuid
) RETURNS integer AS $$
    SELECT count(*)::integer
    FROM vehicle_inquiry_messages
    WHERE conversation_id = p_conversation_id
      AND is_read = false
      AND sender_id != p_user_id;
$$ LANGUAGE sql SECURITY DEFINER;

-- 6. Conversations view (used by Flutter to build the mixed DM list) ──────────

CREATE OR REPLACE VIEW vehicle_inquiry_conversations_view AS
SELECT
    vic.id,
    vic.vehicle_id,
    vic.buyer_id,
    vic.seller_id,
    vic.created_at,
    vic.updated_at,
    -- Vehicle summary
    vl.year   AS vehicle_year,
    vl.make   AS vehicle_make,
    vl.model  AS vehicle_model,
    vl.trim   AS vehicle_trim,
    vl.price  AS vehicle_price,
    (SELECT img FROM (
        SELECT split_part(vl.images, ',', 1) AS img
    ) sub WHERE img != '') AS vehicle_image_url,
    -- Buyer profile
    bp.username           AS buyer_username,
    bp.full_name          AS buyer_full_name,
    bp.profile_picture_url AS buyer_profile_picture_url,
    -- Seller profile
    sp.username           AS seller_username,
    sp.full_name          AS seller_full_name,
    sp.profile_picture_url AS seller_profile_picture_url,
    -- Last message
    (SELECT vim.id      FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_id,
    (SELECT vim.content FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_content,
    (SELECT vim.created_at FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_created_at
FROM vehicle_inquiry_conversations vic
JOIN vehicle_listings vl ON vl.id = vic.vehicle_id
JOIN user_profiles bp    ON bp.id = vic.buyer_id
JOIN user_profiles sp    ON sp.id = vic.seller_id;

-- 7. Enable realtime ──────────────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_inquiry_conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE vehicle_inquiry_messages;
