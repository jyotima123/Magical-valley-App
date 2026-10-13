-- Migration 059: Auto-set verified_at for social login users
--
-- Apple, Google, and Facebook users are verified by their identity provider;
-- they should never see the in-app OTP verification screen. Two fixes:
--
--   1. handle_new_user trigger now sets verified_at = NOW() for non-email
--      providers so all future social signups are immediately marked verified.
--
--   2. Backfill for existing social login users whose verified_at is still NULL
--      because they signed up before this migration.

-- 1. Rebuild the trigger with the verified_at column included.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    username_value TEXT;
    display_name TEXT;
    v_verified_at  TIMESTAMPTZ;
BEGIN
    -- Phone-only auth users have no email. Skip profile creation for them;
    -- the phone is linked to an existing profile via auth.updateUser instead.
    IF NEW.email IS NULL THEN
        RETURN NEW;
    END IF;

    -- Social login users (Apple, Google, Facebook, …) are verified by their
    -- identity provider. Set verified_at immediately so they never land on
    -- the in-app OTP verification screen.
    v_verified_at := CASE
        WHEN COALESCE(NEW.raw_app_meta_data->>'provider', 'email') = 'email'
            THEN NULL   -- email/password signup: must complete OTP verification
        ELSE NOW()      -- social login: already verified externally
    END;

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
        verified_at,
        created_at,
        updated_at
    ) VALUES (
        NEW.id,
        username_value,
        display_name,
        NEW.email,
        NEW.id,
        'regular',
        v_verified_at,
        NOW(),
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Backfill existing social login users.
--    Joins user_profiles against auth.users to find rows where the Supabase
--    provider is not 'email' and verified_at is still NULL.
UPDATE public.user_profiles up
SET    verified_at = NOW()
FROM   auth.users au
WHERE  au.id = up.id
  AND  up.verified_at IS NULL
  AND  COALESCE(au.raw_app_meta_data->>'provider', 'email') != 'email';
