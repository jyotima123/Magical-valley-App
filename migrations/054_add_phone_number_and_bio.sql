-- Migration 054: Add phone_number and bio columns to user_profiles
-- Required for SMS/phone verification as alternative to email verification

ALTER TABLE user_profiles ADD COLUMN phone_number VARCHAR(20) UNIQUE;
ALTER TABLE user_profiles ADD COLUMN bio TEXT;

-- Index for phone number lookups (partial index, only non-null values)
CREATE INDEX idx_user_profiles_phone_number
  ON user_profiles (phone_number)
  WHERE phone_number IS NOT NULL;
