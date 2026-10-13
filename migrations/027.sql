-- Drop the existing constraint
ALTER TABLE user_profiles DROP CONSTRAINT username_format;

-- Add new constraint that allows hyphens
ALTER TABLE user_profiles ADD CONSTRAINT username_format CHECK (
    username ~ '^[a-zA-Z0-9_@.+-]{3,24}$' OR
    username ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
)
