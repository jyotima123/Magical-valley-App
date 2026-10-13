-- ============================================================================
-- Migration 067: maps_url scalar on organizations
-- ============================================================================
-- Adds a single Google Maps / Apple Maps share link directly on the
-- organizations row (e.g. https://maps.app.goo.gl/SdvggNrSGAbBJZg39).
-- Admins paste this from the Google Maps "Share → Copy link" flow.
-- GPS coordinates (latitude / longitude) can still be set per-address via
-- the organization_addresses table; this field is the quick "place link".
-- ============================================================================

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS maps_url TEXT;

COMMENT ON COLUMN public.organizations.maps_url
  IS 'Google Maps / Apple Maps share link for the organisation location';

-- Recreate the view to expose the new column.
DROP VIEW IF EXISTS public.organizations_overview;

CREATE VIEW public.organizations_overview AS
SELECT
  o.id,
  o.name,
  o.logo_url,
  o.bio,
  o.website_url,
  o.maps_url,
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
