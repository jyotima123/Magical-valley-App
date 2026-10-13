-- ============================================================================
-- Migration 077: Let any signed-in user post their own vehicle listing
-- ============================================================================
-- Migration 071 shipped vehicle_listings with an admin/superadmin-only INSERT
-- policy, from when the Cars tab was dealership inventory. It has since become
-- a user-to-user marketplace: the "Add listing" button in vehicles_screen.dart
-- is shown to everyone, and 074 already lets a creator edit and mark sold
-- their own row. The INSERT policy was never widened to match, so a regular
-- user filling in New Listing gets 42501 "new row violates row-level security
-- policy for table vehicle_listings" on Save.
--
-- Fix is purely in the database — the app already sends created_by, and
-- source defaults to 'community' — so no client rebuild is needed.
--
-- Two guards keep the policy from being wider than the old one in ways that
-- matter:
--   * created_by = auth.uid()  -> you can only post as yourself, not attribute
--                                 a listing to another user.
--   * source = 'community'     -> you cannot hand-craft a dealer shadow row.
--                                 Real ones are written by
--                                 create_or_get_dealer_vehicle_inquiry (076),
--                                 which is SECURITY DEFINER and so bypasses
--                                 RLS entirely; this policy does not affect it.
-- ============================================================================

-- 1. Replace the admin-only INSERT policy ────────────────────────────────────

DROP POLICY IF EXISTS "Admins can insert vehicle listings" ON vehicle_listings;

DROP POLICY IF EXISTS "Users can create their own vehicle listings"
  ON vehicle_listings;
CREATE POLICY "Users can create their own vehicle listings"
  ON vehicle_listings FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND source = 'community'
  );

-- 2. Close the same door on UPDATE ───────────────────────────────────────────
-- Without this, the source guard above is decorative: a user could insert a
-- community row and immediately UPDATE it to source = 'liftkit', producing a
-- row that reads as dealer inventory owned by an organization. The app's edit
-- payload (add_vehicle_screen.dart _buildPayload) never sends source or
-- created_by, so this is invisible to legitimate edits. Shadow rows are
-- unaffected either way — their created_by is NULL, so auth.uid() = created_by
-- is never true for them.

DROP POLICY IF EXISTS "Creators can update their own vehicle listings"
  ON vehicle_listings;
CREATE POLICY "Creators can update their own vehicle listings"
  ON vehicle_listings FOR UPDATE
  TO authenticated
  USING (auth.uid() = created_by)
  WITH CHECK (
    auth.uid() = created_by
    AND source = 'community'
  );
