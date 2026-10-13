-- ============================================================================
-- Migration 086: Market — a second category per item, and a shorter category list
-- ============================================================================
-- 1. An item can now sit in up to two categories: `category` stays the primary
--    one (it is what the rest of the schema keys on, including the inquiry view
--    from 081), and `secondary_category` is an optional second.
--
-- 2. Until the next release only four categories are offered: Cars, General,
--    Pets and Ag & Livestock. The rest are hidden with is_active, not deleted,
--    so bringing them back is the UPDATE at the bottom. Existing listings in a
--    hidden category, and their conversations, are left untouched (see 080).
--
-- Applies on top of 085.
-- ============================================================================

-- 1. Secondary category ──────────────────────────────────────────────────────

ALTER TABLE market_items
    ADD COLUMN IF NOT EXISTS secondary_category text
        REFERENCES market_categories(slug) ON UPDATE CASCADE;

ALTER TABLE market_items
    DROP CONSTRAINT IF EXISTS market_items_secondary_not_a_vehicle,
    DROP CONSTRAINT IF EXISTS market_items_secondary_differs;

ALTER TABLE market_items
    ADD CONSTRAINT market_items_secondary_not_a_vehicle
      CHECK (secondary_category IS NULL OR secondary_category <> 'cars_trucks'),
    ADD CONSTRAINT market_items_secondary_differs
      CHECK (secondary_category IS NULL OR secondary_category <> category);

COMMENT ON COLUMN market_items.secondary_category IS
  'Optional second category. The item is listed under both; `category` remains '
  'the primary one.';

-- The browse query matches either column.
CREATE INDEX IF NOT EXISTS idx_market_items_secondary_created
    ON market_items (secondary_category, created_at DESC)
    WHERE secondary_category IS NOT NULL;

-- Listing in a hidden category is refused for the second slot too.
DROP POLICY IF EXISTS "Users can create their own market items"
    ON market_items;
CREATE POLICY "Users can create their own market items"
    ON market_items FOR INSERT
    TO authenticated
    WITH CHECK (
        created_by = auth.uid()
        AND EXISTS (
            SELECT 1 FROM market_categories mc
            WHERE mc.slug = market_items.category
              AND mc.is_active
        )
        AND (
            market_items.secondary_category IS NULL
            OR EXISTS (
                SELECT 1 FROM market_categories mc
                WHERE mc.slug = market_items.secondary_category
                  AND mc.is_active
            )
        )
    );

-- 2. Hide every category but four ────────────────────────────────────────────

UPDATE market_categories
SET is_active = (slug IN ('cars_trucks', 'general', 'pets', 'ag_livestock')),
    updated_at = now();

-- ============================================================================
-- To bring the hidden categories back in the next release:
--   UPDATE market_categories SET is_active = true;
--
-- Verification
--   SELECT slug, is_active FROM market_categories ORDER BY sort_order;
--                                                 -- 4 rows true, 10 false
-- ============================================================================
