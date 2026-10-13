-- ============================================================================
-- Migration 080: Market — listing categories and generic items
-- ============================================================================
-- The Cars tab becomes one category of a wider "Market" section:
--
--   Cars & Trucks     -> vehicle_listings, unchanged. Keeps its car fields,
--                        filters, dealer feeds and stock numbers.
--   every other one   -> market_items, added here.
--
-- The non-car categories share one table because they share one shape: a
-- title, a price, a description, photos, a seller and a sold flag. Nothing
-- about a sofa or a saddle needs columns of its own yet; a category that later
-- does can grow a side table keyed on market_items.id without touching the
-- rest.
--
-- Categories are rows, not a CHECK list, for the same reason 078 made
-- dealer_sources a registry: renaming, reordering or hiding a category is an
-- UPDATE, not a migration. Cars & Trucks has a row too, so the Market screen
-- builds its whole category grid from one query — but that slug is reserved
-- and can never hold a market_items row.
--
-- The table is market_categories, not categories: migration 001 already owns
-- `categories` for organization categories.
--
-- Listing and "mark as sold" follow the community-vehicle rules (074, 077):
-- anyone signed in can list, only the author can edit or mark sold, and a sold
-- item stays visible. Messaging is wired up in 081.
--
-- Applies on top of 079.
-- ============================================================================

-- 1. Categories ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS market_categories (
    slug        text        PRIMARY KEY,
    name        text        NOT NULL,
    sort_order  integer     NOT NULL DEFAULT 0,
    is_active   boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT market_categories_slug_format CHECK (slug ~ '^[a-z0-9_]+$')
);

COMMENT ON TABLE market_categories IS
  'The categories of the Market section, in display order. cars_trucks is '
  'backed by vehicle_listings; every other category is backed by market_items.';

COMMENT ON COLUMN market_categories.slug IS
  'Stable identifier the app keys icons and routing on. cars_trucks is '
  'reserved: market_items_not_a_vehicle refuses it by this literal, so it must '
  'never be renamed.';

COMMENT ON COLUMN market_categories.is_active IS
  'The off switch. Inactive categories are hidden from the Market screen and '
  'accept no new listings; existing listings and their conversations are left '
  'untouched.';

-- Steps of 10 leave room to slot a category in without renumbering the rest.
-- DO NOTHING so a re-run never undoes a rename or reorder made in production.
INSERT INTO market_categories (slug, name, sort_order) VALUES
    ('cars_trucks',       'Cars & Trucks',        10),
    ('powersports',       'Powersports',          20),
    ('home_garden',       'Home & Garden',        30),
    ('tools_equipment',   'Tools & Equipment',    40),
    ('farm_ranch',        'Farm & Ranch',         50),
    ('sports_recreation', 'Sports & Recreation',  60),
    ('clothing_shoes',    'Clothing & Shoes',     70),
    ('electronics',       'Electronics',          80),
    ('furniture',         'Furniture',            90),
    ('pets_animals',      'Pets & Animals',      100)
ON CONFLICT (slug) DO NOTHING;

ALTER TABLE market_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view market categories"
    ON market_categories;
CREATE POLICY "Authenticated users can view market categories"
    ON market_categories FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Superadmins manage market categories"
    ON market_categories;
CREATE POLICY "Superadmins manage market categories"
    ON market_categories FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );

DROP TRIGGER IF EXISTS market_categories_updated_at ON market_categories;
CREATE TRIGGER market_categories_updated_at
    BEFORE UPDATE ON market_categories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Items ───────────────────────────────────────────────────────────────────
-- The generic half of vehicle_listings: price, promotion, description,
-- location, images, videos, contact_phone, is_sold, created_by. `title` stands
-- in for the year/make/model a car is named by, and `condition` for its
-- New/Pre-Owned status.
--
-- images is a comma-separated list of URLs, as in vehicle_listings, so the
-- existing photo upload and gallery code works on both.

CREATE TABLE IF NOT EXISTS market_items (
    id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
    -- No ON DELETE: a category with listings cannot be deleted, only hidden
    -- with is_active.
    category      text          NOT NULL
                  REFERENCES market_categories(slug) ON UPDATE CASCADE,
    title         text          NOT NULL,
    description   text,
    condition     text,
    price         numeric(10,2) NOT NULL,
    promotion     numeric(10,2),
    location      text,
    images        text,
    videos        text,
    contact_phone text,
    is_sold       boolean       NOT NULL DEFAULT false,
    -- Always a personal sale (there are no Market feeds), so always an author.
    -- CASCADE rather than vehicle_listings' SET NULL: a listing whose seller is
    -- gone can never be answered, and the seller's conversations already
    -- cascade away with their profile (073).
    created_by    uuid          NOT NULL
                  REFERENCES user_profiles(id) ON DELETE CASCADE,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT market_items_not_a_vehicle
      CHECK (category <> 'cars_trucks'),
    CONSTRAINT market_items_title_not_blank
      CHECK (btrim(title) <> ''),
    -- 0 is allowed: giveaways and rehoming are common in Pets & Animals.
    CONSTRAINT market_items_price_non_negative
      CHECK (price >= 0),
    CONSTRAINT market_items_promotion_non_negative
      CHECK (promotion IS NULL OR promotion >= 0),
    -- Optional: it means nothing for, say, a horse.
    CONSTRAINT market_items_condition_check CHECK (
      condition IS NULL OR
      condition IN ('new', 'like_new', 'good', 'fair', 'for_parts')
    )
);

COMMENT ON TABLE market_items IS
  'Listings in every Market category except Cars & Trucks, which lives in '
  'vehicle_listings. Buyers reach the seller through '
  'create_or_get_market_item_inquiry (081).';

COMMENT ON COLUMN market_items.promotion IS
  'Discounted price shown alongside `price`, as in vehicle_listings.';

COMMENT ON COLUMN market_items.is_sold IS
  'Set by the author. A sold item stays in the list, rendered as sold; '
  'existing conversations continue, but no new one can be started.';

-- The browse query: one category, newest first. Sold items stay listed.
CREATE INDEX IF NOT EXISTS idx_market_items_category_created
    ON market_items (category, created_at DESC);

-- "My listings".
CREATE INDEX IF NOT EXISTS idx_market_items_created_by
    ON market_items (created_by);

DROP TRIGGER IF EXISTS market_items_updated_at ON market_items;
CREATE TRIGGER market_items_updated_at
    BEFORE UPDATE ON market_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. Row-Level Security ──────────────────────────────────────────────────────
-- Same shape as vehicle_listings after 077.

ALTER TABLE market_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view market items"
    ON market_items;
CREATE POLICY "Authenticated users can view market items"
    ON market_items FOR SELECT
    TO authenticated
    USING (true);

-- You can only list as yourself, and only in a category that is open.
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
    );

-- Edit and mark as sold. WITH CHECK stops an author handing the listing to
-- another user. It deliberately does not re-check is_active, so a listing in a
-- category that was later hidden can still be edited and marked sold.
DROP POLICY IF EXISTS "Creators can update their own market items"
    ON market_items;
CREATE POLICY "Creators can update their own market items"
    ON market_items FOR UPDATE
    TO authenticated
    USING (auth.uid() = created_by)
    WITH CHECK (auth.uid() = created_by);

-- Moderation, including delete. As with vehicle_listings, authors cannot hard-
-- delete: that would cascade away the buyers' conversations with it.
DROP POLICY IF EXISTS "Superadmins full access to market items"
    ON market_items;
CREATE POLICY "Superadmins full access to market items"
    ON market_items FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid() AND role = 'superadmin'
        )
    );
