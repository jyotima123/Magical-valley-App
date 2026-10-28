-- ============================================================================
-- ENHANCED promote_user_to_admin FUNCTION
-- This version provides better role handling and clearer logic
-- ============================================================================

-- Drop and recreate the function with enhanced role promotion logic
DROP FUNCTION IF EXISTS promote_user_to_admin(text, uuid);

CREATE OR REPLACE FUNCTION promote_user_to_admin(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
    org_name text;
BEGIN
    -- Check if user exists and get their current details
    SELECT id, role, email INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
    
    -- Check if organization exists and get its name for logging
    SELECT name INTO org_name
    FROM organizations 
    WHERE id = org_id;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Organization with ID % not found', org_id;
        RETURN false;
    END IF;
    
    -- Handle role promotion based on current role
    CASE user_record.role
        WHEN 'regular' THEN
            -- Promote regular user to admin
            UPDATE user_profiles 
            SET role = 'admin', updated_at = NOW()
            WHERE id = user_record.id;
            
            RAISE NOTICE 'User % promoted from regular to admin', user_email;
            
        WHEN 'admin' THEN
            -- User is already admin, just notify (no role change needed)
            RAISE NOTICE 'User % is already an admin (no role change needed)', user_email;
            
        WHEN 'superadmin' THEN
            -- Superadmin doesn't need promotion, just notify
            RAISE NOTICE 'User % is already a superadmin (no role change needed)', user_email;
            
        ELSE
            -- Handle any unexpected role values
            RAISE NOTICE 'User % has unexpected role: %. Cannot determine promotion action.', user_email, user_record.role;
            RETURN false;
    END CASE;
    
    -- Add the admin-organization assignment regardless of role
    -- (superadmins can also have specific organization assignments for clarity)
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (user_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO UPDATE SET
        assigned_at = NOW(),
        updated_at = NOW();
    
    RAISE NOTICE 'User % assigned as admin to organization "%" (ID: %)', user_email, org_name, org_id;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error promoting user %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ALTERNATIVE: More Restrictive Version (Only Promotes Regular Users)
-- ============================================================================

-- If you want a version that ONLY promotes regular users and doesn't assign 
-- existing admins/superadmins to new organizations, use this version instead:

CREATE OR REPLACE FUNCTION promote_regular_user_to_admin_only(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
    org_name text;
BEGIN
    -- Check if user exists and get their current details
    SELECT id, role, email INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
    
    -- Only proceed if user is currently 'regular'
    IF user_record.role != 'regular' THEN
        RAISE NOTICE 'User % already has role % (only regular users can be promoted)', 
                     user_email, user_record.role;
        RETURN false;
    END IF;
    
    -- Check if organization exists
    SELECT name INTO org_name
    FROM organizations 
    WHERE id = org_id;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Organization with ID % not found', org_id;
        RETURN false;
    END IF;
    
    -- Promote regular user to admin
    UPDATE user_profiles 
    SET role = 'admin', updated_at = NOW()
    WHERE id = user_record.id;
    
    -- Add the admin-organization assignment
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (user_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO NOTHING;
    
    RAISE NOTICE 'User % promoted from regular to admin for organization "%"', user_email, org_name;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error promoting user %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- HELPER FUNCTION: Check User Role Before Assignment
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_role_info(user_email text)
RETURNS TABLE(
    user_id uuid,
    username text,
    email text,
    user_role text,
    assigned_organizations json
) AS $func$
BEGIN
    RETURN QUERY
    SELECT 
        up.id as user_id,
        up.username,
        up.email,
        up.role as user_role,
        COALESCE(
            json_agg(
                json_build_object(
                    'org_id', o.id,
                    'org_name', o.name,
                    'assigned_at', ao.assigned_at
                )
            ) FILTER (WHERE o.id IS NOT NULL),
            '[]'::json
        ) as assigned_organizations
    FROM user_profiles up
    LEFT JOIN admin_organizations ao ON up.id = ao.user_id
    LEFT JOIN organizations o ON ao.organization_id = o.id
    WHERE up.email = user_email
    GROUP BY up.id, up.username, up.email, up.role;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Check user's current role and assignments before promoting
-- SELECT * FROM get_user_role_info('user@example.com');

-- Example 2: Promote user (handles all role types)
-- SELECT promote_user_to_admin('user@example.com', 'org-uuid-here');

-- Example 3: Only promote if user is currently regular
-- SELECT promote_regular_user_to_admin_only('user@example.com', 'org-uuid-here');

-- Example 4: Promote using organization name (existing function)
-- SELECT promote_user_to_admin_by_org_name('user@example.com', 'Organization Name');

-- ============================================================================
-- VERIFICATION QUERY
-- ============================================================================

-- Query to see the results after promotion
-- SELECT 
--     up.email,
--     up.role,
--     o.name as organization_name,
--     ao.assigned_at
-- FROM user_profiles up
-- JOIN admin_organizations ao ON up.id = ao.user_id
-- JOIN organizations o ON ao.organization_id = o.id
-- WHERE up.email = 'your-user-email-here';
