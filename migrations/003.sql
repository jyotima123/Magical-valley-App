-- Fix for infinite recursion in RLS policies
-- The issue is caused by circular policy dependencies

-- 1. First, drop the problematic policies
DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Superadmins can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can view posts from followed organizations" ON posts;
DROP POLICY IF EXISTS "Admins can manage their organization posts" ON posts;

DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Anyone can insert new profile during signup" ON user_profiles;



-- 2. Create SECURITY DEFINER functions to bypass RLS for role checks
-- These functions run with the privileges of the creator, not the invoker

CREATE OR REPLACE FUNCTION get_user_role(user_id uuid)
RETURNS text AS $$
BEGIN
    RETURN (SELECT role FROM user_profiles WHERE id = user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_superadmin(user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN (SELECT role FROM user_profiles WHERE id = user_id) = 'superadmin';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION is_admin_or_superadmin(user_id uuid)
RETURNS boolean AS $$
BEGIN
    RETURN (SELECT role FROM user_profiles WHERE id = user_id) IN ('admin', 'superadmin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION user_can_manage_organization(user_id uuid, org_id uuid)
RETURNS boolean AS $$
BEGIN
    -- Check if user is superadmin or admin of the specific organization
    RETURN (
        SELECT COUNT(*) > 0 
        FROM user_profiles up
        LEFT JOIN admin_organizations ao ON up.id = ao.user_id
        WHERE up.id = user_id 
        AND (up.role = 'superadmin' OR (up.role = 'admin' AND ao.organization_id = org_id))
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- 3. Recreate user_profiles policies using the SECURITY DEFINER functions
CREATE POLICY "Users can view their own profile" ON user_profiles 
FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Superadmins can view all profiles" ON user_profiles 
FOR SELECT USING (is_superadmin(auth.uid()));

CREATE POLICY "Users can update their own profile" ON user_profiles 
FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Anyone can insert new profile during signup" ON user_profiles 
FOR INSERT WITH CHECK (true);

-- 4. Fix the posts policies
CREATE POLICY "Users can view posts from followed organizations" ON posts 
FOR SELECT USING (
    status = 'active' AND (
        EXISTS (SELECT 1 FROM user_follows WHERE user_id = auth.uid() AND organization_id = posts.organization_id) OR
        is_admin_or_superadmin(auth.uid())
    )
);

CREATE POLICY "Admins can manage their organization posts" ON posts 
FOR ALL USING (
    user_can_manage_organization(auth.uid(), posts.organization_id)
);

-- 5. Fix other policies that might cause recursion
DROP POLICY IF EXISTS "Superadmins can manage all organizations" ON organizations;
CREATE POLICY "Superadmins can manage all organizations" ON organizations 
FOR ALL USING (is_superadmin(auth.uid()));

-- 6. Create a policy for admins to create posts in their organizations
CREATE POLICY "Admins can create posts for their organizations" ON posts 
FOR INSERT WITH CHECK (
    user_can_manage_organization(auth.uid(), organization_id)
);

-- 7. Update the admin_organizations policies
DROP POLICY IF EXISTS "trigger_check_user_role_for_organization" ON admin_organizations;
CREATE POLICY "Only superadmins can manage admin assignments" ON admin_organizations 
FOR ALL USING (is_superadmin(auth.uid()));

-- 8. Add a policy for request_queue
CREATE POLICY "Users can view their own requests" ON request_queue 
FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create requests" ON request_queue 
FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Superadmins can manage all requests" ON request_queue 
FOR ALL USING (is_superadmin(auth.uid()));

-- 9. Ensure organization_categories can be viewed by authenticated users
DROP POLICY IF EXISTS "Organization categories are viewable by authenticated users" ON organization_categories;
CREATE POLICY "Organization categories are viewable by authenticated users" ON organization_categories 
FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Superadmins can manage organization categories" ON organization_categories 
FOR ALL USING (is_superadmin(auth.uid()));

-- 10. Fix the constraint check functions to avoid recursion
-- Update the function that checks admin organization assignment
DROP FUNCTION IF EXISTS check_admin_organization_assignment();
CREATE OR REPLACE FUNCTION check_admin_organization_assignment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'admin' THEN
        -- Use a direct query without RLS to avoid recursion
        PERFORM 1 FROM admin_organizations WHERE user_id = NEW.id LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Admin users must be assigned to at least one organization';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
