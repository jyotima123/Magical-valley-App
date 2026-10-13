-- Drop and recreate the function with the correct column mapping
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
    
    -- Ensure username is unique by appending numbers if needed
    WHILE EXISTS (SELECT 1 FROM public.user_profiles WHERE username = username_value) LOOP
        username_value := username_value || '_' || floor(random() * 1000)::text;
    END LOOP;
    
    -- Insert the user profile with auth_user_id
    INSERT INTO public.user_profiles (
        id,
        username,
        full_name,
        email,
        auth_user_id,  -- This was missing!
        role,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        username_value,
        display_name,
        NEW.email,
        NEW.id,        -- Set auth_user_id to the same as id
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
