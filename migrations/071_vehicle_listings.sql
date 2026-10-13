CREATE TABLE vehicle_listings (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  stock                text        NOT NULL,
  vin                  text        UNIQUE,
  year                 integer     NOT NULL,
  make                 text        NOT NULL,
  model                text        NOT NULL,
  trim                 text,
  body                 text,
  status               text        NOT NULL DEFAULT 'New',
  mileage              integer     NOT NULL DEFAULT 0,
  color                text,
  interior             text,
  transmission         text,
  speed                text,
  engine_type          text,
  fuel                 text,
  doors                text,
  price                numeric(10,2) NOT NULL,
  promotion            numeric(10,2),
  description          text,
  location             text,
  images               text,
  videos               text,
  engine_options       text,
  package_options      text,
  transmission_options text,
  addons_description   text,
  created_by           uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT vehicle_listings_stock_unique UNIQUE (stock),
  CONSTRAINT vehicle_listings_status_check CHECK (
    status IN ('New', 'Pre-Owned', 'Certified Pre-Owned')
  )
);

ALTER TABLE vehicle_listings ENABLE ROW LEVEL SECURITY;

-- All authenticated users can view listings
CREATE POLICY "Authenticated users can view vehicle listings"
  ON vehicle_listings FOR SELECT
  TO authenticated
  USING (true);

-- Admins and superadmins can insert
CREATE POLICY "Admins can insert vehicle listings"
  ON vehicle_listings FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
    )
  );

-- Admins and superadmins can update
CREATE POLICY "Admins can update vehicle listings"
  ON vehicle_listings FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role IN ('admin', 'superadmin')
    )
  );

-- Only superadmins can delete
CREATE POLICY "Superadmins can delete vehicle listings"
  ON vehicle_listings FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid() AND role = 'superadmin'
    )
  );

CREATE OR REPLACE FUNCTION _update_vehicle_listings_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER vehicle_listings_updated_at
  BEFORE UPDATE ON vehicle_listings
  FOR EACH ROW EXECUTE FUNCTION _update_vehicle_listings_updated_at();
