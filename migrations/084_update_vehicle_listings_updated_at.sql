  CREATE OR REPLACE FUNCTION _update_vehicle_listings_updated_at()
  RETURNS TRIGGER LANGUAGE plpgsql AS $$
  BEGIN
    IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
      NEW.updated_at = now();
    END IF;
    RETURN NEW;
  END;
  $$;
