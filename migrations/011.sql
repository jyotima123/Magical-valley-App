ALTER TABLE user_follows 
ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Update existing records to have the same timestamp as followed_at
UPDATE user_follows 
SET created_at = followed_at 
WHERE created_at IS NULL;

-- Add the updated_at column for consistency
ALTER TABLE user_follows 
ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add the update trigger
CREATE TRIGGER trigger_user_follows_updated_at 
    BEFORE UPDATE ON user_follows 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
