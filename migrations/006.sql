-- Add created_at and updated_at columns to organization_categories junction table
ALTER TABLE organization_categories 
ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add the updated_at trigger to this table as well
CREATE TRIGGER trigger_organization_categories_updated_at 
    BEFORE UPDATE ON organization_categories 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Also add timestamps to admin_organizations if they don't exist
-- (checking if the column exists first to avoid errors)
DO $$ 
BEGIN 
    -- Check if created_at column exists in admin_organizations
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'admin_organizations' 
        AND column_name = 'created_at'
    ) THEN
        ALTER TABLE admin_organizations 
        ADD COLUMN created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
    END IF;
    
    -- Check if updated_at column exists in admin_organizations  
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'admin_organizations' 
        AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE admin_organizations 
        ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
    END IF;
END $$;

-- Add the updated_at trigger to admin_organizations as well
DROP TRIGGER IF EXISTS trigger_admin_organizations_updated_at ON admin_organizations;
CREATE TRIGGER trigger_admin_organizations_updated_at 
    BEFORE UPDATE ON admin_organizations 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Update existing records to have proper timestamps (optional)
UPDATE organization_categories 
SET created_at = NOW(), updated_at = NOW() 
WHERE created_at IS NULL OR updated_at IS NULL;

UPDATE admin_organizations 
SET created_at = COALESCE(assigned_at, NOW()), updated_at = COALESCE(assigned_at, NOW()) 
WHERE created_at IS NULL OR updated_at IS NULL;
