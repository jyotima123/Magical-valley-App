-- ============================================================================
-- FIX USER_PROFILES TO PROPERLY ALIGN WITH AUTH.USERS
-- ============================================================================

-- Step 1: Add auth_user_id column to explicitly store the auth.users.id
-- This makes the relationship crystal clear and improves query performance
-- ALTER TABLE user_profiles 
-- ADD COLUMN auth_user_id UUID UNIQUE;

-- ALTER INDEX idx_user_profiles_auth_user_id RENAME TO idx_user_profiles_id;

-- Step 2: Create an index on the new column for fast lookups
-- CREATE INDEX idx_user_profiles_auth_user_id ON user_profiles(auth_user_id);

-- Step 3: Update existing records to populate the auth_user_id
-- Match user_profiles with auth.users based on email
UPDATE user_profiles 
SET auth_user_id = (
    SELECT au.id 
    FROM auth.users au 
    WHERE au.email = user_profiles.email
)
WHERE auth_user_id IS NULL;

-- Step 4: Verify the matching worked and check for any unmatched records
-- This will show you any user_profiles that couldn't be matched with auth.users
SELECT 
    up.email as profile_email,
    up.id as profile_id,
    up.auth_user_id
FROM user_profiles up
WHERE up.auth_user_id IS NULL;
