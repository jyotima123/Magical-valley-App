-- ============================================================================
-- Migration 074: Vehicle listing "sold" flag + creator edit permissions
-- ============================================================================
-- 1. Adds is_sold so the ad creator can mark a car as sold. Sold listings stay
--    visible in the list (rendered as "Sold") but other users can no longer
--    interact with them.
-- 2. Lets the creator of a listing update their own row (edit / mark as sold),
--    which previously required the admin role.
-- ============================================================================

ALTER TABLE vehicle_listings
  ADD COLUMN IF NOT EXISTS is_sold boolean NOT NULL DEFAULT false;

CREATE POLICY "Creators can update their own vehicle listings"
  ON vehicle_listings FOR UPDATE
  TO authenticated
  USING (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);
