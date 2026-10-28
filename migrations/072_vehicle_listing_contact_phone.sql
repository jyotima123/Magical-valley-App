-- ============================================================================
-- Migration 072: Add contact_phone to vehicle_listings
-- ============================================================================

ALTER TABLE vehicle_listings
  ADD COLUMN contact_phone text;
