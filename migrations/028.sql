-- Drop and recreate the function with proper username formatting
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    username_value TEXT;
    display_name TEXT;
BEGIN
    -- Extract display name from user metadata
    display_name := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'name', 
        NEW.email
    );
    
    -- Generate username from email (before @ symbol) or use a UUID-based fallback
    username_value := COALESCE(
        split_part(NEW.email, '@', 1),
        'user_' || substring(NEW.id::text, 1, 8)
    );
    
    -- CRITICAL FIX: Replace hyphens with underscores to comply with constraint
    username_value := REPLACE(username_value, '-', '_');
    
    -- Ensure username doesn't exceed 24 characters (constraint requirement)
    IF LENGTH(username_value) > 24 THEN
        username_value := LEFT(username_value, 24);
    END IF;
    
    -- Ensure username is unique by appending numbers if needed
    WHILE EXISTS (SELECT 1 FROM public.user_profiles WHERE username = username_value) LOOP
        -- Create a shorter base to make room for the suffix
        username_value := LEFT(COALESCE(
            split_part(NEW.email, '@', 1),
            'user_' || substring(NEW.id::text, 1, 8)
        ), 20) || '_' || floor(random() * 1000)::text;
        username_value := REPLACE(username_value, '-', '_'); -- Replace hyphens again
    END LOOP;
    
    -- Insert the user profile
    INSERT INTO public.user_profiles (
        id,
        username,
        full_name,
        email,
        auth_user_id,
        role,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        username_value,
        display_name,
        NEW.email,
        NEW.id,
        'regular',
        NOW(),
        NOW()
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();
