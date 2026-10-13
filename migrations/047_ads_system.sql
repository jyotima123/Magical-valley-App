-- ============================================================================
-- ADS SYSTEM
-- Allows superadmins and advertisers to create, manage, and publish ads
-- Each ad has purchase info, links to external pages, images, and scheduling
-- ============================================================================

-- 1. Create ads table
CREATE TABLE IF NOT EXISTS ads (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    creator_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,

    -- Ad content
    title VARCHAR(255) NOT NULL,
    description TEXT,
    image_url TEXT NOT NULL,
    link_url TEXT NOT NULL,

    -- Scheduling
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Stripe payment information
    stripe_payment_intent_id VARCHAR(255),
    stripe_customer_id VARCHAR(255),
    amount_paid_cents INTEGER NOT NULL DEFAULT 0,
    currency VARCHAR(3) DEFAULT 'USD',
    payment_status VARCHAR(50) DEFAULT 'pending' CHECK (
        payment_status IN ('pending', 'succeeded', 'failed', 'refunded')
    ),

    -- Ad status
    status VARCHAR(50) DEFAULT 'draft' CHECK (
        status IN ('draft', 'pending_approval', 'approved', 'rejected', 'active', 'expired', 'paused')
    ),
    rejection_reason TEXT,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by UUID REFERENCES user_profiles(id),

    -- Constraints
    CONSTRAINT valid_date_range CHECK (end_date > start_date),
    CONSTRAINT valid_amount CHECK (amount_paid_cents >= 0)
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_ads_creator ON ads(creator_id);
CREATE INDEX IF NOT EXISTS idx_ads_status ON ads(status);
CREATE INDEX IF NOT EXISTS idx_ads_payment_status ON ads(payment_status);
CREATE INDEX IF NOT EXISTS idx_ads_dates ON ads(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_ads_active ON ads(status, start_date, end_date)
    WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_ads_created_at ON ads(created_at DESC);

-- 3. Add updated_at trigger
CREATE TRIGGER trigger_ads_updated_at
    BEFORE UPDATE ON ads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. Function to automatically update ad status based on dates
CREATE OR REPLACE FUNCTION update_ad_status_based_on_dates()
RETURNS void AS $$
BEGIN
    -- Set active ads to expired if their end_date has passed
    UPDATE ads
    SET status = 'expired'
    WHERE status = 'active'
    AND end_date < NOW();

    -- Set approved ads to active if their start_date has arrived
    UPDATE ads
    SET status = 'active'
    WHERE status = 'approved'
    AND start_date <= NOW()
    AND end_date > NOW()
    AND payment_status = 'succeeded';
END;
$$ LANGUAGE plpgsql;

-- 5. Enable RLS (Row Level Security)
ALTER TABLE ads ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies for ads

-- Super admins can view all ads
CREATE POLICY "Super admins can view all ads"
    ON ads
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Advertisers can view their own ads
CREATE POLICY "Advertisers can view their own ads"
    ON ads
    FOR SELECT
    USING (auth.uid() = creator_id);

-- Super admins and advertisers can create ads
CREATE POLICY "Advertisers can create ads"
    ON ads
    FOR INSERT
    WITH CHECK (
        auth.uid() = creator_id AND
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role IN ('advertiser', 'superadmin')
        )
    );

-- Advertisers can update their own ads (only if not approved/active)
CREATE POLICY "Advertisers can update their own draft ads"
    ON ads
    FOR UPDATE
    USING (
        auth.uid() = creator_id AND
        status IN ('draft', 'rejected')
    );

-- Super admins can update any ad
CREATE POLICY "Super admins can update any ad"
    ON ads
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Advertisers can delete their own draft ads
CREATE POLICY "Advertisers can delete their own draft ads"
    ON ads
    FOR DELETE
    USING (
        auth.uid() = creator_id AND
        status = 'draft'
    );

-- Super admins can delete any ad
CREATE POLICY "Super admins can delete any ad"
    ON ads
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- 7. Function to get currently active ads
CREATE OR REPLACE FUNCTION get_active_ads()
RETURNS TABLE (
    id UUID,
    title VARCHAR(255),
    description TEXT,
    image_url TEXT,
    link_url TEXT,
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    -- First update ad statuses
    PERFORM update_ad_status_based_on_dates();

    -- Return active ads
    RETURN QUERY
    SELECT
        a.id,
        a.title,
        a.description,
        a.image_url,
        a.link_url,
        a.start_date,
        a.end_date
    FROM ads a
    WHERE a.status = 'active'
    AND a.start_date <= NOW()
    AND a.end_date > NOW()
    ORDER BY a.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. View for ad analytics (super admins only)
CREATE OR REPLACE VIEW ads_analytics_view AS
SELECT
    a.id,
    a.title,
    a.creator_id,
    up.email AS creator_email,
    up.full_name AS creator_name,
    a.status,
    a.payment_status,
    a.amount_paid_cents,
    a.currency,
    a.start_date,
    a.end_date,
    a.created_at,
    a.approved_at,
    CASE
        WHEN a.status = 'active' AND a.start_date <= NOW() AND a.end_date > NOW()
        THEN true
        ELSE false
    END AS is_currently_active,
    CASE
        WHEN a.end_date < NOW()
        THEN true
        ELSE false
    END AS is_expired
FROM ads a
JOIN user_profiles up ON up.id = a.creator_id;

-- 9. Add 'advertiser' role to user_profiles if not exists
-- First, check if role column has proper constraint
DO $$
BEGIN
    -- Drop existing constraint if it exists
    ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_role_check;

    -- Add new constraint with advertiser role
    ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_role_check
    CHECK (role IN ('regular', 'admin', 'superadmin', 'advertiser'));
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not modify role constraint: %', SQLERRM;
END$$;

-- Grant public access to get active ads (for displaying in the app)
GRANT EXECUTE ON FUNCTION get_active_ads() TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_ads() TO anon;
