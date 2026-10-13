-- Add login provider feature flags to feature_flags table
-- Controls which login methods are available in the app

ALTER TABLE public.feature_flags
  ADD COLUMN IF NOT EXISTS login_apple_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS login_email_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS login_facebook_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS login_google_enabled boolean NOT NULL DEFAULT false;
