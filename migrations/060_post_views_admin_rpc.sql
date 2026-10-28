-- Migration 060: Add RPC function for admins/superadmins to read post views
-- Needed for QA Post Views debug screen (post_views has RLS with no SELECT policy)

-- Returns all views for a given post, callable by org admins and superadmins.
-- SECURITY DEFINER bypasses RLS so the function itself reads all rows,
-- but the body enforces that only admins/superadmins can invoke it.
CREATE OR REPLACE FUNCTION get_post_views(p_post_id UUID)
RETURNS TABLE (
    id UUID,
    user_id UUID,
    post_id UUID,
    viewed_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_role TEXT;
    v_org_id UUID;
BEGIN
    -- Resolve caller role
    SELECT role INTO v_caller_role
    FROM user_profiles
    WHERE user_profiles.id = auth.uid();

    -- Resolve the organization that owns this post
    SELECT organization_id INTO v_org_id
    FROM posts
    WHERE posts.id = p_post_id;

    -- Allow superadmins unconditionally;
    -- allow org admins only for posts in their organization
    IF v_caller_role = 'superadmin' OR (
        v_caller_role = 'admin' AND EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE admin_organizations.user_id = auth.uid()
              AND admin_organizations.organization_id = v_org_id
        )
    ) THEN
        RETURN QUERY
            SELECT pv.id, pv.user_id, pv.post_id, pv.viewed_at
            FROM post_views pv
            WHERE pv.post_id = p_post_id
            ORDER BY pv.viewed_at DESC;
    ELSE
        RAISE EXCEPTION 'Access denied: superadmin or org admin required';
    END IF;
END;
$$;
