-- ============================================================================
-- DIAGNOSTIC: returns what promote_user_to_admin sees at runtime.
-- Call from Flutter: _client.rpc('debug_promote_auth', params: {'p_org_id': orgId})
-- Remove this function once the root cause is confirmed.
-- ============================================================================

CREATE OR REPLACE FUNCTION debug_promote_auth(p_org_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func$
DECLARE
    raw_claims      text;
    caller_id       uuid;
    caller_role     text;
    manages_org     boolean := false;
    parse_error     text := null;
BEGIN
    -- Step 1: raw JWT claims string
    raw_claims := current_setting('request.jwt.claims', true);

    -- Step 2: parse sub claim
    BEGIN
        caller_id := (raw_claims::jsonb->>'sub')::uuid;
    EXCEPTION WHEN OTHERS THEN
        parse_error := SQLERRM;
    END;

    -- Step 3: look up role
    IF caller_id IS NOT NULL THEN
        SELECT role INTO caller_role
        FROM user_profiles
        WHERE id = caller_id;

        SELECT EXISTS(
            SELECT 1 FROM admin_organizations
            WHERE user_id = caller_id AND organization_id = p_org_id
        ) INTO manages_org;
    END IF;

    RETURN jsonb_build_object(
        'claims_empty',  raw_claims IS NULL OR raw_claims = '',
        'caller_id',     caller_id,
        'caller_role',   caller_role,
        'manages_org',   manages_org,
        'parse_error',   parse_error
    );
END;
$func$;
