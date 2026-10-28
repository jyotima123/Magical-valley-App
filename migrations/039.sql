-- Drop the existing restrictive policy
DROP POLICY IF EXISTS "Users can view posts from followed organizations" ON posts;

-- Create new policy that allows both active AND fixated posts
CREATE POLICY "Users can view active and fixated posts from followed organizations" ON posts 
FOR SELECT USING (
    status IN ('active', 'fixated') AND (
        EXISTS (SELECT 1 FROM user_follows WHERE user_id = auth.uid() AND organization_id = posts.organization_id) OR
        is_admin_or_superadmin(auth.uid())
    )
);
