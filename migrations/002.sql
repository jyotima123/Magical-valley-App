-- Allow anyone to insert a new profile (for registration)
drop policy if exists "Anyone can insert new profile during signup" on user_profiles;
CREATE POLICY "Anyone can insert new profile during signup" ON user_profiles 
FOR INSERT WITH CHECK (true);

-- Users can view their own profile (after they're authenticated)
drop policy if exists "Users can view their own profile" on user_profiles;
CREATE POLICY "Users can view their own profile" ON user_profiles 
FOR SELECT USING (auth.uid() = id);

-- Users can update their own profile (after they're authenticated)  
drop policy if exists "Users can update their own profile" on user_profiles;
CREATE POLICY "Users can update their own profile" ON user_profiles 
FOR UPDATE USING (auth.uid() = id);
