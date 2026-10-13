-- ============================================================================
-- POST REACTIONS TABLE
-- Allows users to react to posts with emojis (one reaction per user per post)
-- ============================================================================

-- 1. Create the post_reactions table
CREATE TABLE post_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
    emoji_reactions TEXT[] NOT NULL, -- Array of emoji strings like ['👍', '❤️', '😂']
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Unique constraint: one reaction record per user per post
    UNIQUE(post_id, user_id),
    
    -- Ensure at least one emoji is provided
    CONSTRAINT at_least_one_emoji CHECK (array_length(emoji_reactions, 1) > 0),
    
    -- Ensure no duplicate emojis in the same reaction
    CONSTRAINT no_duplicate_emojis CHECK (
        array_length(emoji_reactions, 1) = 
        array_length(array(SELECT DISTINCT unnest(emoji_reactions)), 1)
    )
);

-- 2. Create indexes for performance
CREATE INDEX idx_post_reactions_post ON post_reactions(post_id);
CREATE INDEX idx_post_reactions_user ON post_reactions(user_id);
CREATE INDEX idx_post_reactions_created_at ON post_reactions(created_at DESC);

-- 3. Add updated_at trigger
CREATE TRIGGER trigger_post_reactions_updated_at 
    BEFORE UPDATE ON post_reactions 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. RLS Policies for post_reactions

-- Enable RLS
ALTER TABLE post_reactions ENABLE ROW LEVEL SECURITY;

-- Users can view all reactions (to show reaction counts)
CREATE POLICY "Users can view all post reactions" ON post_reactions 
FOR SELECT USING (auth.role() = 'authenticated');

-- Users can create their own reactions
CREATE POLICY "Users can create their own reactions" ON post_reactions 
FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own reactions
CREATE POLICY "Users can update their own reactions" ON post_reactions 
FOR UPDATE USING (auth.uid() = user_id);

-- Users can delete their own reactions
CREATE POLICY "Users can delete their own reactions" ON post_reactions 
FOR DELETE USING (auth.uid() = user_id);

-- ============================================================================
-- CATEGORY ORGANIZATION COUNTS VIEW
-- Provides a count of organizations per category
-- ============================================================================

-- Create the view for category organization counts
CREATE VIEW category_organization_counts AS
SELECT 
    c.id as category_id,
    c.name as category_name,
    c.description as category_description,
    COUNT(oc.organization_id) as organization_count
FROM categories c
LEFT JOIN organization_categories oc ON c.id = oc.category_id
GROUP BY c.id, c.name, c.description
ORDER BY organization_count DESC, c.name;

-- Grant access to the view
GRANT SELECT ON category_organization_counts TO authenticated;

-- ============================================================================
-- POST REACTIONS AGGREGATION VIEWS
-- Helpful views for displaying reaction statistics
-- ============================================================================

-- View for post reaction summaries (total reactions per post)
CREATE VIEW post_reaction_summary AS
SELECT 
    p.id as post_id,
    p.title,
    p.organization_id,
    COUNT(pr.id) as total_users_reacted,
    COUNT(unnest(pr.emoji_reactions)) as total_emoji_reactions,
    array_agg(DISTINCT unnest(pr.emoji_reactions)) as unique_emojis_used
FROM posts p
LEFT JOIN post_reactions pr ON p.id = pr.post_id
GROUP BY p.id, p.title, p.organization_id;

-- View for individual emoji counts per post
CREATE VIEW post_emoji_counts AS
WITH emoji_expanded AS (
    SELECT 
        post_id,
        unnest(emoji_reactions) as emoji
    FROM post_reactions
)
SELECT 
    post_id,
    emoji,
    COUNT(*) as count
FROM emoji_expanded
GROUP BY post_id, emoji
ORDER BY post_id, count DESC;

-- Grant access to the views
GRANT SELECT ON post_reaction_summary TO authenticated;
GRANT SELECT ON post_emoji_counts TO authenticated;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get category counts as a JSON object (id -> count mapping)
CREATE OR REPLACE FUNCTION get_category_counts_json()
RETURNS jsonb AS $$
BEGIN
    RETURN (
        SELECT jsonb_object_agg(category_id::text, organization_count)
        FROM category_organization_counts
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to add/update a user's reaction to a post
CREATE OR REPLACE FUNCTION upsert_post_reaction(
    p_post_id uuid,
    p_user_id uuid,
    p_emoji_reactions text[]
)
RETURNS boolean AS $$
BEGIN
    -- Validate that emojis array is not empty
    IF array_length(p_emoji_reactions, 1) IS NULL OR array_length(p_emoji_reactions, 1) = 0 THEN
        RAISE EXCEPTION 'At least one emoji reaction is required';
    END IF;
    
    -- Validate that there are no duplicate emojis
    IF array_length(p_emoji_reactions, 1) != 
       array_length(array(SELECT DISTINCT unnest(p_emoji_reactions)), 1) THEN
        RAISE EXCEPTION 'Duplicate emojis are not allowed in the same reaction';
    END IF;
    
    -- Insert or update the reaction
    INSERT INTO post_reactions (post_id, user_id, emoji_reactions)
    VALUES (p_post_id, p_user_id, p_emoji_reactions)
    ON CONFLICT (post_id, user_id)
    DO UPDATE SET 
        emoji_reactions = EXCLUDED.emoji_reactions,
        updated_at = NOW();
    
    RETURN true;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error upserting reaction: %', SQLERRM;
        RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to remove a user's reaction from a post
CREATE OR REPLACE FUNCTION remove_post_reaction(
    p_post_id uuid,
    p_user_id uuid
)
RETURNS boolean AS $$
DECLARE
    rows_affected integer;
BEGIN
    DELETE FROM post_reactions 
    WHERE post_id = p_post_id AND user_id = p_user_id;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    RETURN rows_affected > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Get category organization counts as a simple view
-- SELECT * FROM category_organization_counts;

-- Example 2: Get category counts as JSON object (id -> count mapping)
-- SELECT get_category_counts_json();

-- Example 3: Add/update a user's reaction to a post
-- SELECT upsert_post_reaction(
--     'post-uuid-here'::uuid,
--     auth.uid(),
--     ARRAY['👍', '❤️', '🔥']
-- );

-- Example 4: Remove a user's reaction from a post
-- SELECT remove_post_reaction('post-uuid-here'::uuid, auth.uid());

-- Example 5: Get reaction summary for a specific post
-- SELECT * FROM post_reaction_summary WHERE post_id = 'post-uuid-here';

-- Example 6: Get individual emoji counts for a specific post
-- SELECT * FROM post_emoji_counts WHERE post_id = 'post-uuid-here';

-- ============================================================================
-- SAMPLE DATA FOR TESTING (OPTIONAL)
-- ============================================================================

-- Uncomment to insert sample reactions for testing:
/*
-- Sample reactions (replace with actual post and user IDs)
INSERT INTO post_reactions (post_id, user_id, emoji_reactions) VALUES
    ('sample-post-id-1', 'sample-user-id-1', ARRAY['👍', '❤️']),
    ('sample-post-id-1', 'sample-user-id-2', ARRAY['😂', '🔥']),
    ('sample-post-id-1', 'sample-user-id-3', ARRAY['👍']),
    ('sample-post-id-2', 'sample-user-id-1', ARRAY['❤️', '🎉']);
*/
