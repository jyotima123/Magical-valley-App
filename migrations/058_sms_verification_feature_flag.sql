-- Migration 058: Add sms_verification_enabled feature flag
--
-- Controls whether the SMS verification option is shown on the verification
-- method choice screen. Defaults to false so it can be enabled per-environment
-- (e.g. true in QA for testing, true in production when ready to launch).
--
-- Production and QA are separate Supabase projects, so each project's
-- feature_flags row is configured independently after running this migration.

ALTER TABLE public.feature_flags
  ADD COLUMN IF NOT EXISTS sms_verification_enabled boolean NOT NULL DEFAULT false;
