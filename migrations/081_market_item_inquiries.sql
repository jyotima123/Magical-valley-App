-- ============================================================================
-- Migration 081: Direct messages about Market items
-- ============================================================================
-- A Market item is messaged exactly like a community car: the buyer taps
-- "Message Seller", a conversation opens with the person who listed it, and it
-- lands in the same Messages tab with the same push notifications.
--
-- Rather than a parallel set of tables, the vehicle inquiry tables (073, 076)
-- now carry either kind of listing: a conversation points at a vehicle OR at a
-- market item. Everything keyed on the conversation — the messages table and
-- its RLS, realtime, the notification trigger (075), the recipients RPC, read
-- receipts — works unchanged, because none of it ever looked at the vehicle.
-- The tables keep their vehicle_ names; renaming them would break the realtime
-- subscriptions of every installed build.
--
-- Market items are always personal sales (there are no Market feeds), so an
-- item conversation always has a seller_id and never an organization_id.
--
-- ── Installed builds ─────────────────────────────────────────────────────────
-- VehicleInquiryConversation.fromJson casts vehicle_id to a non-null String.
-- An item conversation reaching a build that predates this migration would
-- fail the whole inbox parse, not just its own row. So:
--   * get_vehicle_inquiries_for_user() keeps returning vehicle conversations
--     only — current builds see exactly what they saw before;
--   * get_listing_inquiries_for_user() is the new inbox call, returning both.
--
-- Applies on top of 080.
-- ============================================================================

-- 1. A conversation is about a vehicle XOR a market item ─────────────────────

ALTER TABLE vehicle_inquiry_conversations
  ADD COLUMN IF NOT EXISTS market_item_id uuid
  REFERENCES market_items(id) ON DELETE CASCADE;

ALTER TABLE vehicle_inquiry_conversations
  ALTER COLUMN vehicle_id DROP NOT NULL;

ALTER TABLE vehicle_inquiry_conversations
  DROP CONSTRAINT IF EXISTS vic_one_listing;
ALTER TABLE vehicle_inquiry_conversations
  ADD CONSTRAINT vic_one_listing
  CHECK (num_nonnulls(vehicle_id, market_item_id) = 1);

-- No dealer side on a market item: the seller is always its author.
ALTER TABLE vehicle_inquiry_conversations
  DROP CONSTRAINT IF EXISTS vic_market_item_is_personal;
ALTER TABLE vehicle_inquiry_conversations
  ADD CONSTRAINT vic_market_item_is_personal
  CHECK (market_item_id IS NULL OR organization_id IS NULL);

-- One thread per buyer per item, as vic_one_per_buyer_vehicle does for cars.
-- Item conversations have a NULL vehicle_id, and NULLs never collide in a
-- UNIQUE constraint, so the vehicle rule does not get in the way. The index
-- behind this constraint also serves lookups by market_item_id alone.
ALTER TABLE vehicle_inquiry_conversations
  DROP CONSTRAINT IF EXISTS vic_one_per_buyer_item;
ALTER TABLE vehicle_inquiry_conversations
  ADD CONSTRAINT vic_one_per_buyer_item UNIQUE (market_item_id, buyer_id);

COMMENT ON TABLE vehicle_inquiry_conversations IS
  'Buyer-to-seller conversations about one listing: a vehicle (vehicle_id) or '
  'a Market item (market_item_id), never both. Named for its first use.';

COMMENT ON COLUMN vehicle_inquiry_conversations.market_item_id IS
  'Set for conversations about a Market item (081); vehicle_id is then NULL.';

-- 2. Conversations view ──────────────────────────────────────────────────────
-- The vehicle join becomes a LEFT JOIN so item conversations appear, and
-- listing_* columns describe either kind of listing, so the inbox can render a
-- row without caring which table it came from. The vehicle_* columns are kept
-- as they were and are NULL for item conversations.
--
-- Replaced rather than dropped: the columns up to last_message_created_at must
-- stay exactly as 076 defined them, in that order; new ones go at the end.
-- That keeps the grants and the functions typed on this view's row.

CREATE OR REPLACE VIEW vehicle_inquiry_conversations_view AS
SELECT
    vic.id,
    vic.vehicle_id,
    vic.buyer_id,
    vic.seller_id,
    vic.organization_id,
    vic.created_at,
    vic.updated_at,
    -- Vehicle summary (NULL for item conversations)
    vl.year   AS vehicle_year,
    vl.make   AS vehicle_make,
    vl.model  AS vehicle_model,
    vl.trim   AS vehicle_trim,
    vl.price  AS vehicle_price,
    vl.source AS vehicle_source,
    (SELECT img FROM (
        SELECT split_part(vl.images, ',', 1) AS img
    ) sub WHERE img != '') AS vehicle_image_url,
    -- Buyer profile
    bp.username            AS buyer_username,
    bp.full_name           AS buyer_full_name,
    bp.profile_picture_url AS buyer_profile_picture_url,
    -- Seller side: the individual, or the organization standing in for them
    COALESCE(sp.username,            o.name)     AS seller_username,
    COALESCE(sp.full_name,           o.name)     AS seller_full_name,
    COALESCE(sp.profile_picture_url, o.logo_url) AS seller_profile_picture_url,
    o.name     AS organization_name,
    o.logo_url AS organization_logo_url,
    -- Last message
    (SELECT vim.id         FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_id,
    (SELECT vim.content    FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_content,
    (SELECT vim.created_at FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_created_at,
    -- ── Added by 081 ──
    vic.market_item_id,
    CASE WHEN vic.market_item_id IS NOT NULL
         THEN 'market_item' ELSE 'vehicle'
    END AS listing_type,
    COALESCE(mi.category, 'cars_trucks') AS listing_category,
    COALESCE(
        mi.title,
        concat_ws(' ', NULLIF(vl.year, 0), vl.make, vl.model, NULLIF(vl.trim, ''))
    ) AS listing_title,
    COALESCE(mi.price, vl.price) AS listing_price,
    NULLIF(btrim(split_part(COALESCE(mi.images, vl.images), ',', 1)), '')
        AS listing_image_url,
    COALESCE(mi.is_sold, vl.is_sold, false) AS listing_is_sold
FROM vehicle_inquiry_conversations vic
LEFT JOIN vehicle_listings vl ON vl.id = vic.vehicle_id
LEFT JOIN market_items     mi ON mi.id = vic.market_item_id
JOIN      user_profiles    bp ON bp.id = vic.buyer_id
LEFT JOIN user_profiles    sp ON sp.id = vic.seller_id
LEFT JOIN organizations    o  ON o.id  = vic.organization_id;

COMMENT ON VIEW vehicle_inquiry_conversations_view IS
  'One row per inquiry conversation, about a vehicle or a Market item. '
  'listing_type says which; listing_title / listing_price / listing_image_url / '
  'listing_is_sold describe either, and vehicle_* are NULL for items. '
  'seller_* fall back to the organization for dealer conversations.';

-- CREATE OR REPLACE VIEW replaces the view's options with the ones it was
-- given — none here — so the security_invoker that 076 set is now gone.
-- Without it the view reads as its owner and bypasses RLS entirely (see 076).
-- Restore it the same tolerant way 076 did.
DO $$
BEGIN
    EXECUTE 'ALTER VIEW vehicle_inquiry_conversations_view '
            'SET (security_invoker = true)';
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Could not set security_invoker on '
                      'vehicle_inquiry_conversations_view (Postgres < 15?): %',
                      SQLERRM;
END;
$$;

-- 3. Start (or resume) a conversation about a market item ───────────────────
-- The item counterpart of create_or_get_vehicle_inquiry (076). SECURITY
-- DEFINER because buyers cannot insert conversations directly (076 dropped
-- that policy); the seller is read off the item, never taken from the client.

CREATE OR REPLACE FUNCTION create_or_get_market_item_inquiry(
    p_item_id uuid
) RETURNS uuid AS $$
DECLARE
    v_buyer_id        uuid := current_jwt_user_id();
    v_item            RECORD;
    v_conversation_id uuid;
BEGIN
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT id, created_by, is_sold INTO v_item
    FROM market_items
    WHERE id = p_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Listing not found' USING ERRCODE = 'P0002';
    END IF;

    -- created_by is NOT NULL and cascades from user_profiles, so unlike a
    -- vehicle listing an item can never outlive its seller.
    IF v_item.created_by = v_buyer_id THEN
        RAISE EXCEPTION 'You are the seller of this listing'
            USING ERRCODE = '22023';
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
        (market_item_id, buyer_id, seller_id)
    VALUES
        (p_item_id, v_buyer_id, v_item.created_by)
    ON CONFLICT ON CONSTRAINT vic_one_per_buyer_item DO UPDATE
        SET updated_at = vehicle_inquiry_conversations.updated_at
    RETURNING id INTO v_conversation_id;

    RETURN v_conversation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION create_or_get_market_item_inquiry(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION create_or_get_market_item_inquiry(uuid) TO authenticated;

-- 4. The Messages tab ────────────────────────────────────────────────────────
-- Same access rule as 076: the buyer, the seller, or any current admin of the
-- owning organization. SECURITY INVOKER, so the RLS on the tables is still the
-- real guard.

-- Installed builds call this one. Vehicle conversations only (see header).
CREATE OR REPLACE FUNCTION get_vehicle_inquiries_for_user()
RETURNS SETOF vehicle_inquiry_conversations_view AS $$
    SELECT v.*
    FROM vehicle_inquiry_conversations_view v
    WHERE v.vehicle_id IS NOT NULL
      AND (
            v.buyer_id  = auth.uid()
         OR v.seller_id = auth.uid()
         OR (
              v.organization_id IS NOT NULL AND EXISTS (
                  SELECT 1 FROM admin_organizations ao
                  WHERE ao.user_id = auth.uid()
                    AND ao.organization_id = v.organization_id
              )
            )
      )
    ORDER BY v.updated_at DESC;
$$ LANGUAGE sql STABLE;

-- Builds with the Market section call this one: vehicles and items together.
CREATE OR REPLACE FUNCTION get_listing_inquiries_for_user()
RETURNS SETOF vehicle_inquiry_conversations_view AS $$
    SELECT v.*
    FROM vehicle_inquiry_conversations_view v
    WHERE v.buyer_id  = auth.uid()
       OR v.seller_id = auth.uid()
       OR (
            v.organization_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM admin_organizations ao
                WHERE ao.user_id = auth.uid()
                  AND ao.organization_id = v.organization_id
            )
          )
    ORDER BY v.updated_at DESC;
$$ LANGUAGE sql STABLE;

REVOKE ALL     ON FUNCTION get_listing_inquiries_for_user() FROM public;
GRANT  EXECUTE ON FUNCTION get_listing_inquiries_for_user() TO authenticated;
