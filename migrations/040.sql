-- Create feature_flags table for version management
CREATE TABLE IF NOT EXISTS public.feature_flags (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  min_recommended_version_android character varying,
  min_recommended_version_ios character varying,
  min_required_version_android character varying,
  min_required_version_ios character varying,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT feature_flags_pkey PRIMARY KEY (id)
);

-- Create a unique constraint to ensure only one row exists
-- This makes it a singleton table
CREATE UNIQUE INDEX IF NOT EXISTS feature_flags_singleton_idx ON public.feature_flags ((1));

-- Insert initial row with NULL values (can be updated later)
INSERT INTO public.feature_flags (
  min_recommended_version_android,
  min_recommended_version_ios,
  min_required_version_android,
  min_required_version_ios
) VALUES (
  NULL,  -- Set to version like '1.2.11' when you want to recommend an update
  NULL,  -- Set to version like '1.2.11' when you want to recommend an update
  NULL,  -- Set to version like '1.2.11' when you want to force an update
  NULL   -- Set to version like '1.2.11' when you want to force an update
)
ON CONFLICT DO NOTHING;

-- Create a function to update the updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_feature_flags_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_feature_flags_updated_at
  BEFORE UPDATE ON public.feature_flags
  FOR EACH ROW
  EXECUTE FUNCTION update_feature_flags_updated_at();

-- Example update queries (uncomment and modify as needed):
-- 
-- -- Update recommended versions (dismissible dialog)
-- UPDATE public.feature_flags
-- SET 
--   min_recommended_version_android = '1.3.0',
--   min_recommended_version_ios = '1.3.0'
-- WHERE id = (SELECT id FROM public.feature_flags LIMIT 1);
--
-- -- Update required versions (non-dismissible dialog with 6000s timeout)
-- UPDATE public.feature_flags
-- SET 
--   min_required_version_android = '1.4.0',
--   min_required_version_ios = '1.4.0'
-- WHERE id = (SELECT id FROM public.feature_flags LIMIT 1);
