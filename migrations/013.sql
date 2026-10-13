-- ============================================================================
-- FIX FOR USER_FOLLOWS VISIBILITY - Allow users to see all follows for proper follower counts
-- ============================================================================

-- Step 1: Drop the existing overly restrictive policy
DROP POLICY IF EXISTS "Users can manage their own follows" ON user_follows;

-- Step 2: Create separate policies for different operations

-- Policy 1: All authenticated users can VIEW all following relationships
-- This allows users to see follower counts and who follows what
CREATE POLICY "Users can view all follows" ON user_follows 
FOR SELECT USING (auth.role() = 'authenticated');

-- Policy 2: Users can only INSERT their own follows (follow organizations)
CREATE POLICY "Users can create their own follows" ON user_follows 
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Policy 3: Users can only DELETE their own follows (unfollow organizations)
CREATE POLICY "Users can delete their own follows" ON user_follows 
FOR DELETE USING (auth.uid() = user_id);

-- Policy 4: Users can only UPDATE their own follows (if needed)
CREATE POLICY "Users can update their own follows" ON user_follows 
FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================================
-- EXPLANATION OF THE CHANGES
-- ============================================================================

-- BEFORE: 
-- - Users could only see their own follows
-- - Follower counts appeared as 1 because you could only see your own follow

-- AFTER:
-- - All users can see all following relationships (for proper follower counts)
-- - Users can still only follow/unfollow for themselves
-- - Privacy is maintained (users can see WHO follows WHAT, but this is typical for social platforms)

-- ============================================================================
-- ALTERNATIVE: If you want more privacy, you can use this policy instead
-- ============================================================================

-- If you don't want users to see WHO follows what, but still want accurate follower counts,
-- you could create a view that shows only aggregate data:

CREATE VIEW public_follower_counts AS
SELECT
    organization_id,
    COUNT(*) as follower_count
FROM user_follows
GROUP BY organization_id;

-- Then allow users to query this view instead of the raw table
GRANT SELECT ON public_follower_counts TO authenticated;
