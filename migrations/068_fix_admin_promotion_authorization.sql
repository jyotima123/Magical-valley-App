-- ============================================================================
-- FIX: ADMIN PROMOTION AUTHORIZATION
--
-- Business rules enforced:
--   regular   → cannot promote anyone (can be promoted by admins/superadmins)
--   admin     → can promote users to admin of orgs they manage
--               can remove THEMSELVES from being admin of an org they manage
--               cannot remove other admins
--   superadmin → can promote/remove anyone
--               cannot be changed from the app (protected target)
-- ============================================================================

CREATE OR REPLACE FUNCTION promote_user_to_admin(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    caller_record RECORD;
    target_record RECORD;
    org_name text;
BEGIN
    -- Identify the calling user from the JWT
    SELECT id, role INTO caller_record
    FROM user_profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RAISE NOTICE 'Caller not found in user_profiles';
        RETURN false;
    END IF;

    -- Regular users cannot promote anyone
    IF caller_record.role = 'regular' THEN
        RAISE NOTICE 'Regular users cannot promote others to admin';
        RETURN false;
    END IF;

    -- Admin can only promote in orgs they currently manage
    IF caller_record.role = 'admin' THEN
        IF NOT EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = caller_record.id AND organization_id = org_id
        ) THEN
            RAISE NOTICE 'Admin % does not manage organization %', caller_record.id, org_id;
            RETURN false;
        END IF;
    END IF;

    -- Get target user details
    SELECT id, role INTO target_record
    FROM user_profiles
    WHERE email = user_email;

    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;

    -- Superadmin status cannot be changed from the app
    IF target_record.role = 'superadmin' THEN
        RAISE NOTICE 'Cannot change superadmin role';
        RETURN false;
    END IF;

    -- Check organization exists
    SELECT name INTO org_name FROM organizations WHERE id = org_id;
    IF NOT FOUND THEN
        RAISE NOTICE 'Organization with ID % not found', org_id;
        RETURN false;
    END IF;

    -- Promote regular → admin if needed (existing admins just get the org assignment)
    IF target_record.role = 'regular' THEN
        UPDATE user_profiles
        SET role = 'admin', updated_at = NOW()
        WHERE id = target_record.id;
        RAISE NOTICE 'User % promoted from regular to admin', user_email;
    ELSE
        RAISE NOTICE 'User % is already an admin, skipping role change', user_email;
    END IF;

    -- Assign to organization (idempotent)
    INSERT INTO admin_organizations (user_id, organization_id, assigned_at)
    VALUES (target_record.id, org_id, NOW())
    ON CONFLICT (user_id, organization_id) DO NOTHING;

    RAISE NOTICE 'User % assigned as admin to organization "%" (%)', user_email, org_name, org_id;
    RETURN true;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error in promote_user_to_admin: %', SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;


-- promote_user_to_admin_by_org_name delegates to promote_user_to_admin,
-- so the authorization check above is automatically inherited.


CREATE OR REPLACE FUNCTION remove_admin_from_organization(
    user_email text,
    org_id uuid
)
RETURNS boolean AS $func$
DECLARE
    caller_record RECORD;
    target_record RECORD;
    remaining_orgs integer;
BEGIN
    -- Identify the calling user from the JWT
    SELECT id, role INTO caller_record
    FROM user_profiles
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RAISE NOTICE 'Caller not found in user_profiles';
        RETURN false;
    END IF;

    -- Get target user details
    SELECT id, role INTO target_record
    FROM user_profiles
    WHERE email = user_email;

    IF NOT FOUND THEN
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;

    -- Superadmin cannot be removed from the app
    IF target_record.role = 'superadmin' THEN
        RAISE NOTICE 'Cannot remove superadmin from organization';
        RETURN false;
    END IF;

    -- Authorization check
    IF caller_record.role = 'regular' THEN
        RAISE NOTICE 'Regular users cannot remove admins';
        RETURN false;
    END IF;

    IF caller_record.role = 'admin' THEN
        -- Admin can only remove themselves
        IF caller_record.id != target_record.id THEN
            RAISE NOTICE 'Admin % can only remove themselves, not other admins', caller_record.id;
            RETURN false;
        END IF;
        -- And only from an org they actually manage
        IF NOT EXISTS (
            SELECT 1 FROM admin_organizations
            WHERE user_id = caller_record.id AND organization_id = org_id
        ) THEN
            RAISE NOTICE 'Admin % is not assigned to organization %', caller_record.id, org_id;
            RETURN false;
        END IF;
    END IF;

    -- Verify target is actually assigned to this org
    IF NOT EXISTS (
        SELECT 1 FROM admin_organizations
        WHERE user_id = target_record.id AND organization_id = org_id
    ) THEN
        RAISE NOTICE 'User % is not assigned to organization %', user_email, org_id;
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
        RAISE NOTICE 'User % removed from last org and demoted to regular', user_email;
    ELSE
        RAISE NOTICE 'User % removed from org (still admin of % other org(s))', user_email, remaining_orgs;
    END IF;

    RETURN true;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error in remove_admin_from_organization: %', SQLERRM;
        RETURN false;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
