-- ============================================================================
-- Migration 083: Market — the category list as it ships
-- ============================================================================
-- Renames the ten categories seeded by 080 and adds four more, so the Market
-- screen reads:
--
--   Cars, Recreational Vehicles, Home & Garden, Industrial, Ag & Livestock,
--   Sports & Fitness, Clothing, Electronics, Furniture, Pets,
--   Musical Instruments, Auto Parts, Outdoors, General
--
-- This is exactly the UPDATE that 080 promised instead of a schema change: the
-- categories are rows, so renaming and reordering them is data.
--
-- Slugs move with the names, because a slug that says `powersports` under a
-- category called "Recreational Vehicles" is a trap for whoever reads it next.
-- market_items.category references market_categories(slug) ON UPDATE CASCADE,
-- so listings follow their category across the rename by themselves.
--
-- The one slug that does NOT move is cars_trucks, whatever its name says now:
--
--   * market_items_not_a_vehicle (080) refuses that literal, and
--   * listing_category in vehicle_inquiry_conversations_view (081) writes it,
--   * installed app builds route the Cars screen on it. A build that has not
--     been updated would treat a renamed slug as an ordinary category and open
--     an empty list where the cars are.
--
-- Older builds do keep their icons keyed on the old slugs, so the categories
-- renamed here show a generic icon until the user updates. Names come from
-- this table, so every build shows the new names immediately.
--
-- Applies on top of 082.
-- ============================================================================

-- 1. Rename and reorder what 080 seeded ──────────────────────────────────────

-- Steps of 10, in the order the Market screen shows them. Re-running this is a
-- no-op: the second pass finds no row under the old slug.
UPDATE market_categories AS c
SET slug       = v.new_slug,
    name       = v.new_name,
    sort_order = v.new_order,
    updated_at = now()
FROM (VALUES
    ('cars_trucks',       'cars_trucks',           'Cars',                   10),
    ('powersports',       'recreational_vehicles', 'Recreational Vehicles',  20),
    ('home_garden',       'home_garden',           'Home & Garden',          30),
    ('tools_equipment',   'industrial',            'Industrial',             40),
    ('farm_ranch',        'ag_livestock',          'Ag & Livestock',         50),
    ('sports_recreation', 'sports_fitness',        'Sports & Fitness',       60),
    ('clothing_shoes',    'clothing',              'Clothing',               70),
    ('electronics',       'electronics',           'Electronics',            80),
    ('furniture',         'furniture',             'Furniture',              90),
    ('pets_animals',      'pets',                  'Pets',                  100)
) AS v (old_slug, new_slug, new_name, new_order)
WHERE c.slug = v.old_slug;

-- 2. The four new ones ───────────────────────────────────────────────────────

-- DO NOTHING for the same reason as in 080: a re-run must not undo a later
-- rename or reorder made in production.
INSERT INTO market_categories (slug, name, sort_order) VALUES
    ('musical_instruments', 'Musical Instruments', 110),
    ('auto_parts',          'Auto Parts',          120),
    ('outdoors',            'Outdoors',            130),
    ('general',             'General',             140)
ON CONFLICT (slug) DO NOTHING;

-- 3. Record why cars_trucks reads "Cars" ─────────────────────────────────────

COMMENT ON COLUMN market_categories.slug IS
  'Stable identifier the app keys icons and routing on. cars_trucks is '
  'reserved and must never be renamed: market_items_not_a_vehicle refuses it '
  'by this literal, migration 081 writes it as listing_category, and installed '
  'builds route the Cars screen on it. Its name changed to "Cars" in 083; the '
  'slug is deliberately left as it was.';

-- ============================================================================
-- Verification
-- ============================================================================
--   SELECT slug, name, sort_order, is_active
--   FROM market_categories ORDER BY sort_order;      -- 14 rows, Cars first
--
--   SELECT category, count(*) FROM market_items GROUP BY category;
--                                                    -- no old slug survives
-- ============================================================================
