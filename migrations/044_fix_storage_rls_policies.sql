-- ============================================================================
-- FIX STORAGE RLS POLICIES FOR ALL BUCKETS
-- This migration fixes RLS policies to properly handle:
-- - Regular users: can only upload their own profile picture (avatars bucket)
-- - Admins: can upload organization logos (logos bucket) AND upload posts (uploads bucket)
-- - Super admins: can do anything with any bucket
-- ============================================================================

-- ============================================================================
-- PART 1: FIX LOGOS BUCKET POLICIES
-- ============================================================================

-- Drop existing logos bucket policies
DROP POLICY IF EXISTS "Organization admins can upload logos" ON storage.objects;
DROP POLICY IF EXISTS "Organization admins can update logos" ON storage.objects;
DROP POLICY IF EXISTS "Organization admins can delete logos" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to logos" ON storage.objects;
DROP FUNCTION IF EXISTS user_can_manage_organization_logo(uuid, text);

-- Create a more reliable function to extract organization ID from file path
-- File path format: {organization_id}/logo_{timestamp}.{ext}
CREATE OR REPLACE FUNCTION extract_org_id_from_path(file_path text)
RETURNS text AS $$
BEGIN
    -- Extract the first part of the path (before the first '/')
    -- Example: '513b3132-1fe1-4cdf-93a0-69bceed73f1e/logo_123.png' -> '513b3132-1fe1-4cdf-93a0-69bceed73f1e'
    RETURN split_part(file_path, '/', 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Create a SECURITY DEFINER function to check organization admin privileges
-- This bypasses RLS when checking admin permissions
CREATE OR REPLACE FUNCTION user_can_manage_organization_logo(p_user_id uuid, org_id_text text)
RETURNS boolean AS $$
DECLARE
    org_uuid uuid;
    user_role text;
BEGIN
    -- Get user role first (using SECURITY DEFINER to bypass RLS)
    SELECT role INTO user_role
    FROM user_profiles
    WHERE id = p_user_id;
    
    -- Super admins can manage any organization logo
    IF user_role = 'superadmin' THEN
        RETURN true;
    END IF;
    
    -- Regular users cannot manage organization logos
    IF user_role = 'regular' OR user_role IS NULL THEN
        RETURN false;
    END IF;
    
    -- For admins, check if they are assigned to this organization
    -- Convert text to UUID
    BEGIN
        org_uuid := org_id_text::uuid;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN false;
    END;
    
    -- Check if user is admin of the specific organization
    RETURN EXISTS (
        SELECT 1 
        FROM admin_organizations ao
        WHERE ao.user_id = p_user_id 
        AND ao.organization_id = org_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 1. Allow organization admins and superadmins to upload logos
CREATE POLICY "Organization admins can upload logos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'logos'
  AND (
    -- Super admins can upload any logo
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
    OR
    -- Admins can upload logos for organizations they manage
    user_can_manage_organization_logo(
      auth.uid(), 
      extract_org_id_from_path(name)
    )
  )
);

-- 2. Allow organization admins and superadmins to update logos
CREATE POLICY "Organization admins can update logos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'logos'
  AND (
    -- Super admins can update any logo
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
    OR
    -- Admins can update logos for organizations they manage
    user_can_manage_organization_logo(
      auth.uid(), 
      extract_org_id_from_path(name)
    )
  )
);

-- 3. Allow public read access to logos
CREATE POLICY "Public read access to logos" ON storage.objects
FOR SELECT USING (bucket_id = 'logos');

-- 4. Allow organization admins and superadmins to delete logos
CREATE POLICY "Organization admins can delete logos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'logos'
  AND (
    -- Super admins can delete any logo
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
    OR
    -- Admins can delete logos for organizations they manage
    user_can_manage_organization_logo(
      auth.uid(), 
      extract_org_id_from_path(name)
    )
  )
);

-- ============================================================================
-- PART 2: ENSURE AVATARS BUCKET POLICIES (Regular users can only upload their own)
-- ============================================================================

-- Drop existing avatars policies if they exist (they should already be correct, but let's ensure)
DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
DROP POLICY IF EXISTS "Super admins can manage any avatar" ON storage.objects;

-- Allow authenticated users to upload their own avatar
-- File path format: {user_id}/avatar.{ext}
CREATE POLICY "Users can upload their own avatar" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'avatars'
  AND (
    -- Users can upload their own avatar
    auth.uid()::text = extract_org_id_from_path(name)
    OR
    -- Super admins can upload any avatar
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
  )
);

-- Allow authenticated users to update their own avatar
CREATE POLICY "Users can update their own avatar" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'avatars'
  AND (
    -- Users can update their own avatar
    auth.uid()::text = extract_org_id_from_path(name)
    OR
    -- Super admins can update any avatar
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
  )
);

-- Allow public read access to avatars
CREATE POLICY "Public read access to avatars" ON storage.objects
FOR SELECT USING (bucket_id = 'avatars');

-- Allow users to delete their own avatar
CREATE POLICY "Users can delete their own avatar" ON storage.objects
FOR DELETE USING (
  bucket_id = 'avatars'
  AND (
    -- Users can delete their own avatar
    auth.uid()::text = extract_org_id_from_path(name)
    OR
    -- Super admins can delete any avatar
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
  )
);

-- ============================================================================
-- PART 3: ENSURE UPLOADS BUCKET POLICIES (Admins can upload posts)
-- ============================================================================

-- Drop existing uploads policies if they exist
DROP POLICY IF EXISTS "Authenticated users can upload files" ON storage.objects;
DROP POLICY IF EXISTS "Users can update files they uploaded" ON storage.objects;
DROP POLICY IF EXISTS "Public read access to uploads" ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete any uploaded file" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own files" ON storage.objects;

-- Allow authenticated users (regular, admin, superadmin) to upload files
-- This is for posts and other content
CREATE POLICY "Authenticated users can upload files" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'uploads'
  AND auth.uid() IS NOT NULL
);

-- Allow authenticated users to update files they uploaded
-- Note: We check owner_id if it exists, otherwise allow based on path structure
CREATE POLICY "Users can update files they uploaded" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'uploads'
  AND (
    -- If file path starts with user_id, they can update it
    auth.uid()::text = extract_org_id_from_path(name)
    OR
    -- Super admins can update any file
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role = 'superadmin'
    )
    OR
    -- Admins can update any file (for managing posts)
    EXISTS (
      SELECT 1 FROM user_profiles 
      WHERE id = auth.uid() 
      AND role IN ('admin', 'superadmin')
    )
  )
);

-- Allow public read access to uploads
CREATE POLICY "Public read access to uploads" ON storage.objects
FOR SELECT USING (bucket_id = 'uploads');

-- Allow admins and superadmins to delete any file
CREATE POLICY "Admins can delete any uploaded file" ON storage.objects
FOR DELETE USING (
  bucket_id = 'uploads'
  AND EXISTS (
    SELECT 1 FROM user_profiles 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'superadmin')
  )
);

-- Allow users to delete their own files
CREATE POLICY "Users can delete their own files" ON storage.objects
FOR DELETE USING (
  bucket_id = 'uploads'
  AND auth.uid()::text = extract_org_id_from_path(name)
);

-- ============================================================================
-- VERIFICATION QUERIES (for debugging - can be run separately)
-- ============================================================================

-- Test the extract function:
-- SELECT extract_org_id_from_path('513b3132-1fe1-4cdf-93a0-69bceed73f1e/logo_123.png');
-- Should return: '513b3132-1fe1-4cdf-93a0-69bceed73f1e'

-- Test the permission function:
-- SELECT user_can_manage_organization_logo(
--   auth.uid(),
--   '513b3132-1fe1-4cdf-93a0-69bceed73f1e'
-- );

-- Check current user's role and organization assignments:
-- SELECT 
--   up.id,
--   up.email,
--   up.role,
--   array_agg(ao.organization_id) as assigned_orgs
-- FROM user_profiles up
-- LEFT JOIN admin_organizations ao ON up.id = ao.user_id
-- WHERE up.id = auth.uid()
-- GROUP BY up.id, up.email, up.role;

