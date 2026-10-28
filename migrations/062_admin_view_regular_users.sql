-- Allow admins and superadmins to query all regular-role user profiles.
-- Needed by UserSelectorScreen when an admin starts a new Direct Message conversation.
--
-- A plain policy that queries user_profiles inside its own USING clause causes
-- infinite recursion, so we follow the same pattern as is_superadmin() and
-- wrap the role lookup in a SECURITY DEFINER function.

CREATE OR REPLACE FUNCTION is_admin_or_superadmin(user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN (SELECT role FROM user_profiles WHERE id = user_id) IN ('admin', 'superadmin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

GRANT EXECUTE ON FUNCTION is_admin_or_superadmin(uuid) TO authenticated;

-- Admins and superadmins may SELECT rows where role = 'regular'.
-- The role = 'regular' guard is part of the USING expression, so admins
-- cannot use this policy to read other admin/superadmin profiles.
CREATE POLICY "Admins can view regular user profiles" ON user_profiles
FOR SELECT USING (
    role = 'regular'
    AND is_admin_or_superadmin(auth.uid())
);
