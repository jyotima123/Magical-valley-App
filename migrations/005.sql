-- ============================================================================
-- SCRIPT 3: ADDITIONAL SUPERADMIN HELPER FUNCTIONS
-- ============================================================================

-- Function to promote a user to superadmin by email
CREATE OR REPLACE FUNCTION promote_user_to_superadmin(user_email text)
RETURNS boolean AS $func$
DECLARE
    rows_affected integer;
BEGIN
    UPDATE user_profiles 
    SET role = 'superadmin', updated_at = NOW() 
    WHERE email = user_email;
    
    GET DIAGNOSTICS rows_affected = ROW_COUNT;
    
    IF rows_affected > 0 THEN
        RAISE NOTICE 'User % promoted to superadmin successfully', user_email;
        RETURN true;
    ELSE
        RAISE NOTICE 'User with email % not found', user_email;
        RETURN false;
    END IF;
END;
$func$ LANGUAGE plpgsql SECURITY DEFINER;
