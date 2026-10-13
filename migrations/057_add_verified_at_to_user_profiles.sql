-- Migration 057: Add verified_at to user_profiles
--
-- Tracks whether the user has completed the app's custom OTP verification
-- (either via email OTP or SMS OTP). Used by _onCheckAuthStatus to route
-- unverified users back to the verification choice screen instead of home,
-- even when a valid Supabase session exists.

ALTER TABLE user_profiles
  ADD COLUMN verified_at TIMESTAMPTZ;

-- Backfill existing users as verified so they are not forced to re-verify.
-- Any user_profiles row that already exists went through the previous signup
-- flow and should be treated as verified.
UPDATE user_profiles SET verified_at = NOW() WHERE verified_at IS NULL;
