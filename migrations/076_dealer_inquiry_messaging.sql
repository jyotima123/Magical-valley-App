-- ============================================================================
-- Migration 076: In-app messaging for dealer-feed vehicles
-- ============================================================================
-- Buyers talk to dealers inside the app, never on the dealership's own site:
-- listing here is meant to replace the dealer's website, so a dealer listing
-- gets the same "Message Seller" conversation a community listing gets.
--
-- Two things stood in the way:
--   1. vehicle_inquiry_conversations.vehicle_id is a FK into vehicle_listings,
--      but feed vehicles live only in the provider's API (their ids look like
--      'liftkit:12345' and are not uuids).
--   2. seller_id must be a real user_profiles row, and a feed carries no
--      per-vehicle seller identity.
--
-- Fixes, in order:
--   1. A feed vehicle is materialized into vehicle_listings on first contact
--      (a "shadow row", source <> 'community'). Everything downstream — the
--      conversations view, the notification trigger, the Messages tab — then
--      works unchanged. It also snapshots the vehicle, so a conversation still
--      shows what was being discussed after the car leaves the feed.
--   2. A dealer conversation is owned by an ORGANIZATION, not by a person.
--
-- ── Why (2) matters ──────────────────────────────────────────────────────────
-- Migration 073 made both sides of an inquiry a user_profiles row. For a
-- private seller that is right; for a dealership it is not. Pointing a whole
-- feed at one staffer's account meant:
--   * a second admin of the dealership could not see the inbox at all
--     (RLS was `auth.uid() IN (buyer_id, seller_id)`);
--   * deleting that staffer's account DELETED the buyers' message history
--     (seller_id was NOT NULL ... ON DELETE CASCADE, and the messages cascade
--     off the conversation);
--   * removing them from the organization revoked nothing — they kept reading
--     dealer mail indefinitely.
--
-- So the seller side is now organization XOR person:
--
--   source = 'community'   ->  seller_id       = vehicle_listings.created_by
--                              a personal sale; one human answers.
--   source <> 'community'  ->  organization_id = dealer_sources.organization_id
--                              every current admin of that org answers, and
--                              access follows admin_organizations, so staff
--                              changes take effect immediately.
--
-- Listings created through our app are ALWAYS personal, whoever creates them.
-- Organization-owned listings only ever arrive from a feed, so a listing needs
-- no organization_id of its own: `source` already determines which branch
-- applies, and dealer_sources maps it to the org.
--
-- Applies on top of 075. Tables from 073 are altered in place.
-- ============================================================================

-- 1. Feed provenance on vehicle_listings ─────────────────────────────────────

ALTER TABLE vehicle_listings
  ADD COLUMN IF NOT EXISTS source      text NOT NULL DEFAULT 'community',
  ADD COLUMN IF NOT EXISTS external_id text;

ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_source_check;
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_source_check
  CHECK (source IN ('community', 'liftkit'));

-- Shadow rows must carry the provider's id; community rows must not.
ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_external_id_presence;
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_external_id_presence CHECK (
    (source =  'community' AND external_id IS NULL) OR
    (source <> 'community' AND external_id IS NOT NULL)
  );

ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_external_id_unique;
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_external_id_unique UNIQUE (external_id);

-- Stock numbers and VINs are only unique within a source: our community stock
-- counter (1001+) and a dealership's own stock numbers share a namespace, and
-- the same VIN can legitimately appear in two different feeds.
ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_stock_unique;
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_stock_unique UNIQUE (source, stock);

ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_vin_key;
ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_vin_unique;
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_vin_unique UNIQUE (source, vin);

CREATE INDEX IF NOT EXISTS idx_vehicle_listings_source
  ON vehicle_listings(source);

COMMENT ON COLUMN vehicle_listings.source IS
  'community = listed in-app by a user (always a personal listing, whatever '
  'their role); anything else = shadow row mirroring one vehicle from that '
  'feed, created on first buyer contact and owned by the organization that '
  'dealer_sources maps the feed to. Shadow rows are excluded from the Cars '
  'list, which renders the live feed instead.';

-- 2. Which organization answers for each feed ────────────────────────────────

CREATE TABLE IF NOT EXISTS dealer_sources (
    source          text        PRIMARY KEY,
    organization_id uuid        NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
    is_active       boolean     NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Defensive: an earlier draft of this migration keyed the feed to a person.
-- Nothing should have run it, but converting is cheaper than a failed deploy.
ALTER TABLE dealer_sources
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT;
ALTER TABLE dealer_sources DROP COLUMN IF EXISTS seller_id;
ALTER TABLE dealer_sources DROP COLUMN IF EXISTS display_name;

COMMENT ON TABLE dealer_sources IS
  'Maps a vehicle feed to the organization that answers buyer messages about '
  'it. A feed mirrors exactly one dealership, so one organization covers every '
  'vehicle from it. Every admin in admin_organizations for that org shares the '
  'inbox, so staff can come and go without conversations being lost or left '
  'readable by a former employee.';

COMMENT ON COLUMN dealer_sources.organization_id IS
  'ON DELETE RESTRICT: an org with a live feed cannot be deleted out from '
  'under its conversations.';

ALTER TABLE dealer_sources ENABLE ROW LEVEL SECURITY;

-- Readable by everyone signed in: the app checks "is this feed mine?" to
-- decide which button to show. The mapping is not a secret.
DROP POLICY IF EXISTS "Authenticated users can view dealer sources" ON dealer_sources;
CREATE POLICY "Authenticated users can view dealer sources"
    ON dealer_sources FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Superadmins manage dealer sources" ON dealer_sources;
CREATE POLICY "Superadmins manage dealer sources"
    ON dealer_sources FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );

DROP TRIGGER IF EXISTS dealer_sources_updated_at ON dealer_sources;
CREATE TRIGGER dealer_sources_updated_at
    BEFORE UPDATE ON dealer_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. A conversation's seller side: organization XOR person ───────────────────

ALTER TABLE vehicle_inquiry_conversations
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE;

ALTER TABLE vehicle_inquiry_conversations
  ALTER COLUMN seller_id DROP NOT NULL;

ALTER TABLE vehicle_inquiry_conversations
  DROP CONSTRAINT IF EXISTS vic_seller_or_org;
ALTER TABLE vehicle_inquiry_conversations
  ADD CONSTRAINT vic_seller_or_org CHECK (
    (seller_id IS NOT NULL AND organization_id IS NULL) OR
    (seller_id IS NULL     AND organization_id IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_vic_organization
  ON vehicle_inquiry_conversations(organization_id);

COMMENT ON COLUMN vehicle_inquiry_conversations.seller_id IS
  'Set only for community listings — the individual who listed the car. '
  'NULL for dealer conversations; see organization_id.';
COMMENT ON COLUMN vehicle_inquiry_conversations.organization_id IS
  'Set only for dealer-feed listings. Denormalized from dealer_sources at '
  'creation rather than derived per query: RLS reads it on every row, and it '
  'keeps the conversation intact after the vehicle leaves the feed.';

-- 4. Row-Level Security ──────────────────────────────────────────────────────
-- The seller side is now "the seller, or any current admin of the owning org".

DROP POLICY IF EXISTS "Participants can view vehicle inquiry conversations"
    ON vehicle_inquiry_conversations;
CREATE POLICY "Participants can view vehicle inquiry conversations"
    ON vehicle_inquiry_conversations FOR SELECT
    USING (
        auth.uid() = buyer_id
        OR auth.uid() = seller_id
        OR (
            organization_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM admin_organizations ao
                WHERE ao.user_id = auth.uid()
                  AND ao.organization_id = vehicle_inquiry_conversations.organization_id
            )
        )
    );

-- Conversations are created only through the RPCs below, which resolve the
-- seller server-side. Without this, a client could open a conversation naming
-- any arbitrary user as the seller.
DROP POLICY IF EXISTS "Buyers can create vehicle inquiry conversations"
    ON vehicle_inquiry_conversations;

DROP POLICY IF EXISTS "Participants can view vehicle inquiry messages"
    ON vehicle_inquiry_messages;
CREATE POLICY "Participants can view vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations vic
            WHERE vic.id = vehicle_inquiry_messages.conversation_id
              AND (
                auth.uid() = vic.buyer_id
                OR auth.uid() = vic.seller_id
                OR (
                    vic.organization_id IS NOT NULL AND EXISTS (
                        SELECT 1 FROM admin_organizations ao
                        WHERE ao.user_id = auth.uid()
                          AND ao.organization_id = vic.organization_id
                    )
                )
              )
        )
    );

DROP POLICY IF EXISTS "Participants can send vehicle inquiry messages"
    ON vehicle_inquiry_messages;
CREATE POLICY "Participants can send vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id AND
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations vic
            WHERE vic.id = conversation_id
              AND (
                auth.uid() = vic.buyer_id
                OR auth.uid() = vic.seller_id
                OR (
                    vic.organization_id IS NOT NULL AND EXISTS (
                        SELECT 1 FROM admin_organizations ao
                        WHERE ao.user_id = auth.uid()
                          AND ao.organization_id = vic.organization_id
                    )
                )
              )
        )
    );

DROP POLICY IF EXISTS "Participants can update vehicle inquiry messages"
    ON vehicle_inquiry_messages;
CREATE POLICY "Participants can update vehicle inquiry messages"
    ON vehicle_inquiry_messages FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM vehicle_inquiry_conversations vic
            WHERE vic.id = conversation_id
              AND (
                auth.uid() = vic.buyer_id
                OR auth.uid() = vic.seller_id
                OR (
                    vic.organization_id IS NOT NULL AND EXISTS (
                        SELECT 1 FROM admin_organizations ao
                        WHERE ao.user_id = auth.uid()
                          AND ao.organization_id = vic.organization_id
                    )
                )
              )
        )
    );

-- 5. Conversations view ──────────────────────────────────────────────────────
-- The seller display columns fall back to the organization, so the client
-- renders a dealer conversation exactly like a private-seller one.
-- Dropped rather than replaced: seller_* become nullable and columns are added.

DROP VIEW IF EXISTS vehicle_inquiry_conversations_view;
CREATE VIEW vehicle_inquiry_conversations_view AS
SELECT
    vic.id,
    vic.vehicle_id,
    vic.buyer_id,
    vic.seller_id,
    vic.organization_id,
    vic.created_at,
    vic.updated_at,
    -- Vehicle summary
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
    (SELECT vim.created_at FROM vehicle_inquiry_messages vim WHERE vim.conversation_id = vic.id ORDER BY vim.created_at DESC LIMIT 1) AS last_message_created_at
FROM vehicle_inquiry_conversations vic
JOIN      vehicle_listings vl ON vl.id = vic.vehicle_id
JOIN      user_profiles    bp ON bp.id = vic.buyer_id
LEFT JOIN user_profiles    sp ON sp.id = vic.seller_id
LEFT JOIN organizations    o  ON o.id  = vic.organization_id;

COMMENT ON VIEW vehicle_inquiry_conversations_view IS
  'seller_username / seller_full_name / seller_profile_picture_url fall back '
  'to the organization for dealer conversations, so the client needs no branch '
  'to render a counterparty. organization_id is non-null exactly when the '
  'conversation belongs to a dealership.';

-- A view executes with its OWNER's rights unless told otherwise, and this one
-- is owned by postgres — so without security_invoker the RLS above simply does
-- not apply to anything read through it, and any signed-in client could select
-- the whole table's worth of conversations. Postgres 15+ only; on 14 the view
-- keeps definer semantics and get_vehicle_inquiries_for_user is the guard, so
-- warn rather than fail the migration.
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

-- DROP VIEW discarded the grants PostgREST needs to expose it.
GRANT SELECT ON vehicle_inquiry_conversations_view TO authenticated, service_role;

-- 6. Identifying the caller inside SECURITY DEFINER ──────────────────────────
-- auth.uid() is not dependable once the execution role switches to the
-- function owner: the wrapper may not see request.jwt.claims. Migration 069
-- hit exactly this on promote_user_to_admin and worked around it by reading
-- the sub claim off the session variable. Same trick, factored out, because
-- both RPCs below need it. Invoker-context callers (RLS policies, the view,
-- get_vehicle_inquiries_for_user) can keep using auth.uid() safely.

CREATE OR REPLACE FUNCTION current_jwt_user_id()
RETURNS uuid AS $$
DECLARE
    v_uid uuid;
BEGIN
    BEGIN
        v_uid := (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_uid := NULL;
    END;
    RETURN v_uid;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION current_jwt_user_id() IS
  'The signed-in user, read straight from the PostgREST JWT claims. Use inside '
  'SECURITY DEFINER functions, where auth.uid() can return NULL — see '
  'migration 069.';

-- 7. Start (or resume) a conversation about an existing listing ──────────────
-- One entry point for any row that is already in vehicle_listings, community
-- or shadow. SECURITY DEFINER so the seller side is resolved from the listing
-- and never accepted from the client.

CREATE OR REPLACE FUNCTION create_or_get_vehicle_inquiry(
    p_vehicle_id uuid
) RETURNS uuid AS $$
DECLARE
    v_buyer_id        uuid := current_jwt_user_id();
    v_listing         RECORD;
    v_seller_id       uuid;
    v_organization_id uuid;
    v_conversation_id uuid;
BEGIN
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT id, source, created_by INTO v_listing
    FROM vehicle_listings
    WHERE id = p_vehicle_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Listing not found' USING ERRCODE = 'P0002';
    END IF;

    IF v_listing.source = 'community' THEN
        -- A personal listing: the person who posted it answers.
        v_seller_id := v_listing.created_by;

        -- created_by is ON DELETE SET NULL, so a listing can outlive its
        -- author. Fail cleanly instead of tripping vic_seller_or_org.
        IF v_seller_id IS NULL
           OR NOT EXISTS (SELECT 1 FROM user_profiles WHERE id = v_seller_id) THEN
            RAISE EXCEPTION 'The seller of this listing no longer has an account'
                USING ERRCODE = 'P0002';
        END IF;

        IF v_seller_id = v_buyer_id THEN
            RAISE EXCEPTION 'You are the seller of this listing'
                USING ERRCODE = '22023';
        END IF;
    ELSE
        -- A dealer listing: the organization behind the feed answers.
        SELECT organization_id INTO v_organization_id
        FROM dealer_sources
        WHERE source = v_listing.source AND is_active;

        IF v_organization_id IS NULL THEN
            RAISE EXCEPTION 'No dealership is configured for this inventory yet'
                USING ERRCODE = 'P0002';
        END IF;

        IF EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = v_buyer_id AND organization_id = v_organization_id
        ) THEN
            RAISE EXCEPTION 'You are a dealer for this listing'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    SELECT id INTO v_conversation_id
    FROM vehicle_inquiry_conversations
    WHERE vehicle_id = p_vehicle_id AND buyer_id = v_buyer_id;

    IF v_conversation_id IS NULL THEN
        INSERT INTO vehicle_inquiry_conversations
            (vehicle_id, buyer_id, seller_id, organization_id)
        VALUES
            (p_vehicle_id, v_buyer_id, v_seller_id, v_organization_id)
        ON CONFLICT ON CONSTRAINT vic_one_per_buyer_vehicle DO UPDATE
            SET updated_at = vehicle_inquiry_conversations.updated_at
        RETURNING id INTO v_conversation_id;
    END IF;

    RETURN v_conversation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION create_or_get_vehicle_inquiry(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION create_or_get_vehicle_inquiry(uuid) TO authenticated;

-- 8. Start (or resume) a conversation about a feed vehicle ───────────────────
-- Separate entry point because the vehicle may not exist as a row yet: it is
-- materialized here, then handed to the same conversation logic.

CREATE OR REPLACE FUNCTION create_or_get_dealer_vehicle_inquiry(
    p_source      text,
    p_external_id text,
    p_vehicle     jsonb
) RETURNS uuid AS $$
DECLARE
    v_buyer_id        uuid := current_jwt_user_id();
    v_organization_id uuid;
    v_vehicle_id      uuid;
    v_status          text;
BEGIN
    IF v_buyer_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    IF p_source IS NULL OR p_source = 'community' THEN
        RAISE EXCEPTION 'create_or_get_dealer_vehicle_inquiry is for dealer feeds only'
            USING ERRCODE = '22023';
    END IF;

    IF p_external_id IS NULL OR btrim(p_external_id) = '' THEN
        RAISE EXCEPTION 'Missing vehicle identifier' USING ERRCODE = '22023';
    END IF;

    SELECT organization_id INTO v_organization_id
    FROM dealer_sources
    WHERE source = p_source AND is_active;

    IF v_organization_id IS NULL THEN
        RAISE EXCEPTION 'No dealership is configured for this inventory yet'
            USING ERRCODE = 'P0002';
    END IF;

    -- Clamp to the values vehicle_listings_status_check accepts; a feed can
    -- word its condition however it likes and must not break the insert.
    v_status := COALESCE(p_vehicle->>'status', 'Pre-Owned');
    IF v_status NOT IN ('New', 'Pre-Owned', 'Certified Pre-Owned') THEN
        v_status := 'Pre-Owned';
    END IF;

    -- Refresh the snapshot on every contact so an existing conversation keeps
    -- showing current price/photos while the vehicle is still in the feed.
    -- created_by stays NULL: a shadow row has no individual author, and the
    -- organization owns it by way of source -> dealer_sources.
    INSERT INTO vehicle_listings (
        source, external_id, stock, vin, year, make, model, trim, body,
        status, mileage, color, interior, transmission, speed, engine_type,
        fuel, doors, price, promotion, description, location, images, videos,
        engine_options, package_options, transmission_options,
        addons_description, created_by
    ) VALUES (
        p_source,
        p_external_id,
        COALESCE(NULLIF(btrim(COALESCE(p_vehicle->>'stock', '')), ''), p_external_id),
        NULLIF(btrim(COALESCE(p_vehicle->>'vin', '')), ''),
        COALESCE((p_vehicle->>'year')::integer, 0),
        COALESCE(NULLIF(btrim(COALESCE(p_vehicle->>'make', '')), ''), 'Unknown'),
        COALESCE(NULLIF(btrim(COALESCE(p_vehicle->>'model', '')), ''), 'Unknown'),
        p_vehicle->>'trim',
        p_vehicle->>'body',
        v_status,
        COALESCE((p_vehicle->>'mileage')::integer, 0),
        p_vehicle->>'color',
        p_vehicle->>'interior',
        p_vehicle->>'transmission',
        p_vehicle->>'speed',
        p_vehicle->>'engine_type',
        p_vehicle->>'fuel',
        p_vehicle->>'doors',
        COALESCE((p_vehicle->>'price')::numeric, 0),
        (p_vehicle->>'promotion')::numeric,
        p_vehicle->>'description',
        p_vehicle->>'location',
        p_vehicle->>'images',
        p_vehicle->>'videos',
        p_vehicle->>'engine_options',
        p_vehicle->>'package_options',
        p_vehicle->>'transmission_options',
        p_vehicle->>'addons_description',
        NULL
    )
    ON CONFLICT ON CONSTRAINT vehicle_listings_external_id_unique DO UPDATE SET
        price       = EXCLUDED.price,
        promotion   = EXCLUDED.promotion,
        mileage     = EXCLUDED.mileage,
        status      = EXCLUDED.status,
        images      = EXCLUDED.images,
        description = EXCLUDED.description,
        updated_at  = now()
    RETURNING id INTO v_vehicle_id;

    -- The row exists now, so the shared path can take it from here.
    RETURN create_or_get_vehicle_inquiry(v_vehicle_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION create_or_get_dealer_vehicle_inquiry(text, text, jsonb) FROM public;
GRANT  EXECUTE ON FUNCTION create_or_get_dealer_vehicle_inquiry(text, text, jsonb) TO authenticated;

-- 9. The Messages tab ────────────────────────────────────────────────────────
-- A dealer conversation has no seller_id, so the client can no longer find its
-- own threads with `buyer_id.eq.X or seller_id.eq.X` — an admin's inbox would
-- come back empty. SECURITY INVOKER: the RLS above is still the real guard,
-- this just spares the client from knowing which orgs it administers.

CREATE OR REPLACE FUNCTION get_vehicle_inquiries_for_user()
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

REVOKE ALL     ON FUNCTION get_vehicle_inquiries_for_user() FROM public;
GRANT  EXECUTE ON FUNCTION get_vehicle_inquiries_for_user() TO authenticated;

-- 10. Who to notify about a new message ───────────────────────────────────────
-- One buyer on one side; on the other, either one seller or every admin of the
-- organization. The edge function calls this instead of picking "the other
-- participant", which no longer identifies a single person.

CREATE OR REPLACE FUNCTION get_vehicle_inquiry_recipients(
    p_conversation_id uuid,
    p_sender_id       uuid
) RETURNS TABLE (user_id uuid) AS $$
    SELECT vic.buyer_id
    FROM vehicle_inquiry_conversations vic
    WHERE vic.id = p_conversation_id
      AND vic.buyer_id <> p_sender_id

    UNION

    SELECT vic.seller_id
    FROM vehicle_inquiry_conversations vic
    WHERE vic.id = p_conversation_id
      AND vic.seller_id IS NOT NULL
      AND vic.seller_id <> p_sender_id

    UNION

    -- Everyone currently administering the dealership, minus whoever replied.
    SELECT ao.user_id
    FROM vehicle_inquiry_conversations vic
    JOIN admin_organizations ao ON ao.organization_id = vic.organization_id
    WHERE vic.id = p_conversation_id
      AND vic.organization_id IS NOT NULL
      AND ao.user_id <> p_sender_id;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

REVOKE ALL     ON FUNCTION get_vehicle_inquiry_recipients(uuid, uuid) FROM public;
GRANT  EXECUTE ON FUNCTION get_vehicle_inquiry_recipients(uuid, uuid) TO service_role;

-- 11. Wiring a feed up ───────────────────────────────────────────────────────
-- Run once per environment. The organization must already exist, and needs at
-- least one admin in admin_organizations or nobody can answer its messages.
--
--   INSERT INTO dealer_sources (source, organization_id)
--   VALUES ('liftkit', '<organizations.id>')
--   ON CONFLICT (source) DO UPDATE
--     SET organization_id = EXCLUDED.organization_id;
--
-- The conversation header and the Messages tab show organizations.name, so no
-- separate display name is needed. Add or remove staff with
-- promote_user_to_admin / remove_admin_from_organization (migration 068);
-- inbox access follows immediately, in both directions.
