#!/usr/bin/env python3
"""
Script to create a test user in Supabase database.
This script uses the Supabase service role key to create users directly in the database.

Usage:
    python3 create_test_user.py <email> <password> <full_name> <username>

Returns:
    Exit code 0 on success with user_id printed to stdout
    Exit code 1 on failure with error message printed to stderr
"""

import sys
import os
import json
import requests
from typing import Dict, Any

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

def create_test_user(email: str, password: str, full_name: str, username: str) -> Dict[str, Any]:
    """
    Create a test user in Supabase Auth and User Profiles.
    
    Args:
        email: User email
        password: User password
        full_name: User's full name
        username: User's username
        
    Returns:
        Dict with user_id or error information
    """
    service_key = get_service_role_key()
    
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json"
    }
    
    # Step 1: Create user in Supabase Auth
    auth_url = f"{SUPABASE_URL}/auth/v1/admin/users"
    
    auth_payload = {
        "email": email,
        "password": password,
        "email_confirm": True,  # Auto-confirm email for test users
        "user_metadata": {
            "full_name": full_name
        }
    }
    
    try:
        print(f"Creating user in Supabase Auth: {email}", file=sys.stderr)
        auth_response = requests.post(auth_url, headers=headers, json=auth_payload)
        auth_response.raise_for_status()
        auth_data = auth_response.json()
        user_id = auth_data.get('id')
        
        if not user_id:
            raise Exception("Failed to create auth user: no ID returned")
        
        print(f"✅ Auth user created successfully: {user_id}", file=sys.stderr)
        
    except requests.exceptions.RequestException as e:
        error_msg = f"Failed to create auth user: {e}"
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.json()
                error_msg += f" - {json.dumps(error_detail)}"
            except:
                error_msg += f" - {e.response.text}"
        raise Exception(error_msg)
    
    # Step 2: Ensure user profile exists (Supabase may auto-create via trigger)
    # Prefer to upsert: if a profile already exists (auto-created), update it; otherwise insert
    profile_url = f"{SUPABASE_URL}/rest/v1/user_profiles"

    # First, try to fetch existing profile by auth_user_id
    try:
        get_params = {"auth_user_id": f"eq.{user_id}", "select": "id,username"}
        existing_resp = requests.get(profile_url, headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}"
        }, params=get_params)
        existing_resp.raise_for_status()
        existing_profiles = existing_resp.json() if existing_resp.content else []
    except requests.exceptions.RequestException:
        existing_profiles = []

    if isinstance(existing_profiles, list) and len(existing_profiles) > 0:
        # Update existing profile (likely created by DB trigger)
        try:
            print(f"Updating existing user profile: {username}", file=sys.stderr)
            patch_params = {"auth_user_id": f"eq.{user_id}"}
            patch_payload = {
                "email": email,
                "full_name": full_name,
                "username": username,
                "role": "regular"
            }
            patch_headers = {
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            }
            patch_resp = requests.patch(profile_url, headers=patch_headers, params=patch_params, json=patch_payload)
            if patch_resp.status_code == 409:
                # Username conflict: append a numeric suffix
                print(f"⚠️ Username '{username}' already in use. Retrying with suffix...", file=sys.stderr)
                suffix_username = f"{username}_{str(user_id)[:6]}"
                patch_payload["username"] = suffix_username
                patch_resp = requests.patch(profile_url, headers=patch_headers, params=patch_params, json=patch_payload)
            patch_resp.raise_for_status()
            print(f"✅ User profile updated successfully", file=sys.stderr)
        except requests.exceptions.RequestException as e:
            print(f"⚠️ Warning: Failed to update user profile: {e}", file=sys.stderr)
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Details: {json.dumps(error_detail)}", file=sys.stderr)
                except:
                    print(f"   Details: {e.response.text}", file=sys.stderr)
    else:
        # Insert profile if trigger didn't create it
        profile_payload = {
            "auth_user_id": user_id,
            "email": email,
            "username": username,
            "full_name": full_name,
            "role": "regular"
        }
        try:
            print(f"Creating user profile: {username}", file=sys.stderr)
            post_headers = {
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            }
            profile_response = requests.post(profile_url, headers=post_headers, json=profile_payload)
            if profile_response.status_code == 409:
                # Username conflict: generate a unique fallback and retry once
                print(f"⚠️ Username '{username}' already exists. Retrying with fallback...", file=sys.stderr)
                fallback_username = f"{username}_{str(user_id)[:6]}"
                profile_payload["username"] = fallback_username
                profile_response = requests.post(profile_url, headers=post_headers, json=profile_payload)
            profile_response.raise_for_status()
            print(f"✅ User profile created successfully", file=sys.stderr)
        except requests.exceptions.RequestException as e:
            # Profile creation might fail if user already exists or other issues
            # We still return success since the auth user was created
            print(f"⚠️ Warning: Failed to create user profile: {e}", file=sys.stderr)
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Details: {json.dumps(error_detail)}", file=sys.stderr)
                except:
                    print(f"   Details: {e.response.text}", file=sys.stderr)
    
    return {
        "user_id": user_id,
        "email": email,
        "username": username,
        "full_name": full_name
    }

def main():
    if len(sys.argv) != 5:
        print("Usage: python3 create_test_user.py <email> <password> <full_name> <username>", file=sys.stderr)
        sys.exit(1)
    
    email = sys.argv[1]
    password = sys.argv[2]
    full_name = sys.argv[3]
    username = sys.argv[4]
    
    try:
        result = create_test_user(email, password, full_name, username)
        # Print user_id to stdout for bash script to capture
        print(result["user_id"])
        sys.exit(0)
        
    except Exception as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

