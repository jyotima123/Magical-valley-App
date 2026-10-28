-- ============================================================================
-- FUNCTION TO CREATE MISSING USER PROFILES
-- This function creates user_profiles for auth.users that don't have profiles yet
-- ============================================================================

-- Function to create a profile for a specific user by auth ID
CREATE OR REPLACE FUNCTION create_profile_for_auth_user(auth_user_id uuid)
RETURNS boolean AS $$
DECLARE
    auth_record RECORD;
    username_value TEXT;
    display_name TEXT;
BEGIN
    -- Get the auth user data
    SELECT id, email, raw_user_meta_data, created_at 
    INTO auth_record
    FROM auth.users 
    WHERE id = auth_user_id;
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Auth user with ID % not found', auth_user_id;
        RETURN false;
    END IF;
    
    -- Check if profile already exists
    IF EXISTS (SELECT 1 FROM public.user_profiles WHERE auth_user_id = auth_record.id) THEN
        RAISE NOTICE 'Profile already exists for user %', auth_record.email;
        RETURN false;
    END IF;
    
    -- Extract display name from user metadata
    display_name := COALESCE(
        auth_record.raw_user_meta_data->>'full_name',
        auth_record.raw_user_meta_data->>'name',
        auth_record.raw_user_meta_data->>'display_name',
        auth_record.email
    );
    
    -- Generate username from email (before @ symbol) or use a UUID-based fallback
    username_value := COALESCE(
        split_part(auth_record.email, '@', 1),
        'user_' || substring(auth_record.id::text, 1, 8)
    );
    
    -- Replace hyphens with underscores to comply with constraint
    username_value := REPLACE(username_value, '-', '_');
    
    -- Ensure username doesn't exceed 24 characters
    IF LENGTH(username_value) > 24 THEN
        username_value := LEFT(username_value, 24);
    END IF;
    
    -- Ensure username is unique by appending numbers if needed
    WHILE EXISTS (SELECT 1 FROM public.user_profiles WHERE username = username_value) LOOP
        -- Create a shorter base to make room for the suffix
        username_value := LEFT(COALESCE(
            split_part(auth_record.email, '@', 1),
            'user_' || substring(auth_record.id::text, 1, 8)
        ), 20) || '_' || floor(random() * 1000)::text;
        username_value := REPLACE(username_value, '-', '_');
    END LOOP;
    
    -- Insert the user profile
    INSERT INTO public.user_profiles (
        id,
        username,
        full_name,
        email,
        auth_user_id,
        role,
        created_at,
        updated_at
    ) VALUES (
        auth_record.id,
        username_value,
        display_name,
        auth_record.email,
        auth_record.id,
        'regular',
        auth_record.created_at,
        NOW()
    );
    
    RAISE NOTICE 'Profile created successfully for user % with username %', auth_record.email, username_value;
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating profile for user %: %', auth_record.email, SQLERRM;
        RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION TO CREATE PROFILES FOR ALL MISSING USERS
-- ============================================================================

CREATE OR REPLACE FUNCTION create_all_missing_profiles()
RETURNS TABLE(
    auth_user_id uuid,
    email text,
    success boolean,
    message text
) AS $$
DECLARE
    auth_user RECORD;
    profile_created boolean;
BEGIN
    -- Loop through all auth users who don't have profiles
    FOR auth_user IN 
        SELECT au.id, au.email 
        FROM auth.users au
        LEFT JOIN user_profiles up ON au.id = up.auth_user_id
        WHERE up.auth_user_id IS NULL
        ORDER BY au.created_at
    LOOP
        -- Create profile for this user
        SELECT create_profile_for_auth_user(auth_user.id) INTO profile_created;
        
        -- Return result for this user (cast email to TEXT to match return type)
        RETURN QUERY SELECT 
            auth_user.id as auth_user_id,
            auth_user.email::text as email,
            profile_created as success,
            CASE 
                WHEN profile_created THEN 'Profile created successfully'::text
                ELSE 'Failed to create profile'::text
            END as message;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- FUNCTION TO GET MISSING PROFILES SUMMARY
-- ============================================================================

CREATE OR REPLACE FUNCTION get_missing_profiles_summary()
RETURNS TABLE(
    total_auth_users bigint,
    total_profiles bigint,
    missing_profiles bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        (SELECT COUNT(*) FROM auth.users) as total_auth_users,
        (SELECT COUNT(*) FROM user_profiles) as total_profiles,
        (SELECT COUNT(*) 
         FROM auth.users au
         LEFT JOIN user_profiles up ON au.id = up.auth_user_id
         WHERE up.auth_user_id IS NULL) as missing_profiles;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Check how many profiles are missing:
-- SELECT * FROM get_missing_profiles_summary();

-- Create profile for a specific user:
-- SELECT create_profile_for_auth_user('your-auth-user-id-here');

-- Create profiles for all missing users:
-- SELECT * FROM create_all_missing_profiles();

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Query to see auth users without profiles:
-- SELECT 
--     au.id,
--     au.email,
--     au.created_at,
--     up.id as profile_exists
-- FROM auth.users au
-- LEFT JOIN user_profiles up ON au.id = up.auth_user_id
-- WHERE up.auth_user_id IS NULL;

-- Query to verify all profiles have corresponding auth users:
-- SELECT 
--     up.email,
--     up.username,
--     au.id as auth_exists
-- FROM user_profiles up
-- LEFT JOIN auth.users au ON up.auth_user_id = au.id
-- WHERE au.id IS NULL;


-- SELECT * FROM create_all_missing_profiles();
