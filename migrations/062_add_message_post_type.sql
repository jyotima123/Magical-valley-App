-- Allow 'message' as a valid post_type in the posts table.
-- Posts created without a title (content-only) use this type.

ALTER TABLE posts
    DROP CONSTRAINT IF EXISTS posts_post_type_check;

ALTER TABLE posts
    ADD CONSTRAINT posts_post_type_check
    CHECK (post_type IN ('text', 'image', 'pdf', 'message'));

-- Update the file_required_for_media constraint to explicitly exclude 'message'
-- (same logic as before, but now 'message' is treated like 'text' — no file needed)
ALTER TABLE posts
    DROP CONSTRAINT IF EXISTS file_required_for_media;

ALTER TABLE posts
    ADD CONSTRAINT file_required_for_media
    CHECK (
        post_type IN ('text', 'message') OR
        (post_type IN ('image', 'pdf') AND file_url IS NOT NULL)
    );
