-- added by export_supabase_migrations.py
SET search_path TO public, extensions;

-- ============================================================================
-- Migration 072: Add contact_phone to vehicle_listings
-- ============================================================================

ALTER TABLE vehicle_listings
  ADD COLUMN contact_phone text;
