-- added by export_supabase_migrations.py
SET search_path TO public, extensions;

-- ============================================================================
-- Migration 089: Promoted Market listings
-- ============================================================================
-- A listing can be promoted until a given time. While it is, it also appears
-- in the carousel at the top of its category; it stays in the normal list
-- either way.
--
-- Promotion is granted by a superadmin for now (from the listing's menu in the
-- app). There is no payment flow yet. The creator UPDATE policy from 080 covers
-- every column, so without the trigger below a seller could promote their own
-- listing straight through the API.
--
-- Applies on top of 088.
-- ============================================================================

ALTER TABLE market_items
  ADD COLUMN IF NOT EXISTS promoted_until timestamptz;

COMMENT ON COLUMN market_items.promoted_until IS
  'While in the future, the item is shown in its category''s Promoted carousel '
  '(089). Set by superadmins only; NULL = not promoted.';

-- The carousel query: one category's currently promoted items.
CREATE INDEX IF NOT EXISTS idx_market_items_promoted
    ON market_items (promoted_until DESC)
    WHERE promoted_until IS NOT NULL;

-- Only a superadmin may set or change promoted_until. Checked in a trigger
-- rather than a policy because RLS cannot restrict individual columns.
-- Statements with no signed-in user — the SQL editor, the service role — are
-- operators and pass; app users always carry a JWT.
CREATE OR REPLACE FUNCTION guard_market_item_promotion()
RETURNS trigger AS $$
BEGIN
    -- Nothing to check when the promotion is left as it was. (No CASE inside
    -- the IF condition: PL/pgSQL ends the condition at the first THEN.)
    IF TG_OP = 'UPDATE' THEN
        IF NEW.promoted_until IS NOT DISTINCT FROM OLD.promoted_until THEN
            RETURN NEW;
        END IF;
    ELSIF NEW.promoted_until IS NULL THEN
        RETURN NEW;
    END IF;

    IF current_jwt_user_id() IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM user_profiles
           WHERE id = current_jwt_user_id() AND role = 'superadmin'
       )
    THEN
        RAISE EXCEPTION 'Only an administrator can promote a listing'
            USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS market_items_guard_promotion ON market_items;
CREATE TRIGGER market_items_guard_promotion
    BEFORE INSERT OR UPDATE OF promoted_until ON market_items
    FOR EACH ROW EXECUTE FUNCTION guard_market_item_promotion();

-- ============================================================================
-- Promote by hand:
--   UPDATE market_items SET promoted_until = now() + interval '7 days'
--   WHERE id = '<item uuid>';
--
-- Verification
--   SELECT id, title, category, promoted_until FROM market_items
--   WHERE promoted_until > now() ORDER BY promoted_until DESC;
-- ============================================================================
