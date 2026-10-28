-- ============================================================================
-- FEEDBACK TABLE
-- Allows users to submit feedback (issues or suggestions) with optional screenshots
-- ============================================================================

-- 1. Create feedback table
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    -- Feedback content
    feedback_type VARCHAR(20) NOT NULL CHECK (feedback_type IN ('issue', 'suggestion')),
    description TEXT NOT NULL,
    screenshot_url TEXT,
    
    -- Status tracking
    status VARCHAR(20) DEFAULT 'pending' CHECK (
        status IN ('pending', 'reviewed', 'resolved', 'dismissed')
    ),
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID REFERENCES user_profiles(id)
);

-- 2. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_feedback_user_id ON feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_feedback_type ON feedback(feedback_type);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback(status);
CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback(created_at DESC);

-- 3. Add updated_at trigger
CREATE TRIGGER trigger_feedback_updated_at
    BEFORE UPDATE ON feedback
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. Enable RLS (Row Level Security)
ALTER TABLE feedback ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for feedback

-- Users can view their own feedback
CREATE POLICY "Users can view their own feedback"
    ON feedback
    FOR SELECT
    USING (auth.uid() = user_id);

-- Super admins can view all feedback
CREATE POLICY "Super admins can view all feedback"
    ON feedback
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Users can create feedback
CREATE POLICY "Users can create feedback"
    ON feedback
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own pending feedback
CREATE POLICY "Users can update their own pending feedback"
    ON feedback
    FOR UPDATE
    USING (
        auth.uid() = user_id
        AND status = 'pending'
    );

-- Super admins can update any feedback
CREATE POLICY "Super admins can update any feedback"
    ON feedback
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );

-- Users can delete their own pending feedback
CREATE POLICY "Users can delete their own pending feedback"
    ON feedback
    FOR DELETE
    USING (
        auth.uid() = user_id
        AND status = 'pending'
    );

-- Super admins can delete any feedback
CREATE POLICY "Super admins can delete any feedback"
    ON feedback
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM user_profiles
            WHERE id = auth.uid()
            AND role = 'superadmin'
        )
    );
