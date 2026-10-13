-- ============================================================================
-- Migration 085: creator delete (soft) + auto-expiring sold listings
-- ============================================================================
-- 1. deleted_at lets a listing's creator remove it from the app without a
--    hard DELETE. vehicle_inquiry_conversations.vehicle_id references
--    vehicle_listings ON DELETE CASCADE (073), so actually deleting the row
--    would wipe out the buyer's conversation history with it. The row (and
--    its conversations) stay; every browse/list query just filters this out.
--    No new RLS is needed — this is an UPDATE, already covered by "Creators
--    can update their own vehicle listings" (074/077).
--
-- 2. sold_at records exactly when a listing flipped to sold, via trigger
--    rather than the app setting it, so it can't be missed by an update that
--    goes straight to Postgres. CommunityVehicleProvider uses it to clear a
--    sold listing from the shared Cars list 24h after the sale; My Listings
--    is untouched; it always shows the creator's own history, sold included.
-- ============================================================================

ALTER TABLE vehicle_listings
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS sold_at    timestamptz;

-- Existing sold rows predate sold_at; approximate with updated_at so they
-- start aging out of the 24h window immediately rather than being treated as
-- sold "just now".
UPDATE vehicle_listings
   SET sold_at = updated_at
 WHERE is_sold AND sold_at IS NULL;

CREATE OR REPLACE FUNCTION _set_vehicle_listing_sold_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_sold AND NOT OLD.is_sold THEN
    NEW.sold_at = now();
  ELSIF NOT NEW.is_sold AND OLD.is_sold THEN
    NEW.sold_at = NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS vehicle_listings_sold_at ON vehicle_listings;
CREATE TRIGGER vehicle_listings_sold_at
  BEFORE UPDATE ON vehicle_listings
  FOR EACH ROW EXECUTE FUNCTION _set_vehicle_listing_sold_at();

COMMENT ON COLUMN vehicle_listings.sold_at IS
  'Set automatically when is_sold flips true, cleared when it flips back '
  '(see vehicle_listings_sold_at trigger). Community listings clear from the '
  'browse list 24h after this; dealer feed rows are excluded from browse by '
  'is_sold alone and never go through this trigger''s app-facing path.';

COMMENT ON COLUMN vehicle_listings.deleted_at IS
  'Soft delete: set when the creator removes their own listing from the app. '
  'The row and its vehicle_inquiry_conversations are kept on purpose — a hard '
  'DELETE would cascade those away (073) — so every list query filters this '
  'out instead of relying on RLS to hide it.';
