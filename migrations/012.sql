-- Migration to add ID field to user_follows table

-- Step 1: Drop the existing primary key constraint
ALTER TABLE user_follows DROP CONSTRAINT user_follows_pkey;

-- Step 2: Add the ID column
ALTER TABLE user_follows ADD COLUMN id UUID DEFAULT uuid_generate_v4();

-- Step 3: Update existing records to have UUIDs
UPDATE user_follows SET id = uuid_generate_v4() WHERE id IS NULL;

-- Step 4: Make ID column NOT NULL and set as primary key
ALTER TABLE user_follows ALTER COLUMN id SET NOT NULL;
ALTER TABLE user_follows ADD PRIMARY KEY (id);

-- Step 5: Add unique constraint on the composite key to maintain uniqueness
ALTER TABLE user_follows ADD CONSTRAINT user_follows_user_org_unique 
    UNIQUE (user_id, organization_id);

-- Update indexes
DROP INDEX IF EXISTS idx_user_follows_user;
DROP INDEX IF EXISTS idx_user_follows_org;
CREATE INDEX idx_user_follows_user ON user_follows(user_id);
CREATE INDEX idx_user_follows_org ON user_follows(organization_id);
CREATE INDEX idx_user_follows_composite ON user_follows(user_id, organization_id);
