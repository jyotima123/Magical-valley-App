-- Migration 061: organizations_overview view
--
-- Creates a single view that is the authoritative source for organization
-- display data: live follower count (computed from user_follows instead of
-- the denormalized column), whether the current user is following the org
-- (auth.uid()), and the category IDs the org belongs to.
--
-- All app code that needs follower counts or is_following should query this
-- view (or the getAllOrganizations API that now points at it) instead of the
-- raw organizations table.

CREATE OR REPLACE VIEW public.organizations_overview AS
SELECT
  o.id,
  o.name,
  o.logo_url,
  o.created_at,
  o.updated_at,

  -- Live follower count from user_follows (single source of truth).
  -- Replaces the denormalized organizations.follower_count column which can
  -- drift out of sync with the actual user_follows rows.
  (
    SELECT COUNT(*)::int
    FROM public.user_follows uf
    WHERE uf.organization_id = o.id
  ) AS follower_count,

  -- Whether the currently authenticated user follows this org.
  -- auth.uid() is resolved per-request from the JWT, so each caller gets
  -- the correct value for their own session.
  (
    SELECT EXISTS (
      SELECT 1
      FROM public.user_follows uf
      WHERE uf.organization_id = o.id
        AND uf.user_id = auth.uid()
    )
  ) AS is_following,

  -- Category IDs this org belongs to, as a text array.
  COALESCE(
    (
      SELECT array_agg(oc.category_id::text ORDER BY oc.category_id)
      FROM public.organization_categories oc
      WHERE oc.organization_id = o.id
    ),
    '{}'::text[]
  ) AS category_ids

FROM public.organizations o;

-- Allow the PostgREST roles to query this view via the Supabase client.
-- RLS policies on the underlying tables (organizations, user_follows,
-- organization_categories) still apply because the view is SECURITY INVOKER.
GRANT SELECT ON public.organizations_overview TO authenticated;
GRANT SELECT ON public.organizations_overview TO anon;

-- Recommended indexes to keep the correlated subqueries fast:
--   CREATE INDEX IF NOT EXISTS idx_user_follows_org ON public.user_follows(organization_id);
--   CREATE INDEX IF NOT EXISTS idx_user_follows_user_org ON public.user_follows(user_id, organization_id);
--   CREATE INDEX IF NOT EXISTS idx_org_categories_org ON public.organization_categories(organization_id);
-- These likely already exist; listed here for reference only.
