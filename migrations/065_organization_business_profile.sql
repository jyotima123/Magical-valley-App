-- ============================================================================
-- Migration 065: Organization business profile (WhatsApp Business-style)
-- ============================================================================
-- Adds richer profile data to organizations:
--   • bio        – short description / about text (on organizations table)
--   • website_url – primary website link (on organizations table)
--   • organization_phone_numbers – 1-N phone numbers with optional label
--   • organization_addresses     – 1-N physical addresses with optional label
--
-- The organizations_overview view is recreated to expose all new fields so
-- app code has a single query point (no JOIN required on the client side).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. New scalar columns on organizations
-- ----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS bio         TEXT,
  ADD COLUMN IF NOT EXISTS website_url TEXT;

-- ----------------------------------------------------------------------------
-- 2. Phone numbers table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organization_phone_numbers (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  label           VARCHAR(50),          -- e.g. 'Main', 'Support', 'WhatsApp'
  phone_number    VARCHAR(50) NOT NULL,
  display_order   SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_org_phones_org
  ON public.organization_phone_numbers(organization_id);

-- RLS
ALTER TABLE public.organization_phone_numbers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Phone numbers are viewable by authenticated users"
  ON public.organization_phone_numbers FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage their org phone numbers"
  ON public.organization_phone_numbers FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_organizations ao
      JOIN public.user_profiles up ON ao.user_id = up.id
      WHERE up.id = auth.uid()
        AND ao.organization_id = organization_phone_numbers.organization_id
    ) OR
    EXISTS (
      SELECT 1 FROM public.user_profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- ----------------------------------------------------------------------------
-- 3. Addresses table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organization_addresses (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  label           VARCHAR(50),          -- e.g. 'HQ', 'Branch'
  street          TEXT,
  city            VARCHAR(100),
  state           VARCHAR(100),
  country         VARCHAR(100),
  postal_code     VARCHAR(20),
  display_order   SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_org_addresses_org
  ON public.organization_addresses(organization_id);

-- RLS
ALTER TABLE public.organization_addresses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Addresses are viewable by authenticated users"
  ON public.organization_addresses FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage their org addresses"
  ON public.organization_addresses FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_organizations ao
      JOIN public.user_profiles up ON ao.user_id = up.id
      WHERE up.id = auth.uid()
        AND ao.organization_id = organization_addresses.organization_id
    ) OR
    EXISTS (
      SELECT 1 FROM public.user_profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- ----------------------------------------------------------------------------
-- 4. Allow org admins to update the new scalar columns
-- ----------------------------------------------------------------------------
CREATE POLICY "Admins can update their organization profile"
  ON public.organizations FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_organizations ao
      JOIN public.user_profiles up ON ao.user_id = up.id
      WHERE up.id = auth.uid()
        AND ao.organization_id = organizations.id
    ) OR
    EXISTS (
      SELECT 1 FROM public.user_profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- ----------------------------------------------------------------------------
-- 5. Recreate organizations_overview to include new profile fields
-- CREATE OR REPLACE VIEW cannot reorder or insert columns, so we drop first.
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.organizations_overview;

CREATE VIEW public.organizations_overview AS
SELECT
  o.id,
  o.name,
  o.logo_url,
  o.bio,
  o.website_url,
  o.created_at,
  o.updated_at,

  -- Live follower count (source of truth; avoids drift in denormalized column)
  (
    SELECT COUNT(*)::int
    FROM public.user_follows uf
    WHERE uf.organization_id = o.id
  ) AS follower_count,

  -- Whether the currently authenticated user follows this org
  (
    SELECT EXISTS (
      SELECT 1
      FROM public.user_follows uf
      WHERE uf.organization_id = o.id
        AND uf.user_id = auth.uid()
    )
  ) AS is_following,

  -- Category IDs this org belongs to, as a text array
  COALESCE(
    (
      SELECT array_agg(oc.category_id::text ORDER BY oc.category_id)
      FROM public.organization_categories oc
      WHERE oc.organization_id = o.id
    ),
    '{}'::text[]
  ) AS category_ids,

  -- Phone numbers as a JSONB array ordered by display_order
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',           p.id,
          'label',        p.label,
          'phone_number', p.phone_number
        )
        ORDER BY p.display_order, p.created_at
      )
      FROM public.organization_phone_numbers p
      WHERE p.organization_id = o.id
    ),
    '[]'::jsonb
  ) AS phone_numbers,

  -- Addresses as a JSONB array ordered by display_order
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',          a.id,
          'label',       a.label,
          'street',      a.street,
          'city',        a.city,
          'state',       a.state,
          'country',     a.country,
          'postal_code', a.postal_code
        )
        ORDER BY a.display_order, a.created_at
      )
      FROM public.organization_addresses a
      WHERE a.organization_id = o.id
    ),
    '[]'::jsonb
  ) AS addresses

FROM public.organizations o;

-- Restore grants (view was replaced, not altered)
GRANT SELECT ON public.organizations_overview TO authenticated;
GRANT SELECT ON public.organizations_overview TO anon;

-- ----------------------------------------------------------------------------
-- 6. Comments
-- ----------------------------------------------------------------------------
COMMENT ON COLUMN public.organizations.bio         IS 'Short description / about text shown on the organization profile';
COMMENT ON COLUMN public.organizations.website_url IS 'Primary website URL for the organization';
COMMENT ON TABLE  public.organization_phone_numbers IS '1-N phone numbers per organization, ordered by display_order';
COMMENT ON TABLE  public.organization_addresses     IS '1-N physical addresses per organization, ordered by display_order';
