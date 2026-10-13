-- ============================================================================
-- FIX USER_PROFILES TO PROPERLY ALIGN WITH AUTH.USERS
-- ============================================================================

-- Step 1: Add auth_user_id column to explicitly store the auth.users.id
-- This makes the relationship crystal clear and improves query performance
ALTER TABLE user_profiles 
ADD COLUMN auth_user_id UUID UNIQUE;

-- Step 2: Create an index on the new column for fast lookups
CREATE INDEX idx_user_profiles_auth_user_id ON user_profiles(auth_user_id);

-- Step 3: Update existing records to populate the auth_user_id
-- This assumes your current user_profiles.id already matches auth.users.id
-- If not, you'll need a different approach based on email matching
UPDATE user_profiles 
SET auth_user_id = id 
WHERE auth_user_id IS NULL;

-- Step 4: Make the column NOT NULL after populating existing data
ALTER TABLE user_profiles 
ALTER COLUMN auth_user_id SET NOT NULL;

-- Step 5: Create a function to get user profile by auth ID (convenience)
CREATE OR REPLACE FUNCTION get_user_profile_by_auth_id(auth_id uuid)
RETURNS user_profiles AS $$
DECLARE
    profile user_profiles;
BEGIN
    SELECT * INTO profile 
    FROM user_profiles 
    WHERE auth_user_id = auth_id;
    
    RETURN profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Step 6: Create a trigger to automatically set auth_user_id on insert
CREATE OR REPLACE FUNCTION set_auth_user_id()
RETURNS TRIGGER AS $$
BEGIN
    -- If auth_user_id is not provided, use the current authenticated user's ID
    IF NEW.auth_user_id IS NULL THEN
        NEW.auth_user_id := auth.uid();
    END IF;
    
    -- Also set the id to match auth_user_id if not provided
    IF NEW.id IS NULL THEN
        NEW.id := NEW.auth_user_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_auth_user_id
    BEFORE INSERT ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION set_auth_user_id();

-- ============================================================================
-- ALTERNATIVE APPROACH: If your current user_profiles.id doesn't match auth.users.id
-- ============================================================================

-- If your existing user_profiles.id values don't match auth.users.id,
-- you'll need to populate auth_user_id based on email matching:

/*
-- First, populate auth_user_id by matching emails
UPDATE user_profiles 
SET auth_user_id = (
    SELECT au.id 
    FROM auth.users au 
    WHERE au.email = user_profiles.email
)
WHERE auth_user_id IS NULL;

-- Check for any records that couldn't be matched
SELECT email, id 
FROM user_profiles 
WHERE auth_user_id IS NULL;
*/

-- ============================================================================
-- UPDATED RLS POLICIES TO USE auth_user_id EXPLICITLY
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;

-- Recreate with explicit auth_user_id checks (clearer and potentially faster)
CREATE POLICY "Users can view their own profile" ON user_profiles 
FOR SELECT USING (auth.uid() = auth_user_id);

CREATE POLICY "Users can update their own profile" ON user_profiles 
FOR UPDATE USING (auth.uid() = auth_user_id)
WITH CHECK (auth.uid() = auth_user_id);

-- ============================================================================
-- CONVENIENCE VIEWS AND FUNCTIONS
-- ============================================================================

-- View to easily join auth and profile data
CREATE VIEW user_auth_profiles AS
SELECT 
    au.id as auth_id,
    au.email as auth_email,
    au.created_at as auth_created_at,
    au.email_confirmed_at,
    up.id as profile_id,
    up.username,
    up.full_name,
    up.profile_picture_url,
    up.role,
    up.created_at as profile_created_at,
    up.updated_at
FROM auth.users au
LEFT JOIN user_profiles up ON au.id = up.auth_user_id;

-- Function to get current user's profile (commonly used)
CREATE OR REPLACE FUNCTION get_current_user_profile()
RETURNS user_profiles AS $$
DECLARE
    profile user_profiles;
BEGIN
    SELECT * INTO profile 
    FROM user_profiles 
    WHERE auth_user_id = auth.uid();
    
    RETURN profile;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- EXAMPLE USAGE PATTERNS
-- ============================================================================

-- Instead of complex username matching, now you can:

-- 1. Get current user's profile:
-- SELECT * FROM user_profiles WHERE auth_user_id = auth.uid();

-- 2. Use the convenience function:
-- SELECT get_current_user_profile();

-- 3. Join with auth data easily:
-- SELECT * FROM user_auth_profiles WHERE auth_id = auth.uid();

-- 4. Get user profile by auth ID in application code:
-- SELECT get_user_profile_by_auth_id('some-uuid-here');

-- ============================================================================
-- MIGRATION VERIFICATION
-- ============================================================================

-- Check that all profiles have matching auth users
SELECT 
    COUNT(*) as total_profiles,
    COUNT(auth_user_id) as profiles_with_auth_id,
    COUNT(*) - COUNT(auth_user_id) as missing_auth_ids
FROM user_profiles;

-- Verify the relationship integrity
SELECT 
    up.email as profile_email,
    au.email as auth_email,
    up.auth_user_id,
    up.id as profile_id
FROM user_profiles up
LEFT JOIN auth.users au ON up.auth_user_id = au.id
WHERE au.id IS NULL; -- Should return no rows if everything is properly linked
