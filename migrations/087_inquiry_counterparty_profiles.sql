-- ============================================================================
-- Migration 087: A seller can see who is messaging them
-- ============================================================================
-- Symptom: a buyer messages a Market item (or a personally listed car), the
-- thread works on the buyer's side, and the seller's inbox stays empty — no
-- row in the Messages tab, "No inquiries yet" on the listing's own Messages
-- screen. The message rows exist the whole time.
--
-- Cause: vehicle_inquiry_conversations_view resolves the counterparty's name
-- and avatar with
--
--     JOIN user_profiles bp ON bp.id = vic.buyer_id   -- INNER
--
-- and 076 set security_invoker = true on the view (rightly: it is what makes
-- the RLS on the conversation table the real guard). Under invoker semantics
-- user_profiles' own RLS applies to whoever is querying, and as migration 053
-- already wrote down, that RLS only allows:
--
--   1. a user to view their own profile,
--   2. superadmins to view everything,
--   3. admins to view role = 'regular' profiles      (062),
--   4. org admins to view their followers' profiles  (053).
--
-- Nothing lets one ordinary user read another's. So the inner join finds no
-- buyer row for the seller and drops the whole conversation:
--
--   * the buyer always sees the thread — bp is their own profile;
--   * the seller sees it only if they happen to be an admin over a 'regular'
--     buyer, which is why this looks intermittent between test accounts and
--     why dealer inboxes (admins, policy 062) were never affected.
--
-- Two fixes, because each is worth having alone:
--   1. the two parties of a conversation may read each other's profile — the
--      names and avatars the chat UI has always meant to show;
--   2. the join becomes LEFT, so no future profile-visibility gap can ever
--      silently swallow a conversation again. A missing profile now costs a
--      name ('Buyer' in the UI), not the thread.
--
-- Applies on top of 081. Re-running it is a no-op.
-- ============================================================================

-- 1. The two sides of a conversation can see each other ──────────────────────
-- SECURITY DEFINER, like is_admin_of_follower_org (053) and
-- is_admin_or_superadmin (062), and for the same reason: a policy on
-- user_profiles that reads vehicle_inquiry_conversations would re-enter that
-- table's own policies, which read user_profiles back (the superadmin check in
-- 073) — straight into infinite recursion. Inside a definer function RLS is
-- off, so the cycle never forms.
--
-- Scope is deliberately narrow: it answers "are these two people in a
-- conversation with each other", so a profile is exposed only to someone its
-- owner is already talking to about a listing.

CREATE OR REPLACE FUNCTION shares_listing_inquiry(
    p_viewer uuid,
    p_other  uuid
) RETURNS boolean AS $$
    SELECT EXISTS (
        SELECT 1
        FROM vehicle_inquiry_conversations vic
        WHERE
            -- Personal listing, either direction.
            (vic.buyer_id = p_viewer AND vic.seller_id = p_other)
         OR (vic.seller_id = p_viewer AND vic.buyer_id = p_other)
            -- Dealer listing: the buyer has no one person to talk to, so every
            -- current admin of the dealership answers — and needs the name.
            -- One way only: being messaged by a dealership does not expose its
            -- staff's personal profiles to the buyer, who sees the
            -- organization instead (076 falls the seller_* columns back to it).
         OR (
              vic.buyer_id = p_other
              AND vic.organization_id IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM admin_organizations ao
                  WHERE ao.user_id = p_viewer
                    AND ao.organization_id = vic.organization_id
              )
            )
    );
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION shares_listing_inquiry(uuid, uuid) IS
  'True when p_viewer and p_other are the two sides of a listing inquiry '
  '(073/076/081), or p_viewer administers the dealership answering p_other. '
  'Backs the user_profiles policy below; SECURITY DEFINER to avoid RLS '
  'recursion, as in 053 and 062.';

REVOKE ALL     ON FUNCTION shares_listing_inquiry(uuid, uuid) FROM public;
GRANT  EXECUTE ON FUNCTION shares_listing_inquiry(uuid, uuid) TO authenticated;

-- Policies are permissive and OR together, so this only ever adds rows a user
-- can read; nothing existing becomes narrower.
DROP POLICY IF EXISTS "Inquiry participants can view each other profile"
    ON user_profiles;
CREATE POLICY "Inquiry participants can view each other profile"
    ON user_profiles FOR SELECT
    TO authenticated
    USING (shares_listing_inquiry(auth.uid(), id));

-- 2. A conversation no longer depends on seeing a profile ────────────────────
-- Identical to 081's view except that both profiles join LEFT and unread_count
-- is appended. Replaced rather than dropped: the columns through
-- last_message_created_at must stay exactly as 076 defined them, in that
-- order, and get_vehicle_inquiries_for_user / get_listing_inquiries_for_user
-- are typed on this view's row.
--
-- If this statement errors with "cannot change name/type of view column", the
-- live view is not 081's — apply 081 first and re-run.

-- The view now calls this (073) as the signed-in user, so make the grant
-- explicit rather than relying on the default EXECUTE to PUBLIC.
GRANT EXECUTE ON FUNCTION get_vehicle_inquiry_unread_count(uuid, uuid)
    TO authenticated;

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
    COALESCE(mi.is_sold, vl.is_sold, false) AS listing_is_sold,
    -- ── Added by 087 ──
    -- The client has read unread_count since the inquiry inbox was built; the
    -- view never provided it, so every inquiry has always looked read. Counted
    -- for whoever is asking, as 045 does for org DMs.
    get_vehicle_inquiry_unread_count(vic.id, auth.uid()) AS unread_count
FROM vehicle_inquiry_conversations vic
LEFT JOIN vehicle_listings vl ON vl.id = vic.vehicle_id
LEFT JOIN market_items     mi ON mi.id = vic.market_item_id
-- LEFT, not JOIN: see the header. A conversation outranks a display name.
LEFT JOIN user_profiles    bp ON bp.id = vic.buyer_id
LEFT JOIN user_profiles    sp ON sp.id = vic.seller_id
LEFT JOIN organizations    o  ON o.id  = vic.organization_id;

COMMENT ON VIEW vehicle_inquiry_conversations_view IS
  'One row per inquiry conversation, about a vehicle or a Market item. '
  'listing_type says which; listing_title / listing_price / listing_image_url / '
  'listing_is_sold describe either, and vehicle_* are NULL for items. '
  'seller_* fall back to the organization for dealer conversations. Every '
  'profile joins LEFT: which conversations you see is RLS on the conversation '
  'table, never whether a profile happens to be readable (087).';

-- CREATE OR REPLACE VIEW resets the view's options to the ones given — none
-- here — so restore the security_invoker that 076 set and 081 restored, the
-- same tolerant way they did.
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
