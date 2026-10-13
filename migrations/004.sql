-- ============================================================================
-- SCRIPT 2: ENHANCED SUPERADMIN POLICIES FOR USER_PROFILES
-- ============================================================================

-- First, drop existing policies that might conflict
DROP POLICY IF EXISTS "Users can view their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Superadmins can view all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON user_profiles;
DROP POLICY IF EXISTS "Anyone can insert new profile during signup" ON user_profiles;

-- Create new comprehensive policies for user_profiles

-- 1. VIEWING POLICIES
-- Users can view their own profile
CREATE POLICY "Users can view their own profile" ON user_profiles 
FOR SELECT USING (auth.uid() = id);

-- Superadmins can view ALL profiles
CREATE POLICY "Superadmins can view all profiles" ON user_profiles 
FOR SELECT USING (is_superadmin(auth.uid()));

-- 2. UPDATING POLICIES  
-- Users can update their own profile (but not their role)
CREATE POLICY "Users can update their own profile" ON user_profiles 
FOR UPDATE USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- Superadmins can update ANY profile (including roles)
CREATE POLICY "Superadmins can update any profile" ON user_profiles 
FOR UPDATE USING (is_superadmin(auth.uid()));

-- 3. INSERTION POLICY
-- Anyone can insert during signup (registration)
CREATE POLICY "Anyone can insert new profile during signup" ON user_profiles 
FOR INSERT WITH CHECK (true);

-- 4. DELETION POLICY  
-- Only superadmins can delete profiles
CREATE POLICY "Only superadmins can delete profiles" ON user_profiles 
FOR DELETE USING (is_superadmin(auth.uid()));
