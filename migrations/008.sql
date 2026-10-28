-- ============================================================================
-- ADMIN PROMOTION AND EMAIL CONFIRMATION FUNCTIONS
-- ============================================================================

-- Function 1: Promote a user to admin and assign them to an organization
CREATE OR REPLACE FUNCTION promote_user_to_admin(user_email text, org_id uuid)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
    rows_affected integer;
BEGIN
    -- First, check if the user exists and get their details
    SELECT id, role, email INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
    
    -- Check if the organization exists
    IF NOT EXISTS (SELECT 1 FROM organizations WHERE id = org_id) THEN
        RAISE NOTICE 'Organization with ID % not found', org_id;
        RETURN false;
    END IF;
    
    -- Update user role to admin
    UPDATE user_profiles 
    SET role = 'admin', updated_at = NOW() 
    WHERE id = user_record.id;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    IF rows_affected = 0 THEN
        RAISE NOTICE 'Failed to update user role for %', user_email;
        RETURN false;
    END IF;
    
    -- Add the admin-organization assignment (using INSERT ... ON CONFLICT to avoid duplicates)
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (user_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO NOTHING;
    
    RAISE NOTICE 'User % promoted to admin and assigned to organization % successfully', user_email, org_id;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error promoting user %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function 2: Auto-confirm email for a user (assuming Supabase auth integration)
CREATE OR REPLACE FUNCTION auto_confirm_email(user_email text)
RETURNS boolean AS $func$
DECLARE
    user_record RECORD;
    auth_user_id uuid;
BEGIN
    -- First, check if the user exists in our user_profiles table
    SELECT id, email INTO user_record 
    FROM user_profiles 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found in user_profiles', user_email;
        RETURN false;
    END IF;
    
    -- Get the auth user ID from Supabase auth.users table
    SELECT id INTO auth_user_id 
    FROM auth.users 
    WHERE email = user_email;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found in auth.users', user_email;
        RETURN false;
    END IF;
    
    -- Update the auth.users table to confirm the email
    UPDATE auth.users 
    SET 
        email_confirmed_at = NOW(),
        confirmed_at = NOW(),
        updated_at = NOW()
    WHERE id = auth_user_id;
    
    RAISE NOTICE 'Email confirmed successfully for user %', user_email;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error confirming email for user %: %', user_email, SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Promote user to admin and assign to organization
-- SELECT promote_user_to_admin('john.doe@example.com', 'org-uuid-here');

-- Example 2: Auto-confirm user's email
-- SELECT auto_confirm_email('john.doe@example.com');

-- ============================================================================
-- HELPER FUNCTION: Get organization ID by name (optional utility)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_organization_id_by_name(org_name text)
RETURNS uuid AS $func$
DECLARE
    org_id uuid;
BEGIN
    SELECT id INTO org_id 
    FROM organizations 
    WHERE name = org_name;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Organization with name % not found', org_name;
        RETURN NULL;
    END IF;
    
    RETURN org_id;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Example usage with helper function:
-- SELECT promote_user_to_admin('john.doe@example.com', get_organization_id_by_name('Acme Corporation'));

-- ============================================================================
-- COMBINED FUNCTION: Promote to admin by organization name (convenience function)
-- ============================================================================

CREATE OR REPLACE FUNCTION promote_user_to_admin_by_org_name(user_email text, org_name text)
RETURNS boolean AS $func$
DECLARE
    org_id uuid;
BEGIN
    -- Get organization ID by name
    org_id := get_organization_id_by_name(org_name);
    
    IF org_id IS NULL THEN
        RETURN false;
    END IF;
    
    -- Use the main promotion function
    RETURN promote_user_to_admin(user_email, org_id);
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;

-- Example usage:
-- SELECT promote_user_to_admin_by_org_name('john.doe@example.com', 'Acme Corporation');
