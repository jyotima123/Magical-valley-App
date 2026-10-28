-- ============================================================================
-- FIX: auth.uid() is unreliable inside SECURITY DEFINER functions in Supabase.
-- When the execution role switches to the function owner, current_setting()
-- for 'request.jwt.claims' may not be accessible via the auth.uid() wrapper.
-- Read the JWT sub claim directly from the session variable instead.
-- ============================================================================

CREATE OR REPLACE FUNCTION promote_user_to_admin(
    user_email text,
    org_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func$
DECLARE
    caller_id   uuid;
    caller_record RECORD;
    target_record RECORD;
    org_name    text;
BEGIN
    -- Read the caller's UUID directly from the JWT claims set by PostgREST
    BEGIN
        caller_id := (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
    EXCEPTION WHEN OTHERS THEN
        caller_id := NULL;
    END;

    IF caller_id IS NULL THEN
        RAISE NOTICE 'promote_user_to_admin: could not identify caller from JWT claims';
        RETURN false;
    END IF;

    SELECT id, role INTO caller_record
    FROM user_profiles
    WHERE id = caller_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'promote_user_to_admin: caller % not found in user_profiles', caller_id;
        RETURN false;
    END IF;

    -- Regular users cannot promote anyone
    IF caller_record.role = 'regular' THEN
        RAISE NOTICE 'promote_user_to_admin: regular user % cannot promote others', caller_id;
        RETURN false;
    END IF;

    -- Admin can only promote in orgs they currently manage
    IF caller_record.role = 'admin' THEN
        IF NOT EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = caller_record.id AND organization_id = org_id
        ) THEN
            RAISE NOTICE 'promote_user_to_admin: admin % does not manage org %', caller_id, org_id;
            RETURN false;
        END IF;
    END IF;

    -- Get target user details
    SELECT id, role INTO target_record
    FROM user_profiles
    WHERE email = user_email;

    IF NOT FOUND THEN
        RAISE NOTICE 'promote_user_to_admin: target user % not found', user_email;
        RETURN false;
    END IF;

    -- Superadmin status cannot be changed from the app
    IF target_record.role = 'superadmin' THEN
        RAISE NOTICE 'promote_user_to_admin: cannot change superadmin %', user_email;
        RETURN false;
    END IF;

    -- Check organization exists
    SELECT name INTO org_name FROM organizations WHERE id = org_id;
    IF NOT FOUND THEN
        RAISE NOTICE 'promote_user_to_admin: org % not found', org_id;
        RETURN false;
    END IF;

    -- Promote regular → admin if needed
    IF target_record.role = 'regular' THEN
        UPDATE user_profiles
        SET role = 'admin', updated_at = NOW()
        WHERE id = target_record.id;
        RAISE NOTICE 'promote_user_to_admin: % promoted regular → admin', user_email;
    ELSE
        RAISE NOTICE 'promote_user_to_admin: % already admin, skipping role change', user_email;
    END IF;

    -- Assign to organization (idempotent)
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (target_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO NOTHING;

    RAISE NOTICE 'promote_user_to_admin: % assigned to org "%" (%)', user_email, org_name, org_id;
    RETURN true;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'promote_user_to_admin: unexpected error: %', SQLERRM;
        RETURN false;
END;
$func$;


CREATE OR REPLACE FUNCTION remove_admin_from_organization(
    user_email text,
    org_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func$
DECLARE
    caller_id     uuid;
    caller_record RECORD;
    target_record RECORD;
    remaining_orgs integer;
BEGIN
    -- Read the caller's UUID directly from the JWT claims set by PostgREST
    BEGIN
        caller_id := (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
    EXCEPTION WHEN OTHERS THEN
        caller_id := NULL;
    END;

    IF caller_id IS NULL THEN
        RAISE NOTICE 'remove_admin_from_organization: could not identify caller from JWT claims';
        RETURN false;
    END IF;

    SELECT id, role INTO caller_record
    FROM user_profiles
    WHERE id = caller_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'remove_admin_from_organization: caller % not found in user_profiles', caller_id;
        RETURN false;
    END IF;

    -- Get target user details
    SELECT id, role INTO target_record
    FROM user_profiles
    WHERE email = user_email;

    IF NOT FOUND THEN
        RAISE NOTICE 'remove_admin_from_organization: target user % not found', user_email;
        RETURN false;
    END IF;

    -- Superadmin cannot be removed from the app
    IF target_record.role = 'superadmin' THEN
        RAISE NOTICE 'remove_admin_from_organization: cannot remove superadmin %', user_email;
        RETURN false;
    END IF;

    -- Authorization check
    IF caller_record.role = 'regular' THEN
        RAISE NOTICE 'remove_admin_from_organization: regular user % cannot remove admins', caller_id;
        RETURN false;
    END IF;

    IF caller_record.role = 'admin' THEN
        -- Admin can only remove themselves
        IF caller_record.id != target_record.id THEN
            RAISE NOTICE 'remove_admin_from_organization: admin % cannot remove others', caller_id;
            RETURN false;
        END IF;
        -- And only from an org they actually manage
        IF NOT EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = caller_record.id AND organization_id = org_id
        ) THEN
            RAISE NOTICE 'remove_admin_from_organization: admin % not in org %', caller_id, org_id;
            RETURN false;
        END IF;
    END IF;

    -- Verify target is actually assigned to this org
    IF NOT EXISTS (
        SELECT 1 FROM admin_organizations
        WHERE user_id = target_record.id AND organization_id = org_id
    ) THEN
        RAISE NOTICE 'remove_admin_from_organization: % not assigned to org %', user_email, org_id;
        RETURN false;
    END IF;

    -- Count remaining org assignments after this removal
    SELECT COUNT(*) - 1 INTO remaining_orgs
    FROM admin_organizations
    WHERE user_id = target_record.id;

    -- Remove from this organization
    DELETE FROM admin_organizations
    WHERE user_id = target_record.id AND organization_id = org_id;

    -- If this was the last org and user is admin, demote to regular
    IF remaining_orgs = 0 AND target_record.role = 'admin' THEN
        UPDATE user_profiles
        SET role = 'regular', updated_at = NOW()
        WHERE id = target_record.id;
        RAISE NOTICE 'remove_admin_from_organization: % removed from last org, demoted to regular', user_email;
    ELSE
        RAISE NOTICE 'remove_admin_from_organization: % removed from org (% orgs remaining)', user_email, remaining_orgs;
    END IF;

    RETURN true;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'remove_admin_from_organization: unexpected error: %', SQLERRM;
        RETURN false;
END;
$func$;
