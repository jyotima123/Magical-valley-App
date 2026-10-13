-- Allow organization admins to upload logos
CREATE POLICY "Organization admins can upload logos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'logos'
  AND EXISTS (
    SELECT 1 FROM admin_organizations ao
    WHERE ao.user_id = auth.uid()
    AND ao.organization_id::text = (storage.foldername(name))[1]
  )
);

-- Allow organization admins to update logos
CREATE POLICY "Organization admins can update logos" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'logos'
  AND EXISTS (
    SELECT 1 FROM admin_organizations ao
    WHERE ao.user_id = auth.uid()
    AND ao.organization_id::text = (storage.foldername(name))[1]
  )
);

-- Allow public read access to logos
CREATE POLICY "Public read access to logos" ON storage.objects
FOR SELECT USING (bucket_id = 'logos');

-- Allow organization admins to delete logos
CREATE POLICY "Organization admins can delete logos" ON storage.objects
FOR DELETE USING (
  bucket_id = 'logos'
  AND EXISTS (
    SELECT 1 FROM admin_organizations ao
    WHERE ao.user_id = auth.uid()
    AND ao.organization_id::text = (storage.foldername(name))[1]
  )
);
