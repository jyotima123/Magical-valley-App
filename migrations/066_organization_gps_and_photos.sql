 believe-- ============================================================================
-- Migration 066: GPS coordinates on addresses + organization photo gallery
-- ============================================================================
-- Builds on migration 065. Adds:
--   • latitude / longitude / maps_url on organization_addresses — used by the
--     profile screen to open the correct pin in the device maps app directly,
--     instead of relying on a text-formatted address search.
--   • organization_photos table — 1-N photos per org uploaded to Supabase
--     Storage (bucket: organization-photos).
--
-- The organizations_overview view is dropped and recreated to include:
--   • updated addresses JSONB (now carries lat/lng/maps_url)
--   • new photos JSONB array
--
-- ⚠️  Storage bucket must be created separately in the Supabase dashboard:
--     Name: organization-photos  |  Public: true
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. GPS + maps_url on addresses
-- ----------------------------------------------------------------------------
ALTER TABLE public.organization_addresses
  ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS maps_url  TEXT;

COMMENT ON COLUMN public.organization_addresses.latitude  IS 'WGS-84 latitude; used to open device maps app to an exact pin';
COMMENT ON COLUMN public.organization_addresses.longitude IS 'WGS-84 longitude; used to open device maps app to an exact pin';
COMMENT ON COLUMN public.organization_addresses.maps_url  IS 'Optional direct Google Maps / Apple Maps share link';

-- ----------------------------------------------------------------------------
-- 2. Organization photos table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organization_photos (
  id              UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID    NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  photo_url       TEXT    NOT NULL,
  caption         TEXT,
  display_order   SMALLINT NOT NULL DEFAULT 0,
  created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_org_photos_org
  ON public.organization_photos(organization_id);

COMMENT ON TABLE public.organization_photos IS '1-N place photos per organization; photo_url points to Supabase Storage (organization-photos bucket)';

-- RLS
ALTER TABLE public.organization_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Photos are viewable by authenticated users"
  ON public.organization_photos FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage their org photos"
  ON public.organization_photos FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_organizations ao
      JOIN public.user_profiles up ON ao.user_id = up.id
      WHERE up.id = auth.uid()
        AND ao.organization_id = organization_photos.organization_id
    ) OR
    EXISTS (
      SELECT 1 FROM public.user_profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

-- ----------------------------------------------------------------------------
-- 3. Recreate organizations_overview with new fields
--    (DROP required because column order changed again)
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

  (
    SELECT COUNT(*)::int
    FROM public.user_follows uf
    WHERE uf.organization_id = o.id
  ) AS follower_count,

  (
    SELECT EXISTS (
      SELECT 1 FROM public.user_follows uf
      WHERE uf.organization_id = o.id AND uf.user_id = auth.uid()
    )
  ) AS is_following,

  COALESCE(
    (
      SELECT array_agg(oc.category_id::text ORDER BY oc.category_id)
      FROM public.organization_categories oc
      WHERE oc.organization_id = o.id
    ),
    '{}'::text[]
  ) AS category_ids,

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
          'postal_code', a.postal_code,
          'latitude',    a.latitude,
          'longitude',   a.longitude,
          'maps_url',    a.maps_url
        )
        ORDER BY a.display_order, a.created_at
      )
      FROM public.organization_addresses a
      WHERE a.organization_id = o.id
    ),
    '[]'::jsonb
  ) AS addresses,

  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',        ph.id,
          'photo_url', ph.photo_url,
          'caption',   ph.caption
        )
        ORDER BY ph.display_order, ph.created_at
      )
      FROM public.organization_photos ph
      WHERE ph.organization_id = o.id
    ),
    '[]'::jsonb
  ) AS photos

FROM public.organizations o;

GRANT SELECT ON public.organizations_overview TO authenticated;
GRANT SELECT ON public.organizations_overview TO anon;
