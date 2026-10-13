CREATE POLICY "Admins can view their own organization assignments" ON admin_organizations 
FOR SELECT USING (auth.uid() = user_id)
