-- ============================================================================
-- NOTIFICATION PREFERENCES TABLE
-- ============================================================================
-- This table stores user notification preferences per channel

CREATE TABLE IF NOT EXISTS notification_preferences (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  notifications_enabled boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE(user_id, channel_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user_channel 
  ON notification_preferences(user_id, channel_id);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_channel 
  ON notification_preferences(channel_id) 
  WHERE notifications_enabled = true;

-- Enable RLS
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Users can read their own preferences
DROP POLICY IF EXISTS "Users can view their own notification preferences" ON notification_preferences;
CREATE POLICY "Users can view their own notification preferences" 
  ON notification_preferences
  FOR SELECT 
  USING (auth.uid() = user_id);

-- Users can insert their own preferences
DROP POLICY IF EXISTS "Users can insert their own notification preferences" ON notification_preferences;
CREATE POLICY "Users can insert their own notification preferences" 
  ON notification_preferences
  FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own preferences
DROP POLICY IF EXISTS "Users can update their own notification preferences" ON notification_preferences;
CREATE POLICY "Users can update their own notification preferences" 
  ON notification_preferences
  FOR UPDATE 
  USING (auth.uid() = user_id);

-- Service role can read all (for edge function)
DROP POLICY IF EXISTS "Service role can read all preferences" ON notification_preferences;
CREATE POLICY "Service role can read all preferences" 
  ON notification_preferences
  FOR SELECT 
  USING (true);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get users who should receive notifications for a channel
CREATE OR REPLACE FUNCTION get_notification_recipients(channel_id_param uuid)
RETURNS TABLE (
  user_id uuid,
  fcm_token text
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    om.user_id,
    up.fcm_token
  FROM organization_members om
  INNER JOIN user_profiles up ON om.user_id = up.id
  LEFT JOIN notification_preferences np ON (
    np.user_id = om.user_id AND 
    np.channel_id = channel_id_param
  )
  WHERE 
    om.organization_id = channel_id_param
    AND om.status = 'active'
    AND up.fcm_token IS NOT NULL
    AND up.fcm_token != ''
    -- If no preference exists, default to enabled (true)
    -- If preference exists, use its value
    AND COALESCE(np.notifications_enabled, true) = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_notification_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at
DROP TRIGGER IF EXISTS notification_preferences_updated_at ON notification_preferences;
CREATE TRIGGER notification_preferences_updated_at
  BEFORE UPDATE ON notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_notification_preferences_updated_at();

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
-- After running this script:
-- 1. Make sure the 'organizations' and 'organization_members' tables exist
-- 2. Ensure 'user_profiles' table has an 'fcm_token' column
-- 3. Update the Edge Function to use get_notification_recipients()
-- ============================================================================
