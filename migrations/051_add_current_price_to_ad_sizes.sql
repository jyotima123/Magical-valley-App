-- ============================================================================
-- AD SIZES: CURRENT PRICE
-- Adds a column to store the current subscription price for each ad size
-- Price is stored in cents as an integer to avoid floating point issues
-- ============================================================================

-- 1. Add current_price column to ad_sizes table
ALTER TABLE ad_sizes
ADD COLUMN IF NOT EXISTS current_price INTEGER NOT NULL DEFAULT 0;


ALTER TABLE ad_sizes
    ALTER current_price TYPE double precision USING current_price::numeric::double precision