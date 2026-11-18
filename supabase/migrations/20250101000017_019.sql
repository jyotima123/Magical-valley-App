-- added by export_supabase_migrations.py
SET search_path TO public, extensions;

CREATE POLICY "Admins can view their own organization assignments" ON admin_organizations 
FOR SELECT USING (auth.uid() = user_id)
