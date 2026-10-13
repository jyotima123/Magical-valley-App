DROP POLICY IF EXISTS "Public read access to logos"  ON storage.objects;

-- ============================================================================
-- FIXED STORAGE POLICIES FOR LOGOS BUCKET
-- This script fixes the RLS issues preventing logo uploads
-- ============================================================================

-- First, drop the existing problematic policies
DROP POLICY IF EXISTS "Organization admins can upload logos" ON storage.objects;
DROP POLICY IF EXISTS "Organization admins can update logos" ON storage.objects;
DROP POLICY IF EXISTS "Organization admins can delete logos" ON storage.objects;
DROP FUNCTION user_can_manage_organization_logo(uuid,text);

-- Create a SECURITY DEFINER function to check organization admin privileges
-- This bypasses RLS when checking admin permissions
CREATE OR REPLACE FUNCTION user_can_manage_organization_logo(p_user_id uuid, org_id_text text)
RETURNS boolean AS $$
DECLARE
    org_uuid uuid;
BEGIN
    -- Convert text to UUID
    BEGIN
        org_uuid := org_id_text::uuid;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RETURN false;
    END;
    
    -- Check if user is superadmin or admin of the specific organization
    RETURN (
        SELECT COUNT(*) > 0 
        FROM user_profiles up
        LEFT JOIN admin_organizations ao ON up.id = ao.user_id
        WHERE up.id = p_user_id 
        AND (up.role = 'superadmin' OR (up.role = 'admin' AND ao.organization_id = org_uuid))
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Create new storage policies using the SECURITY DEFINER function

-- 1. Allow organization admins to upload logos
CREATE POLICY "Organization admins can upload logos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'logos'
  AND user_can_manage_organization_logo(auth.uid(), (storage.foldername(name))[1])
);

-- 2. Allow organization admins to update logos
CREATE POLICY "Organization admins can update logos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'logos'
  AND user_can_manage_organization_logo(auth.uid(), (storage.foldername(name))[1])
);

-- 3. Allow public read access to logos (unchanged)
CREATE POLICY "Public read access to logos" ON storage.objects
FOR SELECT USING (bucket_id = 'logos');

-- 4. Allow organization admins to delete logos
CREATE POLICY "Organization admins can delete logos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'logos'
  AND user_can_manage_organization_logo(auth.uid(), (storage.foldername(name))[1])
);

-- ============================================================================
-- ALTERNATIVE SIMPLER APPROACH (if the above still has issues)
-- This gives broader permissions but is more reliable
-- ============================================================================

-- If the function-based approach still has issues, you can use this simpler approach:

-- Drop existing policies
-- DROP POLICY IF EXISTS "Organization admins can upload logos" ON storage.objects;
-- DROP POLICY IF EXISTS "Organization admins can update logos" ON storage.objects;
-- DROP POLICY IF EXISTS "Organization admins can delete logos" ON storage.objects;

-- Allow all admins and superadmins to upload logos to any organization folder
-- CREATE POLICY "Admins can upload logos" ON storage.objects
-- FOR INSERT WITH CHECK (
--   bucket_id = 'logos'
--   AND EXISTS (
--     SELECT 1 FROM user_profiles 
--     WHERE id = auth.uid() 
--     AND role IN ('admin', 'superadmin')
--   )
-- );

-- CREATE POLICY "Admins can update logos" ON storage.objects
-- FOR UPDATE USING (
--   bucket_id = 'logos'
--   AND EXISTS (
--     SELECT 1 FROM user_profiles 
--     WHERE id = auth.uid() 
--     AND role IN ('admin', 'superadmin')
--   )
-- );

-- CREATE POLICY "Admins can delete logos" ON storage.objects
-- FOR DELETE USING (
--   bucket_id = 'logos'
--   AND EXISTS (
--     SELECT 1 FROM user_profiles 
--     WHERE id = auth.uid() 
--     AND role IN ('admin', 'superadmin')
--   )
-- );

-- ============================================================================
-- DEBUGGING QUERIES
-- ============================================================================

-- Test the function manually (replace with your actual user ID and org ID)
-- SELECT user_can_manage_organization_logo(
--   'your-user-id-here'::uuid, 
--   '6b712a83-7782-441d-ad5e-0f09b895ec3f'
-- );

-- Check current user's role and organization assignments
-- SELECT 
--   up.id,
--   up.email,
--   up.role,
--   array_agg(ao.organization_id) as assigned_orgs
-- FROM user_profiles up
-- LEFT JOIN admin_organizations ao ON up.id = ao.user_id
-- WHERE up.id = auth.uid()
-- GROUP BY up.id, up.email, up.role;

-- Verify the specific organization exists
-- SELECT id, name FROM organizations WHERE id = '6b712a83-7782-441d-ad5e-0f09b895ec3f';
