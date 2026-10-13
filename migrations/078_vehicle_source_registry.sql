-- ============================================================================
-- 078: `source` becomes a registry, not a hardcoded list
--
-- 076 pinned the set of inventory providers into a CHECK constraint:
--
--     CHECK (source IN ('community', 'liftkit'))
--
-- which means onboarding a provider is a schema migration, and retiring one is
-- another. With vAuto arriving as the second feed — and more expected after it —
-- that is the wrong shape: a provider should be a row, so adding or dropping one
-- cannot touch, break, or require redeploying the others.
--
-- dealer_sources is already keyed by the same `source` text and already the
-- thing you insert a row into per provider, so it becomes the registry. Two
-- columns carry the distinction that matters:
--
--   provider  which code path fetches and maps it ('liftkit', 'vauto', ...).
--   kind      how it reaches us, which decides where its rows may be read:
--
--     'community'  listed in-app by a user. Exactly one such row, owning no
--                  organization: these are personal sales.
--     'api'        pulled live from the provider at read time. Stored rows are
--                  shadow rows, materialized on first buyer contact, and must
--                  stay out of the browse list.
--     'feed'       pushed to us as a file and ingested. The stored rows ARE the
--                  inventory, so they belong in the browse list.
--
-- ── One row per DEALER, not per vendor ──────────────────────────────────────
--
-- 076 states the rule this table exists to enforce: "A feed mirrors exactly one
-- dealership, so one organization covers every vehicle from it." vAuto breaks
-- that if modelled as a single 'vauto' source, because one vAuto account
-- delivers a separate file for each dealership it exports for. Collapsing them
-- would route every dealer's buyer messages into one organization's inbox, and
-- would make "mark everything absent from this file as sold" erase every OTHER
-- dealer's inventory on each import.
--
-- So the registry is keyed per dealership — 'vauto:48213', 'vauto:50991' — with
-- `provider` grouping them for the code and `dealer_ref` holding the vendor's
-- own id for the ingest lookup. Onboarding dealer N is still one INSERT.
--
-- Applies on top of 077.
-- ============================================================================

-- 1. Registry columns ────────────────────────────────────────────────────────

ALTER TABLE dealer_sources
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS kind         text NOT NULL DEFAULT 'feed',
  ADD COLUMN IF NOT EXISTS provider     text,
  ADD COLUMN IF NOT EXISTS dealer_ref   text;

-- Existing rows predate `provider`; before 078 the source key and the provider
-- were the same string.
UPDATE dealer_sources SET provider = source WHERE provider IS NULL;
ALTER TABLE dealer_sources ALTER COLUMN provider SET NOT NULL;

-- The community row has no owning dealership, so the column can no longer be
-- mandatory. A feed row is also allowed to sit here with a NULL organization
-- between "vAuto is delivering files" and "we know which org answers for them";
-- create_or_get_dealer_vehicle_inquiry already raises a distinct, operator-
-- readable error in that window ("No dealership is configured for this
-- inventory yet", 076 line 490), which is exactly the behaviour we want.
ALTER TABLE dealer_sources ALTER COLUMN organization_id DROP NOT NULL;

ALTER TABLE dealer_sources
  DROP CONSTRAINT IF EXISTS dealer_sources_kind_check;
ALTER TABLE dealer_sources
  ADD CONSTRAINT dealer_sources_kind_check
  CHECK (kind IN ('community', 'api', 'feed'));

-- A personal-sale source can never be owned by a dealership; if one ever were,
-- buyer messages would route to an org instead of to the seller.
ALTER TABLE dealer_sources
  DROP CONSTRAINT IF EXISTS dealer_sources_community_has_no_org;
ALTER TABLE dealer_sources
  ADD CONSTRAINT dealer_sources_community_has_no_org
  CHECK (kind <> 'community' OR organization_id IS NULL);

-- How the ingest function resolves "file says dealer 48213" to a source key.
-- Partial, because only multi-dealer providers carry a dealer_ref at all.
CREATE UNIQUE INDEX IF NOT EXISTS dealer_sources_provider_dealer_ref_key
  ON dealer_sources (provider, dealer_ref)
  WHERE dealer_ref IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_dealer_sources_provider
  ON dealer_sources (provider) WHERE is_active;

COMMENT ON COLUMN dealer_sources.provider IS
  'Which integration handles this source: the Flutter provider that fetches it '
  'and, for feeds, the mapper that parses it. Many sources can share a provider '
  '— one per dealership that vendor exports for.';

COMMENT ON COLUMN dealer_sources.dealer_ref IS
  'The vendor''s own identifier for this dealership, as it appears in the '
  'delivered file. NULL for single-dealership providers.';

COMMENT ON COLUMN dealer_sources.kind IS
  'community = in-app personal listings; api = pulled live at read time, stored '
  'rows are shadow rows and are excluded from browse; feed = delivered as a '
  'file and ingested, stored rows are the real inventory and are browsable.';

COMMENT ON COLUMN dealer_sources.display_name IS
  'Provider/dealership name for operator-facing surfaces (import logs, admin).';

COMMENT ON COLUMN dealer_sources.is_active IS
  'The off switch. Inactive sources are not fetched, not ingested, and cannot '
  'start new conversations; their rows and conversations are left untouched.';

-- 2. Seed the registry with what already exists ──────────────────────────────

INSERT INTO dealer_sources (source, organization_id, provider, kind, display_name, is_active)
VALUES ('community', NULL, 'community', 'community', 'Community', true)
ON CONFLICT (source) DO UPDATE
  SET provider     = 'community',
      kind         = 'community',
      display_name = COALESCE(dealer_sources.display_name, 'Community');

-- organization_id is deliberately absent from the UPDATE branch: whatever an
-- environment already has wired up must survive a re-run of this migration.
INSERT INTO dealer_sources (source, organization_id, provider, kind, display_name)
VALUES ('liftkit', NULL, 'liftkit', 'api', 'LiftKit')
ON CONFLICT (source) DO UPDATE
  SET provider     = 'liftkit',
      kind         = 'api',
      display_name = COALESCE(dealer_sources.display_name, 'LiftKit');

-- No 'vauto' row is seeded. vAuto sources are per-dealership and are created by
-- an operator during onboarding — see the wiring notes at the bottom. Until a
-- dealership exists here, the ingest function rejects that dealer's file with a
-- named error rather than inventing a home for the vehicles.

-- Any source that reached vehicle_listings without a registry row would fail
-- the foreign key below. There should be none, but a migration that aborts
-- halfway is worse than one that adopts a stray value as an inactive provider.
INSERT INTO dealer_sources (source, organization_id, provider, kind, display_name, is_active)
SELECT DISTINCT vl.source, NULL::uuid, vl.source, 'feed', vl.source, false
FROM vehicle_listings vl
WHERE NOT EXISTS (
  SELECT 1 FROM dealer_sources ds WHERE ds.source = vl.source
)
ON CONFLICT (source) DO NOTHING;

-- 3. Swap the CHECK for a foreign key ────────────────────────────────────────

ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_source_check;

ALTER TABLE vehicle_listings
  DROP CONSTRAINT IF EXISTS vehicle_listings_source_fkey;
-- No ON DELETE clause: the default (NO ACTION) refuses to delete a provider
-- that still has listings, matching how organization_id guards itself.
ALTER TABLE vehicle_listings
  ADD CONSTRAINT vehicle_listings_source_fkey
  FOREIGN KEY (source) REFERENCES dealer_sources(source) ON UPDATE CASCADE;

-- `community` stays a reserved literal in vehicle_listings_external_id_presence
-- rather than becoming kind-aware: a CHECK cannot read another table, and the
-- alternative (a trigger firing on every ingested row) costs more than the
-- constraint is worth. The rule is unchanged: only in-app listings lack a
-- provider-side identifier.

COMMENT ON COLUMN vehicle_listings.source IS
  'FK into dealer_sources, which says what kind of provider it is. community = '
  'listed in-app by a user (always a personal listing, whatever their role). A '
  'kind=api source stores shadow rows, mirrored on first buyer contact and '
  'excluded from the Cars list because the live feed is rendered instead. A '
  'kind=feed source stores the inventory itself, ingested from a delivered '
  'file, and those rows ARE what the Cars list renders. Feed sources are per '
  'dealership, so this also identifies which dealer a vehicle belongs to.';

-- 4. Wiring notes ────────────────────────────────────────────────────────────
--
-- Onboard a vAuto dealership. `dealer_ref` must match the dealer id vAuto puts
-- in the file; `source` is conventionally provider:dealer_ref:
--
--   INSERT INTO dealer_sources
--     (source, organization_id, provider, kind, dealer_ref, display_name, is_active)
--   VALUES
--     ('vauto:48213', '<organizations.id>', 'vauto', 'feed', '48213',
--      'Smith Chevrolet', true);
--
-- Point LiftKit at the organization that answers for it:
--
--   UPDATE dealer_sources
--      SET organization_id = '<organizations.id>', is_active = true
--    WHERE source = 'liftkit';
--
-- Onboard an entirely new vendor without a migration — only its mapper is code:
--
--   INSERT INTO dealer_sources
--     (source, organization_id, provider, kind, dealer_ref, display_name)
--   VALUES ('homenet:771', '<organizations.id>', 'homenet', 'feed', '771', 'Ridgeline Ford');
--
-- Retire one without deleting its history:
--
--   UPDATE dealer_sources SET is_active = false WHERE source = 'vauto:48213';
