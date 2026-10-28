-- ============================================================================
-- Migration: Allow organization admins to view profiles of their org followers
-- ============================================================================
--
-- Problem: Organization admins can only see their own profile in the followers
-- list because user_profiles RLS only allows:
-- 1. Users to view their own profile
-- 2. Superadmins to view all profiles
--
-- Solution: Add a policy that allows organization admins to view profiles of
-- users who follow their organization(s).
-- ============================================================================

-- Create a SECURITY DEFINER function to check if a user is an admin of any
-- organization that the target user follows. This avoids RLS recursion issues.
CREATE OR REPLACE FUNCTION is_admin_of_follower_org(admin_user_id uuid, follower_user_id uuid)
RETURNS boolean AS $$
BEGIN
    -- Check if admin_user_id manages any organization that follower_user_id follows
    RETURN EXISTS (
        SELECT 1
        FROM admin_organizations ao
        JOIN user_follows uf ON uf.organization_id = ao.organization_id
        WHERE ao.user_id = admin_user_id
          AND uf.user_id = follower_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION is_admin_of_follower_org(uuid, uuid) TO authenticated;

-- Add policy: Organization admins can view profiles of users who follow their org
CREATE POLICY "Org admins can view follower profiles" ON user_profiles
FOR SELECT USING (
    is_admin_of_follower_org(auth.uid(), id)
);

-- ============================================================================
-- EXPLANATION
-- ============================================================================
--
-- This policy allows organization admins to see profiles of followers because:
-- 1. The function checks if the current user (admin) manages any organization
-- 2. That is also followed by the target user (the profile being viewed)
-- 3. If true, the admin can view that follower's profile
--
-- Example: If Alice is an admin of "TechCorp" and Bob follows "TechCorp",
-- Alice can now see Bob's profile in the followers list.
--
-- The SECURITY DEFINER attribute ensures the function runs with elevated
-- privileges to avoid RLS recursion issues when checking admin_organizations
-- and user_follows tables.
-- ============================================================================
