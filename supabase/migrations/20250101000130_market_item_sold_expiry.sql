-- added by export_supabase_migrations.py
SET search_path TO public, extensions;

-- ============================================================================
-- Migration 090: auto-expiring sold market items
-- ============================================================================
-- Mirrors 085 for vehicle_listings. sold_at records exactly when an item
-- flipped to sold, via trigger rather than the app, so it can't be missed by an
-- update that goes straight to Postgres. MarketRepository.fetchItems uses it to
-- clear a sold item from the shared category lists (Marketplace and community
-- Pets) 24h after the sale; My Listings is untouched.
-- ============================================================================

ALTER TABLE market_items
  ADD COLUMN IF NOT EXISTS sold_at timestamptz;

-- Existing sold rows predate sold_at; approximate with updated_at so they
-- start aging out of the 24h window immediately.
UPDATE market_items
   SET sold_at = updated_at
 WHERE is_sold AND sold_at IS NULL;

CREATE OR REPLACE FUNCTION _set_market_item_sold_at()
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

DROP TRIGGER IF EXISTS market_items_sold_at ON market_items;
CREATE TRIGGER market_items_sold_at
  BEFORE UPDATE ON market_items
  FOR EACH ROW EXECUTE FUNCTION _set_market_item_sold_at();

COMMENT ON COLUMN market_items.sold_at IS
  'Set automatically when is_sold flips true, cleared when it flips back '
  '(see market_items_sold_at trigger). Category lists drop the item 24h after '
  'this; the author''s My Listings keeps showing it.';

COMMENT ON COLUMN market_items.is_sold IS
  'Set by the author. A sold item stays in the list, rendered as sold, for '
  '24h (see sold_at); existing conversations continue, but no new one can be '
  'started.';
