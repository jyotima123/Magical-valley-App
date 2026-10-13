-- Allow any authenticated user to upload files
CREATE POLICY "Authenticated users can upload files" ON storage.objects
FOR INSERT WITH CHECK (
  auth.uid() IS NOT NULL
  AND bucket_id = 'uploads'
);

-- Allow any authenticated user to update files they uploaded
CREATE POLICY "Users can update files they uploaded" ON storage.objects
FOR UPDATE USING (
  auth.uid() IS NOT NULL
  AND bucket_id = 'uploads'
);

-- Allow public read access to uploads
CREATE POLICY "Public read access to uploads" ON storage.objects
FOR SELECT USING (bucket_id = 'uploads');

-- Allow admins and superadmins to delete any file
CREATE POLICY "Admins can delete any uploaded file" ON storage.objects
FOR DELETE USING (
  bucket_id = 'uploads'
  AND EXISTS (
    SELECT 1 FROM user_profiles 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'superadmin')
  )
);

-- Optional: Allow users to delete their own files (remove if not needed)
CREATE POLICY "Users can delete their own files" ON storage.objects
FOR DELETE USING (
  bucket_id = 'uploads'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
