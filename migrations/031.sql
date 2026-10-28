-- SOLUTION 1: Temporarily disable the trigger for deletion
-- Run this BEFORE deleting the organization
ALTER TABLE organization_categories DISABLE TRIGGER trigger_check_organization_category;

-- Now delete your organization (this will cascade delete the category relationships)
-- DELETE FROM organizations WHERE id = 'your-organization-id-here';

-- Re-enable the trigger after deletion
ALTER TABLE organization_categories ENABLE TRIGGER trigger_check_organization_category;

-- ============================================================================

-- SOLUTION 2: Delete in the correct order manually
-- First, delete all related records, then the organization

-- Replace 'your-organization-id-here' with the actual organization ID
-- DELETE FROM posts WHERE organization_id = 'your-organization-id-here';
-- DELETE FROM user_follows WHERE organization_id = 'your-organization-id-here';
-- DELETE FROM admin_organizations WHERE organization_id = 'your-organization-id-here';
-- DELETE FROM organization_categories WHERE organization_id = 'your-organization-id-here';
-- DELETE FROM organizations WHERE id = 'your-organization-id-here';

-- ============================================================================

-- SOLUTION 3: Fix the trigger logic (RECOMMENDED)
-- Replace the existing trigger with a better one that allows deletion when the organization itself is being deleted

-- Drop the problematic function and trigger
DROP TRIGGER IF EXISTS trigger_check_organization_category ON organization_categories;
DROP FUNCTION IF EXISTS check_organization_category();

-- Create a better function that only prevents deletion if the organization still exists
CREATE OR REPLACE FUNCTION check_organization_category()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Only check if the organization still exists (not being deleted)
        IF EXISTS (SELECT 1 FROM organizations WHERE id = OLD.organization_id) THEN
            -- Check if organization would have no categories after delete
            IF NOT EXISTS (
                SELECT 1 FROM organization_categories 
                WHERE organization_id = OLD.organization_id 
                AND category_id != OLD.category_id
            ) THEN
                RAISE EXCEPTION 'Organization must belong to at least one category';
            END IF;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
CREATE TRIGGER trigger_check_organization_category
    BEFORE DELETE ON organization_categories
    FOR EACH ROW EXECUTE FUNCTION check_organization_category();
