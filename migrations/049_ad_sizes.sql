-- ============================================================================
-- AD SIZES
-- Defines standard ad sizes that users can choose from when creating ads
-- Includes common IAB standard ad sizes for both desktop and mobile
-- ============================================================================

-- 1. Create ad_sizes table
CREATE TABLE IF NOT EXISTS ad_sizes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT true,
    display_order INTEGER DEFAULT 0,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Constraints
    CONSTRAINT valid_dimensions CHECK (width > 0 AND height > 0),
    CONSTRAINT unique_dimensions UNIQUE (width, height)
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ad_sizes_active ON ad_sizes(is_active, display_order);
CREATE INDEX IF NOT EXISTS idx_ad_sizes_dimensions ON ad_sizes(width, height);

-- 3. Add updated_at trigger
CREATE TRIGGER trigger_ad_sizes_updated_at
    BEFORE UPDATE ON ad_sizes
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. Insert standard ad sizes
INSERT INTO ad_sizes (name, width, height, display_order) VALUES
    -- Desktop/Tablet ad sizes
    ('Medium Rectangle', 300, 250, 1),
    ('Leaderboard', 728, 90, 2),
    ('Half-Page', 300, 600, 3),
    ('Large Rectangle', 336, 280, 4),
    ('Wide Skyscraper', 160, 600, 5),
    ('Billboard', 970, 250, 6),
    ('Portrait', 300, 1050, 7),

    -- Mobile ad sizes
    ('Mobile Banner', 300, 50, 10),
    ('Large Mobile Banner', 320, 100, 11),
    ('Mobile Leaderboard', 320, 50, 12)
ON CONFLICT (width, height) DO NOTHING;

-- 5. Add ad_size_id to ads table
ALTER TABLE ads ADD COLUMN IF NOT EXISTS ad_size_id UUID REFERENCES ad_sizes(id);

-- 6. Create index on ads.ad_size_id
CREATE INDEX IF NOT EXISTS idx_ads_size ON ads(ad_size_id);

-- 7. Enable RLS (Row Level Security)
ALTER TABLE ad_sizes ENABLE ROW LEVEL SECURITY;

-- 8. RLS Policies for ad_sizes

-- Everyone can view active ad sizes (for selection when creating ads)
CREATE POLICY "Anyone can view active ad sizes"
    ON ad_sizes
    FOR SELECT
    USING (is_active = true);

-- Super admins can view all ad sizes
CREATE POLICY "Super admins can view all ad sizes"
    ON ad_sizes
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Super admins can insert new ad sizes
CREATE POLICY "Super admins can insert ad sizes"
    ON ad_sizes
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Super admins can update ad sizes
CREATE POLICY "Super admins can update ad sizes"
    ON ad_sizes
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Super admins can delete ad sizes (only if not referenced by any ads)
CREATE POLICY "Super admins can delete ad sizes"
    ON ad_sizes
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- 9. Create view for ad sizes with usage count
CREATE OR REPLACE VIEW ad_sizes_with_usage AS
SELECT
    ads.id,
    ads.name,
    ads.width,
    ads.height,
    ads.is_active,
    ads.display_order,
    ads.created_at,
    COUNT(a.id) AS ads_count
FROM ad_sizes ads
LEFT JOIN ads a ON a.ad_size_id = ads.id
GROUP BY ads.id, ads.name, ads.width, ads.height, ads.is_active, ads.display_order, ads.created_at
ORDER BY ads.display_order, ads.name;
