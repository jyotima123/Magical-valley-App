-- ============================================================================
-- ADS STORAGE BUCKET AND RLS POLICIES
-- Creates a storage bucket for ad images with appropriate RLS policies
-- Only superadmins and advertisers can upload ad images
-- Everyone can view ad images
-- ============================================================================

-- 1. Create the ads bucket (must be done through Supabase dashboard or API)
-- This is a reminder/documentation - actual bucket creation might need to be done via dashboard
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('ads', 'ads', true);

-- Note: If running this manually, create the bucket first via:
-- Supabase Dashboard -> Storage -> Create Bucket -> Name: "ads", Public: true

-- 2. Drop existing ads bucket policies if they exist
DROP POLICY IF EXISTS "Advertisers and superadmins can upload ad images" ON storage.objects;
DROP POLICY IF EXISTS "Advertisers can update their own ad images" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to ad images" ON storage.objects;
DROP POLICY IF EXISTS "Advertisers can delete their own ad images" ON storage.objects;
DROP POLICY IF EXISTS "Superadmins can delete any ad image" ON storage.objects;

-- 3. Function to check if user is advertiser or superadmin
CREATE OR REPLACE FUNCTION user_can_manage_ads(p_user_id uuid)
RETURNS boolean AS $$
DECLARE
    user_role text;
BEGIN
    -- Get user role
    SELECT role INTO user_role
    FROM user_profiles
    WHERE id = p_user_id;

    -- Check if user is advertiser or superadmin
    RETURN user_role IN ('advertiser', 'superadmin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 4. Function to extract ad ID or user ID from file path
-- File path format: {user_id}/ad_{ad_id}_{timestamp}.{ext}
CREATE OR REPLACE FUNCTION extract_ad_creator_from_path(file_path text)
RETURNS text AS $$
BEGIN
    -- Extract the first part of the path (before the first '/')
    -- Example: '123e4567-e89b-12d3-a456-426614174000/ad_456_123.png' -> '123e4567-e89b-12d3-a456-426614174000'
    RETURN split_part(file_path, '/', 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- 5. Allow advertisers and superadmins to upload ad images
CREATE POLICY "Advertisers and superadmins can upload ad images" ON storage.objects
FOR INSERT WITH CHECK (
    bucket_id = 'ads'
    AND user_can_manage_ads(auth.uid())
    AND auth.uid()::text = extract_ad_creator_from_path(name)
);

-- 6. Allow advertisers to update their own ad images
-- Superadmins can update any ad image
CREATE POLICY "Advertisers can update their own ad images" ON storage.objects
FOR UPDATE USING (
    bucket_id = 'ads'
    AND (
        -- Advertisers can update their own ad images
        (
            auth.uid()::text = extract_ad_creator_from_path(name)
            AND user_can_manage_ads(auth.uid())
        )
        OR
        -- Superadmins can update any ad image
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    )
);

-- 7. Allow public read access to ad images
CREATE POLICY "Public read access to ad images" ON storage.objects
FOR SELECT USING (bucket_id = 'ads');

-- 8. Allow advertisers to delete their own ad images
CREATE POLICY "Advertisers can delete their own ad images" ON storage.objects
FOR DELETE USING (
    bucket_id = 'ads'
    AND auth.uid()::text = extract_ad_creator_from_path(name)
    AND user_can_manage_ads(auth.uid())
);

-- 9. Allow superadmins to delete any ad image
CREATE POLICY "Superadmins can delete any ad image" ON storage.objects
FOR DELETE USING (
    bucket_id = 'ads'
    AND EXISTS (
        SELECT 1 FROM user_profiles
        WHERE id = auth.uid()
        AND role = 'superadmin'
    )
);

-- ============================================================================
-- MANUAL BUCKET CREATION INSTRUCTIONS
-- ============================================================================
-- Since SQL cannot directly create storage buckets, you need to create it via:
--
-- Option 1 - Supabase Dashboard:
-- 1. Go to Storage section
-- 2. Click "Create Bucket"
-- 3. Name: "ads"
-- 4. Public: true (checked)
-- 5. File size limit: 5MB (or as needed)
-- 6. Allowed MIME types: image/jpeg, image/png, image/webp, image/gif
--
-- Option 2 - Supabase SQL Editor:
-- Run this in the SQL editor (must be run as service_role):
/*
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'ads',
    'ads',
    true,
    5242880, -- 5MB in bytes
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
);
*/
--
-- Option 3 - Supabase Client/API:
-- Use the Supabase JavaScript client to create the bucket programmatically
-- ============================================================================
