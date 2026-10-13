#!/usr/bin/env python3
"""
Script to delete a test user from Supabase database.
This script uses the Supabase service role key to delete users directly from the database.

Usage:
    python3 delete_test_user.py <user_id_or_email>

Returns:
    Exit code 0 on success
    Exit code 1 on failure with error message printed to stderr
"""

import sys
import os
import requests
import time
from typing import Optional, Tuple

# Configuration
SUPABASE_URL = "https://yavxzgcgoasicjprzfcv.supabase.co"

# Try to get service role key from environment or .env_qa file
def get_service_role_key() -> str:
    # First, try environment variable
    key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')
    if key:
        return key
    
    # Try to read from .env_qa file
    try:
        env_file = os.path.join(os.path.dirname(__file__), '../../.env_qa')
        with open(env_file, 'r') as f:
            for line in f:
                if line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
                    return line.split('=', 1)[1].strip().strip('"').strip("'")
    except Exception as e:
        pass
    
    raise ValueError("SUPABASE_SERVICE_ROLE_KEY not found. Please set it in .env_qa or as environment variable")

def delete_user_related_data(profile_id: str) -> bool:
    """
    Delete all data related to a user profile before deleting the profile itself.
    This handles foreign key constraints.
    
    Args:
        profile_id: The user_profiles.id (primary key, not auth_user_id)
        
    Returns:
        True if successful
    """
    service_key = get_service_role_key()
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Prefer": "return=representation"
    }
    
    deleted_any = False
    
    # Tables that reference user_profiles.id via user_id or similar:
    # 1. posts.created_by -> user_profiles.id
    # 2. post_reactions.user_id -> user_profiles.id
    # 3. post_views.user_id -> user_profiles.id
    # 4. request_queue.user_id -> user_profiles.id
    # 5. request_queue.reviewed_by -> user_profiles.id
    # 6. user_fcm_tokens.user_id -> user_profiles.id
    # 7. user_follows.user_id -> user_profiles.id
    # 8. admin_organizations.user_id -> user_profiles.id
    
    tables_to_clean = [
        ("posts", "created_by"),
        ("post_reactions", "user_id"),
        ("post_views", "user_id"),
        ("user_fcm_tokens", "user_id"),
        ("user_follows", "user_id"),
        ("admin_organizations", "user_id"),
    ]
    
    # request_queue has two foreign keys
    request_queue_cleanup = [
        ("request_queue", "user_id"),
        ("request_queue", "reviewed_by"),
    ]
    
    base_url = f"{SUPABASE_URL}/rest/v1"
    
    for table_name, column_name in tables_to_clean:
        try:
            url = f"{base_url}/{table_name}"
            params = {column_name: f"eq.{profile_id}"}
            response = requests.delete(url, headers=headers, params=params)
            
            if response.status_code in [200, 204]:
                deleted_data = response.json() if response.content else []
                count = len(deleted_data) if isinstance(deleted_data, list) else 0
                if count > 0 or response.status_code == 204:
                    print(f"✅ Deleted {count} record(s) from {table_name}", file=sys.stderr)
                    deleted_any = True
        except Exception as e:
            print(f"⚠️ Error deleting from {table_name}: {e}", file=sys.stderr)
    
    # Handle request_queue separately (both user_id and reviewed_by)
    for table_name, column_name in request_queue_cleanup:
        try:
            url = f"{base_url}/{table_name}"
            params = {column_name: f"eq.{profile_id}"}
            response = requests.delete(url, headers=headers, params=params)
            
            if response.status_code in [200, 204]:
                deleted_data = response.json() if response.content else []
                count = len(deleted_data) if isinstance(deleted_data, list) else 0
                if count > 0 or response.status_code == 204:
                    print(f"✅ Deleted {count} record(s) from {table_name} (via {column_name})", file=sys.stderr)
                    deleted_any = True
        except Exception as e:
            print(f"⚠️ Error deleting from {table_name} ({column_name}): {e}", file=sys.stderr)
    
    return True  # Return True even if nothing was deleted (user might not have related data)

def get_profile_id_by_auth_user_id(auth_user_id: str) -> Optional[str]:
    """
    Get the user_profiles.id (primary key) given an auth_user_id.
    
    Args:
        auth_user_id: The auth.users.id which maps to user_profiles.auth_user_id
        
    Returns:
        The user_profiles.id or None if not found
    """
    service_key = get_service_role_key()
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}"
    }
    
    profile_url = f"{SUPABASE_URL}/rest/v1/user_profiles"
    params = {"auth_user_id": f"eq.{auth_user_id}", "select": "id"}
    
    try:
        response = requests.get(profile_url, headers=headers, params=params)
        if response.status_code == 200:
            profiles = response.json()
            if isinstance(profiles, list) and len(profiles) > 0:
                return profiles[0].get("id")
    except Exception as e:
        print(f"⚠️ Error getting profile ID: {e}", file=sys.stderr)
    
    return None

def delete_user_profile(email: str, username: Optional[str] = None, user_id: Optional[str] = None) -> bool:
    """
    Delete user profile from database.
    Tries multiple methods to ensure the profile is deleted.
    
    Args:
        email: User email
        username: Optional username to try deleting by username
        user_id: Optional user ID to try deleting by ID or auth_user_id
        
    Returns:
        True if successful or profile doesn't exist
    """
    service_key = get_service_role_key()
    
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Prefer": "return=representation"  # Get deleted records back
    }
    
    profile_url = f"{SUPABASE_URL}/rest/v1/user_profiles"
    deleted = False
    
    # First, get the profile_id (primary key) so we can delete related data
    profile_id = None
    
    if user_id:
        # Get profile_id using auth_user_id
        profile_id = get_profile_id_by_auth_user_id(user_id)
        if profile_id:
            print(f"Found profile ID: {profile_id}", file=sys.stderr)
            # Delete all related data first
            print(f"🗑️  Deleting all data related to user profile...", file=sys.stderr)
            delete_user_related_data(profile_id)
    
    # If we don't have profile_id yet, try to get it by email
    if not profile_id and email:
        try:
            params = {"email": f"eq.{email}", "select": "id,username"}
            response = requests.get(profile_url, headers={
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}"
            }, params=params)
            if response.status_code == 200:
                profiles = response.json()
                if isinstance(profiles, list) and len(profiles) > 0:
                    profile_data = profiles[0]
                    profile_id = profile_data.get("id")
                    # Also get username from profile if we don't have it
                    if not username:
                        username = profile_data.get("username")
                    print(f"Found profile ID by email: {profile_id}, username: {username}", file=sys.stderr)
                    # Delete all related data
                    print(f"🗑️  Deleting all data related to user profile...", file=sys.stderr)
                    delete_user_related_data(profile_id)
        except Exception as e:
            print(f"⚠️ Error getting profile ID by email: {e}", file=sys.stderr)
    
    # Method 1: Try deleting by email (if provided)
    if email:
        try:
            print(f"Deleting user profile by email: {email}", file=sys.stderr)
            params = {"email": f"eq.{email}"}
            response = requests.delete(profile_url, headers=headers, params=params)
            
            if response.status_code in [200, 204]:
                deleted_data = response.json() if response.content else []
                deleted_count = len(deleted_data) if isinstance(deleted_data, list) else 0
                if deleted_count > 0:
                    print(f"✅ User profile deleted successfully by email (deleted {deleted_count} record(s))", file=sys.stderr)
                    deleted = True
                elif response.status_code == 204:
                    # 204 means deleted but no content returned
                    print(f"✅ User profile deleted successfully by email (204 No Content)", file=sys.stderr)
                    deleted = True
                else:
                    print(f"⚠️ Delete by email returned {response.status_code} but no deleted records in response", file=sys.stderr)
            elif response.status_code == 404:
                print(f"⚠️ User profile not found by email (may have already been deleted)", file=sys.stderr)
            else:
                print(f"⚠️ Unexpected status code when deleting by email: {response.status_code}", file=sys.stderr)
                if response.content:
                    print(f"   Response: {response.text}", file=sys.stderr)
        except Exception as e:
            print(f"⚠️ Error deleting user profile by email: {e}", file=sys.stderr)
    
    # Method 2: Try deleting by username if provided and not already deleted
    if not deleted and username:
        try:
            print(f"Trying to delete user profile by username: {username}", file=sys.stderr)
            params = {"username": f"eq.{username}"}
            response = requests.delete(profile_url, headers=headers, params=params)
            
            if response.status_code in [200, 204]:
                deleted_data = response.json() if response.content else []
                deleted_count = len(deleted_data) if isinstance(deleted_data, list) else 0
                if deleted_count > 0:
                    print(f"✅ User profile deleted successfully by username (deleted {deleted_count} record(s))", file=sys.stderr)
                    deleted = True
                elif response.status_code == 204:
                    print(f"✅ User profile deleted successfully by username (204 No Content)", file=sys.stderr)
                    deleted = True
                else:
                    print(f"⚠️ Delete by username returned {response.status_code} but no deleted records in response", file=sys.stderr)
            elif response.status_code == 404:
                print(f"⚠️ User profile not found by username", file=sys.stderr)
            else:
                print(f"⚠️ Unexpected status code when deleting by username: {response.status_code}", file=sys.stderr)
        except Exception as e:
            print(f"⚠️ Error deleting user profile by username: {e}", file=sys.stderr)
    
    # Method 3: Try deleting by auth_user_id first (most reliable since it's unique and matches auth.users.id)
    if not deleted and user_id:
        # Try by auth_user_id first (this is the foreign key to auth.users.id)
        try:
            print(f"Trying to delete user profile by auth_user_id: {user_id}", file=sys.stderr)
            params = {"auth_user_id": f"eq.{user_id}"}
            response = requests.delete(profile_url, headers=headers, params=params)
            
            if response.status_code in [200, 204]:
                deleted_data = response.json() if response.content else []
                deleted_count = len(deleted_data) if isinstance(deleted_data, list) else 0
                if deleted_count > 0:
                    print(f"✅ User profile deleted successfully by auth_user_id (deleted {deleted_count} record(s))", file=sys.stderr)
                    deleted = True
                elif response.status_code == 204:
                    print(f"✅ User profile deleted successfully by auth_user_id (204 No Content)", file=sys.stderr)
                    deleted = True
                else:
                    print(f"⚠️ Delete by auth_user_id returned {response.status_code} but no deleted records in response", file=sys.stderr)
        except Exception as e:
            print(f"⚠️ Error deleting user profile by auth_user_id: {e}", file=sys.stderr)
        
        # Also try by id (primary key) as fallback
        if not deleted:
            try:
                print(f"Trying to delete user profile by primary key ID: {user_id}", file=sys.stderr)
                params = {"id": f"eq.{user_id}"}
                response = requests.delete(profile_url, headers=headers, params=params)
                
                if response.status_code in [200, 204]:
                    deleted_data = response.json() if response.content else []
                    if isinstance(deleted_data, list) and len(deleted_data) > 0:
                        print(f"✅ User profile deleted successfully by primary key ID", file=sys.stderr)
                        deleted = True
                    elif response.status_code == 204:
                        print(f"✅ User profile deleted successfully by primary key ID", file=sys.stderr)
                        deleted = True
            except Exception as e:
                print(f"⚠️ Error deleting user profile by primary key ID: {e}", file=sys.stderr)
    
    # Verify deletion by trying to fetch the profile using multiple methods
    if deleted:
        verified = False
        verification_failed = False
        
        # Verify by email if we have it
        if email:
            try:
                verify_params = {"email": f"eq.{email}"}
                verify_response = requests.get(profile_url, headers=headers, params=verify_params)
                if verify_response.status_code == 200:
                    profiles = verify_response.json()
                    if isinstance(profiles, list) and len(profiles) == 0:
                        print(f"✅ Verified: User profile no longer exists (checked by email)", file=sys.stderr)
                        verified = True
                    else:
                        print(f"❌ ERROR: Profile still exists after deletion! Found {len(profiles)} profile(s) by email", file=sys.stderr)
                        verification_failed = True
            except Exception as e:
                print(f"⚠️ Verification by email failed: {e}", file=sys.stderr)
        
        # Also verify by username if we have it (critical since username is unique)
        if username:
            try:
                verify_params = {"username": f"eq.{username}"}
                verify_response = requests.get(profile_url, headers=headers, params=verify_params)
                if verify_response.status_code == 200:
                    profiles = verify_response.json()
                    if isinstance(profiles, list) and len(profiles) == 0:
                        print(f"✅ Verified: User profile no longer exists (checked by username)", file=sys.stderr)
                        if not verified:
                            verified = True
                    else:
                        print(f"❌ ERROR: Profile with username '{username}' still exists after deletion! Found {len(profiles)} profile(s)", file=sys.stderr)
                        # Print details of remaining profiles
                        for profile in profiles:
                            print(f"   - Profile ID: {profile.get('id')}, Email: {profile.get('email')}, Username: {profile.get('username')}", file=sys.stderr)
                        verification_failed = True
            except Exception as e:
                print(f"⚠️ Verification by username failed: {e}", file=sys.stderr)
        
        # Also verify by auth_user_id if we have it
        if user_id and not verified:
            try:
                verify_params = {"auth_user_id": f"eq.{user_id}"}
                verify_response = requests.get(profile_url, headers=headers, params=verify_params)
                if verify_response.status_code == 200:
                    profiles = verify_response.json()
                    if isinstance(profiles, list) and len(profiles) == 0:
                        print(f"✅ Verified: User profile no longer exists (checked by auth_user_id)", file=sys.stderr)
                        verified = True
                    else:
                        print(f"❌ ERROR: Profile still exists after deletion! Found {len(profiles)} profile(s) by auth_user_id", file=sys.stderr)
                        verification_failed = True
            except Exception as e:
                print(f"⚠️ Verification by auth_user_id failed: {e}", file=sys.stderr)
        
        # If verification failed, return False
        if verification_failed:
            print(f"❌ Deletion verification failed - profile may still exist", file=sys.stderr)
            return False
        
        # If we couldn't verify but deletion reported success, return True anyway
        # (verification might fail due to permissions or other issues)
        if not verified:
            print(f"⚠️ Could not verify deletion, but deletion reported success", file=sys.stderr)
    
    return deleted

def delete_auth_user(email_or_id: str) -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Delete user from Supabase Auth.
    
    Args:
        email_or_id: User email or ID
        
    Returns:
        Tuple of (success, user_id, username) - username might be None if not found
    """
    service_key = get_service_role_key()
    
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json"
    }
    
    # Determine if email or ID
    is_email = "@" in email_or_id
    user_id = None
    username = None
    
    if is_email:
        # First, get user by email to get user_id and any metadata
        get_url = f"{SUPABASE_URL}/auth/v1/admin/users"
        params = {"email": email_or_id}
        
        try:
            response = requests.get(get_url, headers=headers, params=params)
            response.raise_for_status()
            users = response.json().get("users", [])
            
            if not users:
                print(f"⚠️ User not found in auth: {email_or_id}", file=sys.stderr)
                return (True, None, None)  # Consider this success
            
            user_data = users[0]
            user_id = user_data.get("id")
            # Try to get username from user_metadata or other fields
            user_metadata = user_data.get("user_metadata", {})
            username = user_metadata.get("username") or user_metadata.get("preferred_username")
            
        except Exception as e:
            print(f"⚠️ Error getting user by email: {e}", file=sys.stderr)
            return (False, None, None)
    else:
        user_id = email_or_id
        # Try to get user data to extract username
        try:
            get_url = f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}"
            response = requests.get(get_url, headers=headers)
            if response.status_code == 200:
                user_data = response.json()
                user_metadata = user_data.get("user_metadata", {})
                username = user_metadata.get("username") or user_metadata.get("preferred_username")
        except:
            pass  # Not critical if we can't get username
    
    if not user_id:
        return (False, None, None)
    
    # Delete the auth user
    delete_url = f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}"
    
    try:
        print(f"Deleting auth user: {user_id}", file=sys.stderr)
        response = requests.delete(delete_url, headers=headers)
        
        if response.status_code == 200 or response.status_code == 204:
            print(f"✅ Auth user deleted successfully", file=sys.stderr)
            return (True, user_id, username)
        elif response.status_code == 404:
            print(f"⚠️ Auth user not found (may have already been deleted)", file=sys.stderr)
            return (True, user_id, username)  # Consider this success
        else:
            print(f"⚠️ Unexpected status code: {response.status_code}", file=sys.stderr)
            if response.content:
                print(f"   Response: {response.text}", file=sys.stderr)
            return (False, user_id, username)
            
    except Exception as e:
        print(f"⚠️ Error deleting auth user: {e}", file=sys.stderr)
        return (False, user_id, username)

def delete_test_user(email_or_id: str) -> bool:
    """
    Delete a test user from both auth and user_profiles.
    
    IMPORTANT: We delete the profile FIRST, then the auth user.
    This is because:
    - The profile has auth_user_id as foreign key to auth.users
    - We need to get the auth_user_id before deleting auth user
    - But we can still find profile by email/username even after getting auth info
    
    Args:
        email_or_id: User email or ID
        
    Returns:
        True if successful
    """
    # Determine if email or ID
    is_email = "@" in email_or_id
    
    if is_email:
        # STEP 1: Get auth user info FIRST (before deleting anything)
        # This gives us user_id (auth.users.id) and username
        service_key = get_service_role_key()
        headers = {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json"
        }
        
        get_url = f"{SUPABASE_URL}/auth/v1/admin/users"
        params = {"email": email_or_id}
        user_id = None
        username = None
        
        try:
            print(f"🔍 Getting auth user info for: {email_or_id}", file=sys.stderr)
            response = requests.get(get_url, headers=headers, params=params)
            response.raise_for_status()
            users = response.json().get("users", [])
            
            if users:
                user_data = users[0]
                user_id = user_data.get("id")  # This is auth.users.id, which maps to user_profiles.auth_user_id
                user_metadata = user_data.get("user_metadata", {})
                username = user_metadata.get("username") or user_metadata.get("preferred_username")
                
                # Also try to get username from the profile itself if not in metadata
                if not username:
                    try:
                        profile_url = f"{SUPABASE_URL}/rest/v1/user_profiles"
                        profile_params = {"auth_user_id": f"eq.{user_id}", "select": "username"}
                        profile_response = requests.get(profile_url, headers=headers, params=profile_params)
                        if profile_response.status_code == 200:
                            profiles = profile_response.json()
                            if isinstance(profiles, list) and len(profiles) > 0:
                                username = profiles[0].get("username")
                    except Exception as e:
                        print(f"⚠️ Could not get username from profile: {e}", file=sys.stderr)
                
                print(f"✅ Found auth user: id={user_id}, username={username}", file=sys.stderr)
            else:
                print(f"⚠️ Auth user not found: {email_or_id}", file=sys.stderr)
        except Exception as e:
            print(f"⚠️ Error getting auth user info: {e}", file=sys.stderr)
        
        # STEP 2: Delete profile FIRST (using email, username, and auth_user_id)
        profile_success = delete_user_profile(email_or_id, username=username, user_id=user_id)
        
        # STEP 3: Wait a moment for database replication/commit
        if profile_success:
            print(f"⏳ Waiting 2 seconds for database replication...", file=sys.stderr)
            time.sleep(2)
            # Verify one more time after waiting
            print(f"🔍 Final verification after wait...", file=sys.stderr)
            service_key = get_service_role_key()
            headers = {
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}"
            }
            profile_url = f"{SUPABASE_URL}/rest/v1/user_profiles"
            
            # Check by username one more time
            if username:
                try:
                    verify_params = {"username": f"eq.{username}"}
                    verify_response = requests.get(profile_url, headers=headers, params=verify_params)
                    if verify_response.status_code == 200:
                        profiles = verify_response.json()
                        if isinstance(profiles, list) and len(profiles) > 0:
                            print(f"⚠️ WARNING: Profile with username '{username}' still exists after wait!", file=sys.stderr)
                            for profile in profiles:
                                print(f"   - Profile ID: {profile.get('id')}, Email: {profile.get('email')}, Username: {profile.get('username')}, Auth User ID: {profile.get('auth_user_id')}", file=sys.stderr)
                            # Try deleting again by profile ID
                            for profile in profiles:
                                profile_id_to_delete = profile.get('id')
                                if profile_id_to_delete:
                                    print(f"🔄 Attempting to delete remaining profile by ID: {profile_id_to_delete}", file=sys.stderr)
                                    params = {"id": f"eq.{profile_id_to_delete}"}
                                    delete_response = requests.delete(profile_url, headers=headers, params=params)
                                    if delete_response.status_code in [200, 204]:
                                        print(f"✅ Deleted remaining profile", file=sys.stderr)
                                        time.sleep(1)  # Wait again after deletion
                except Exception as e:
                    print(f"⚠️ Final verification check failed: {e}", file=sys.stderr)
        
        # STEP 4: Delete auth user (only if we have user_id)
        if user_id:
            auth_success, _, _ = delete_auth_user(email_or_id)
        else:
            # If we couldn't get user_id, try deleting auth user anyway
            auth_success, _, _ = delete_auth_user(email_or_id)
        
        # Return success if both succeeded
        return auth_success and profile_success
    else:
        # For ID, get user info first
        auth_success, user_id, username = delete_auth_user(email_or_id)
        
        # Try to get email from auth user before deleting
        email = None
        if auth_success and user_id:
            service_key = get_service_role_key()
            headers = {
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}"
            }
            try:
                get_url = f"{SUPABASE_URL}/auth/v1/admin/users/{user_id}"
                response = requests.get(get_url, headers=headers)
                if response.status_code == 200:
                    user_data = response.json()
                    email = user_data.get("email")
            except:
                pass
        
        # Delete profile if we have email, otherwise try with ID and username
        if email:
            profile_success = delete_user_profile(email, username=username, user_id=user_id)
        else:
            # Try deleting profile by ID or username if we don't have email
            profile_success = delete_user_profile("", username=username, user_id=user_id)
        
        return auth_success and profile_success

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 delete_test_user.py <user_id_or_email>", file=sys.stderr)
        sys.exit(1)
    
    email_or_id = sys.argv[1]
    
    try:
        success = delete_test_user(email_or_id)
        
        if success:
            print("✅ User deleted successfully", file=sys.stderr)
            sys.exit(0)
        else:
            print("❌ Failed to delete user", file=sys.stderr)
            sys.exit(1)
            
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

