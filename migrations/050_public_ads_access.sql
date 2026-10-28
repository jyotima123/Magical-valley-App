-- ============================================================================
-- PUBLIC ADS ACCESS
-- Allows public/anonymous users to view active ads
-- This is necessary for displaying ads in the main app chat feed
-- ============================================================================

-- Add policy to allow anyone to view active ads
CREATE POLICY "Anyone can view active ads"
    ON ads
    FOR SELECT
    USING (
        status = 'active'
        AND payment_status = 'succeeded'
        AND start_date <= NOW()
        AND end_date >= NOW()
    );

-- Grant anonymous users access to view ads
GRANT SELECT ON ads TO anon;
GRANT SELECT ON ads TO authenticated;
