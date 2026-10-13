-- ============================================================================
-- COMPLETE FIX FOR user_can_manage_organization FUNCTION
-- This script temporarily drops dependent policies, fixes the function, then recreates policies
-- ============================================================================

-- Step 1: Drop the policies that depend on the function
DROP POLICY IF EXISTS "Admins can manage their organization posts" ON posts;
DROP POLICY IF EXISTS "Admins can create posts for their organizations" ON posts;

-- Step 2: Drop the problematic function
DROP FUNCTION IF EXISTS user_can_manage_organization(uuid, uuid);

-- Step 3: Create the fixed function with unambiguous parameter names
CREATE OR REPLACE FUNCTION user_can_manage_organization(p_user_id uuid, p_org_id uuid)
RETURNS boolean AS $$
BEGIN
    -- Check if user is superadmin or admin of the specific organization
    RETURN (
        SELECT COUNT(*) > 0 
        FROM user_profiles up
        LEFT JOIN admin_organizations ao ON up.id = ao.user_id
        WHERE up.id = p_user_id 
        AND (up.role = 'superadmin' OR (up.role = 'admin' AND ao.organization_id = p_org_id))
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Step 4: Recreate the policies that were dropped
CREATE POLICY "Admins can manage their organization posts" ON posts 
FOR ALL USING (
    user_can_manage_organization(auth.uid(), posts.organization_id)
);

CREATE POLICY "Admins can create posts for their organizations" ON posts 
FOR INSERT WITH CHECK (
    user_can_manage_organization(auth.uid(), organization_id)
);
