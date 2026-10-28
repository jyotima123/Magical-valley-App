-- ============================================================================
-- FIX FOR POSTS VISIBILITY - Allow all users to see all active posts
-- ============================================================================

-- Step 1: Drop the existing restrictive policy
DROP POLICY IF EXISTS "Users can view posts from followed organizations" ON posts;

-- Step 2: Create a new policy that allows all authenticated users to see active posts
CREATE POLICY "All users can view active posts" ON posts 
FOR SELECT USING (
    status = 'active' AND auth.role() = 'authenticated'
);

-- Step 3: Keep the management policies as they are (these are correct)
-- Admins can manage their organization posts
-- Superadmins can manage all posts

-- Optional: If you want to also allow viewing of 'fixated' posts, use this instead:
-- CREATE POLICY "All users can view active and fixated posts" ON posts 
-- FOR SELECT USING (
--     status IN ('active', 'fixated') AND auth.role() = 'authenticated'
-- );

-- ============================================================================
-- EXPLANATION OF THE CHANGE
-- ============================================================================

-- BEFORE: Users could only see posts from organizations they follow
-- AFTER: All authenticated users can see all active posts (like a public feed)

-- The management policies remain unchanged:
-- - Only admins can create/edit posts for their assigned organizations
-- - Only superadmins can create/edit posts for any organization
-- - Regular users cannot create posts at all
