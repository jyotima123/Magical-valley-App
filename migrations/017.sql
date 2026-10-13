-- ============================================================================
-- MULTIPLE USERS ADMIN ASSIGNMENT FUNCTION
-- ============================================================================

-- Function to promote multiple users to admin for a single organization
CREATE OR REPLACE FUNCTION promote_multiple_users_to_admin(
    user_emails text[], 
    org_id uuid
)
RETURNS TABLE(
    email text,
    success boolean,
    message text
) AS $func$
DECLARE
    user_email text;
    result_record RECORD;
    promotion_success boolean;
BEGIN
    -- Check if organization exists first
    IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = org_id) THEN
        RETURN QUERY SELECT 
            'N/A'::text as email,
            false as success,
            format('Organization with ID %s not found', org_id) as message;
        RETURN;
    END IF;
    
    -- Loop through each email
    FOREACH user_email IN ARRAY user_emails
    LOOP
        -- Use the existing single user promotion function
        SELECT promote_user_to_admin(user_email, org_id) INTO promotion_success;
        
        -- Return result for this user
        RETURN QUERY SELECT 
            user_email as email,
            promotion_success as success,
            CASE 
                WHEN promotion_success THEN 'Successfully promoted to admin'
                ELSE 'Failed to promote to admin'
            END as message;
    END LOOP;
    
    RETURN;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to promote multiple users to admin using organization name
CREATE OR REPLACE FUNCTION promote_multiple_users_to_admin_by_org_name(
    user_emails text[], 
    org_name text
)
RETURNS TABLE(
    email text,
    success boolean,
    message text
) AS $func$
DECLARE
    org_id uuid;
BEGIN
    -- Get organization ID by name
    org_id := get_organization_id_by_name(org_name);
    
    IF org_id IS NULL THEN
        RETURN QUERY SELECT 
            'N/A'::text as email,
            false as success,
            format('Organization with name "%s" not found', org_name) as message;
        RETURN;
    END IF;
    
    -- Use the UUID-based function
    RETURN QUERY SELECT * FROM promote_multiple_users_to_admin(user_emails, org_id);
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Promote multiple users using organization UUID
-- SELECT * FROM promote_multiple_users_to_admin(
--     ARRAY['user1@example.com', 'user2@example.com', 'user3@example.com'],
--     'your-org-uuid-here'
-- );

-- Example 2: Promote multiple users using organization name
-- SELECT * FROM promote_multiple_users_to_admin_by_org_name(
--     ARRAY['user1@example.com', 'user2@example.com', 'user3@example.com'],
--     'Your Organization Name'
-- );

-- ============================================================================
-- ADDITIONAL UTILITY FUNCTIONS
-- ============================================================================

-- Function to assign existing admin to additional organization (doesn't change role)
CREATE OR REPLACE FUNCTION assign_admin_to_organization(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
BEGIN
    -- Check if user exists and is already an admin
    SELECT id, role INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
    
    IF user_record.role NOT IN ('admin', 'superadmin') THEN
        RAISE NOTICE 'User % is not an admin (current role: %)', user_email, user_record.role;
        RETURN false;
    END IF;
    
    -- Check if organization exists
    IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = org_id) THEN
        RAISE NOTICE 'Organization with ID % not found', org_id;
        RETURN false;
    END IF;
    
    -- Add the admin-organization assignment
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (user_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO NOTHING;
    
    RAISE NOTICE 'Admin % assigned to organization % successfully', user_email, org_id;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error assigning admin %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to remove admin from organization assignment
CREATE OR REPLACE FUNCTION remove_admin_from_organization(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
    remaining_orgs integer;
BEGIN
    -- Get user details
    SELECT id, role INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
    
    -- Check if user is admin of this organization
    IF NOT EXISTS (
        SELECT 1 FROM admin_organizations 
        WHERE user_id = user_record.id AND organization_id = org_id
    ) THEN
        RAISE NOTICE 'User % is not assigned to organization %', user_email, org_id;
        RETURN false;
    END IF;
    
    -- Count remaining organizations after removal
    SELECT COUNT(*) - 1 INTO remaining_orgs
    FROM admin_organizations 
    WHERE user_id = user_record.id;
    
    -- If this is the last organization and user is admin (not superadmin), 
    -- they need to be demoted to regular user
    IF remaining_orgs = 0 AND user_record.role = 'admin' THEN
        -- Remove from organization
        DELETE FROM admin_organizations 
        WHERE user_id = user_record.id AND organization_id = org_id;
        
        -- Demote to regular user
        UPDATE user_profiles 
        SET role = 'regular', updated_at = NOW()
        WHERE id = user_record.id;
        
        RAISE NOTICE 'User % removed from organization and demoted to regular user', user_email;
    ELSE
        -- Just remove from organization
        DELETE FROM admin_organizations 
        WHERE user_id = user_record.id AND organization_id = org_id;
        
        RAISE NOTICE 'User % removed from organization (still admin of % other organizations)', 
                     user_email, remaining_orgs;
    END IF;
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error removing admin %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
