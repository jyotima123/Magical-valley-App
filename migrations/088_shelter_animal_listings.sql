-- ============================================================================
-- Migration 088: Shelter animals in Pets, messaged in-app
-- ============================================================================
-- The Twin Falls Animal Shelter publishes its adoptable animals through
-- PetPoint's web service (Petango). The app pulls that list live, the way it
-- pulls LiftKit's cars, and shows it at the top of the Pets category.
--
-- Adopters reach the shelter the way buyers reach a dealership: through the
-- in-app inquiry chat, answered by every admin of the shelter's organization.
-- That is migration 076 again, applied to market_items instead of
-- vehicle_listings:
--
--   1. An animal only exists in the shelter's feed, so it is materialized into
--      market_items on first contact — a "shadow row", source <> 'community',
--      with no author. It also snapshots the animal, so a conversation still
--      shows who was being asked about after they are adopted.
--   2. The conversation is owned by the ORGANIZATION that dealer_sources maps
--      the source to, which lifts 081's rule that an item conversation is
--      always personal (vic_market_item_is_personal).
--
-- dealer_sources stays the one registry of "which organization answers for
-- this inventory"; a `listing_type` column keeps the Cars tab from treating a
-- shelter as a car dealer.
--
-- ── Installed builds ─────────────────────────────────────────────────────────
-- MarketItem.fromJson casts created_by to a non-null String, and a shadow row
-- has none. A shadow row reaching an older build's Pets list would fail that
-- whole page, so shadow rows are readable only by the two sides of a
-- conversation about them (section 3). Browsing never needs them: the client
-- renders the live feed, exactly as it does for LiftKit.
--
-- Applies on top of 087.
-- ============================================================================

-- 1. Provenance on market_items ──────────────────────────────────────────────

ALTER TABLE market_items
  ADD COLUMN IF NOT EXISTS source      text NOT NULL DEFAULT 'community',
  ADD COLUMN IF NOT EXISTS external_id text;

-- A shadow row has no individual author; the organization owns it by way of
-- source -> dealer_sources. Community items keep requiring one.
ALTER TABLE market_items ALTER COLUMN created_by DROP NOT NULL;

ALTER TABLE market_items
  DROP CONSTRAINT IF EXISTS market_items_provenance,
  DROP CONSTRAINT IF EXISTS market_items_external_id_unique;

ALTER TABLE market_items
  ADD CONSTRAINT market_items_provenance CHECK (
    (source =  'community' AND created_by IS NOT NULL AND external_id IS NULL) OR
    (source <> 'community' AND created_by IS NULL     AND external_id IS NOT NULL)
  ),
  ADD CONSTRAINT market_items_external_id_unique UNIQUE (external_id);

COMMENT ON COLUMN market_items.source IS
  '''community'' = listed in-app by created_by. Anything else = shadow row '
  'mirroring one listing from that source''s feed, materialized on first '
  'contact (088). Shadow rows are excluded from browsing, which renders the '
  'live feed instead.';

COMMENT ON COLUMN market_items.external_id IS
  'The listing''s id in its source feed, e.g. ''petango:61814626''. NULL for '
  'community items.';

-- 2. Registry: which listings a source carries ──────────────────────────────

ALTER TABLE dealer_sources
  ADD COLUMN IF NOT EXISTS listing_type text NOT NULL DEFAULT 'vehicle';

ALTER TABLE dealer_sources
  DROP CONSTRAINT IF EXISTS dealer_sources_listing_type_check;
ALTER TABLE dealer_sources
  ADD CONSTRAINT dealer_sources_listing_type_check
  CHECK (listing_type IN ('vehicle', 'market_item'));

COMMENT ON COLUMN dealer_sources.listing_type IS
  'vehicle = rows land in vehicle_listings and the Cars tab fetches the source; '
  'market_item = rows land in market_items (088). The Cars tab reads vehicle '
  'sources only.';

-- The shelter. organization_id is left NULL: until an operator points it at the
-- shelter's organization, starting a conversation fails with a readable error
-- (section 5) and the animals still list. See the footer.
INSERT INTO dealer_sources
    (source, organization_id, provider, kind, display_name, listing_type, is_active)
VALUES
    ('petango', NULL, 'petango', 'api', 'Twin Falls Animal Shelter', 'market_item', true)
ON CONFLICT (source) DO UPDATE
  SET provider     = 'petango',
      kind         = 'api',
      listing_type = 'market_item',
      display_name = COALESCE(dealer_sources.display_name, EXCLUDED.display_name);

-- 3. Who can read a shadow row ───────────────────────────────────────────────
-- SECURITY DEFINER for the reason 087 gives: a market_items policy that reads
-- vehicle_inquiry_conversations would run that table's policies, which read
-- user_profiles, whose policies read the conversations back.

CREATE OR REPLACE FUNCTION can_view_sourced_market_item(p_item_id uuid)
RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1
        FROM vehicle_inquiry_conversations vic
        WHERE vic.market_item_id = p_item_id
          AND (
                vic.buyer_id = current_jwt_user_id()
             OR (
                  vic.organization_id IS NOT NULL AND EXISTS (
                      SELECT 1 FROM admin_organizations ao
                      WHERE ao.user_id = current_jwt_user_id()
                        AND ao.organization_id = vic.organization_id
                  )
                )
          )
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION can_view_sourced_market_item(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION can_view_sourced_market_item(uuid) TO authenticated;

-- Community items stay readable by everyone signed in, as in 080. The source
-- test comes first, so browsing never evaluates the function.
DROP POLICY IF EXISTS "Authenticated users can view market items"
    ON market_items;
CREATE POLICY "Authenticated users can view market items"
    ON market_items FOR SELECT
    TO authenticated
    USING (
        source = 'community'
        OR can_view_sourced_market_item(id)
    );

-- 4. An item conversation may belong to an organization ─────────────────────
-- vic_seller_or_org (076) still guarantees exactly one seller side.

ALTER TABLE vehicle_inquiry_conversations
  DROP CONSTRAINT IF EXISTS vic_market_item_is_personal;

-- 5. Start (or resume) a conversation about an existing item ────────────────
-- 081's function, now with the same community/organization split as
-- create_or_get_vehicle_inquiry (076). The seller side is still read off the
-- item, never accepted from the client.

CREATE OR REPLACE FUNCTION create_or_get_market_item_inquiry(
    p_item_id uuid
) RETURNS uuid AS $$
DECLARE
    v_buyer_id        uuid := current_jwt_user_id();
    v_item            RECORD;
    v_seller_id       uuid;
    v_organization_id uuid;
    v_conversation_id uuid;
BEGIN
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT id, source, created_by, is_sold INTO v_item
    FROM market_items
    WHERE id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Listing not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_item.source = 'community' THEN
        v_seller_id := v_item.created_by;

        IF v_seller_id = v_buyer_id THEN
            RAISE EXCEPTION 'You are the seller of this listing'
                USING ERRCODE = '22023';
        END IF;
    ELSE
        SELECT organization_id INTO v_organization_id
        FROM dealer_sources
        WHERE source = v_item.source AND is_active;

        IF v_organization_id IS NULL THEN
            RAISE EXCEPTION 'This organization is not set up to receive messages yet'
                USING ERRCODE = 'P0002';
        END IF;

        IF EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = v_buyer_id AND organization_id = v_organization_id
        ) THEN
            RAISE EXCEPTION 'You manage this listing'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    SELECT id INTO v_conversation_id
    FROM vehicle_inquiry_conversations
    WHERE market_item_id = p_item_id AND buyer_id = v_buyer_id;

    -- An existing thread outlives the sale: the buyer may still be arranging
    -- pickup. Only a NEW conversation about a sold item is refused.
    IF v_conversation_id IS NOT NULL THEN
        RETURN v_conversation_id;
    END IF;

    IF v_item.is_sold THEN
        RAISE EXCEPTION 'This item has already been sold'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO vehicle_inquiry_conversations
        (market_item_id, buyer_id, seller_id, organization_id)
    VALUES
        (p_item_id, v_buyer_id, v_seller_id, v_organization_id)
    ON CONFLICT ON CONSTRAINT vic_one_per_buyer_item DO UPDATE
        SET updated_at = vehicle_inquiry_conversations.updated_at
    RETURNING id INTO v_conversation_id;

    RETURN v_conversation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION create_or_get_market_item_inquiry(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION create_or_get_market_item_inquiry(uuid) TO authenticated;

-- 6. Start (or resume) a conversation about a feed item ─────────────────────
-- The item counterpart of create_or_get_dealer_vehicle_inquiry (076): the
-- listing may not exist as a row yet, so it is materialized here and then
-- handed to the shared path above.
--
-- p_item carries title, description, price, location, images (comma-separated)
-- and category. As in 076 the snapshot comes from the client, which is the one
-- holding the live feed; the organization never does.

CREATE OR REPLACE FUNCTION create_or_get_sourced_item_inquiry(
    p_source      text,
    p_external_id text,
    p_item        jsonb
) RETURNS uuid AS $$
DECLARE
    v_buyer_id uuid := current_jwt_user_id();
    v_category text;
    v_item_id  uuid;
    v_source   text;
BEGIN
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    IF p_source IS NULL OR p_source = 'community' THEN
        RAISE EXCEPTION 'create_or_get_sourced_item_inquiry is for feed listings only'
            USING ERRCODE = '22023';
    END IF;

    IF p_external_id IS NULL OR btrim(p_external_id) = '' THEN
        RAISE EXCEPTION 'Missing listing identifier' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM dealer_sources
        WHERE source = p_source AND is_active AND listing_type = 'market_item'
    ) THEN
        RAISE EXCEPTION 'These listings are no longer available'
            USING ERRCODE = 'P0002';
    END IF;

    -- A category the client names must exist and must not be Cars; anything
    -- else lands in General rather than failing the adopter's first message.
    SELECT slug INTO v_category
    FROM market_categories
    WHERE slug = p_item->>'category' AND slug <> 'cars_trucks';
    v_category := COALESCE(v_category, 'general');

    -- Refresh the snapshot on every contact so the conversation keeps showing
    -- current photos while the animal is still listed.
    INSERT INTO market_items (
        source, external_id, category, title, description, price, location,
        images, created_by
    ) VALUES (
        p_source,
        p_external_id,
        v_category,
        COALESCE(NULLIF(btrim(COALESCE(p_item->>'title', '')), ''), 'Listing'),
        NULLIF(btrim(COALESCE(p_item->>'description', '')), ''),
        GREATEST(COALESCE((p_item->>'price')::numeric, 0), 0),
        NULLIF(btrim(COALESCE(p_item->>'location', '')), ''),
        NULLIF(btrim(COALESCE(p_item->>'images', '')), ''),
        NULL
    )
    ON CONFLICT ON CONSTRAINT market_items_external_id_unique DO UPDATE SET
        title       = EXCLUDED.title,
        description = EXCLUDED.description,
        price       = EXCLUDED.price,
        location    = EXCLUDED.location,
        images      = EXCLUDED.images,
        updated_at  = now()
    RETURNING id, source INTO v_item_id, v_source;

    -- external_id is unique across sources, so a conflict could land on
    -- another source's row; refuse rather than reroute its conversation.
    IF v_source <> p_source THEN
        RAISE EXCEPTION 'Listing identifier belongs to another source'
            USING ERRCODE = '22023';
    END IF;

    RETURN create_or_get_market_item_inquiry(v_item_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION create_or_get_sourced_item_inquiry(text, text, jsonb) FROM public;
GRANT  EXECUTE ON FUNCTION create_or_get_sourced_item_inquiry(text, text, jsonb) TO authenticated;

-- ============================================================================
-- Operator step — route the shelter's messages to its organization:
--   UPDATE dealer_sources
--   SET organization_id = '<shelter organization uuid>'
--   WHERE source = 'petango';
--
-- Off switch (the Pets carousel disappears for current builds):
--   UPDATE dealer_sources SET is_active = false WHERE source = 'petango';
--
-- Verification
--   SELECT source, listing_type, kind, organization_id, is_active
--   FROM dealer_sources ORDER BY listing_type, source;
--   SELECT source, count(*) FROM market_items GROUP BY source;
--                                       -- 'community' only until first contact
-- ============================================================================
