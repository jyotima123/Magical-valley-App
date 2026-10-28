-- Migration 056: Fix handle_new_user trigger to handle phone-only auth users
--
-- Root cause: signInWithOtp(phone) creates a new auth.users row with email=NULL
-- when the phone is not already registered. The trigger then tries to INSERT
-- into user_profiles with email=NULL, violating the NOT NULL constraint and
-- causing Supabase to return HTTP 500 "Database error saving new user".
--
-- Fix: return early when NEW.email IS NULL (phone-only user) so no profile row
-- is attempted. Phone numbers are linked to existing profiles via updateUser,
-- not via a new auth.users insert.

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    username_value TEXT;
    display_name TEXT;
BEGIN
    -- Phone-only auth users have no email. Skip profile creation for them;
    -- the phone is linked to an existing profile via auth.updateUser instead.
    IF NEW.email IS NULL THEN
        RETURN NEW;
    END IF;

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

    -- Replace hyphens with underscores to comply with constraint
    username_value := REPLACE(username_value, '-', '_');

    -- Ensure username doesn't exceed 24 characters (constraint requirement)
    IF LENGTH(username_value) > 24 THEN
        username_value := LEFT(username_value, 24);
    END IF;

    -- Ensure username is unique by appending numbers if needed
    WHILE EXISTS (SELECT 1 FROM public.user_profiles WHERE username = username_value) LOOP
        username_value := LEFT(COALESCE(
            split_part(NEW.email, '@', 1),
            'user_' || substring(NEW.id::text, 1, 8)
        ), 20) || '_' || floor(random() * 1000)::text;
        username_value := REPLACE(username_value, '-', '_');
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
