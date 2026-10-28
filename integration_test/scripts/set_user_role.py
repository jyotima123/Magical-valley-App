#!/usr/bin/env python3
"""
Set a user's role (regular, admin, superadmin) and manage admin organization assignments.

Usage:
    python3 set_user_role.py <email> <role> [--organization-id <uuid>]

Behaviour:
    • Updates the `user_profiles.role` field.
    • When setting role to `admin`, requires an organization id and assigns the user
      to `admin_organizations`.
    • When switching away from `admin`, removes existing admin organization rows.

Reads SUPABASE_SERVICE_ROLE_KEY from env or ../../.env_qa.
"""

import argparse
import os
import sys
import time
from typing import Optional

try:
    import requests  # type: ignore[import]
except ImportError as exc:  # pragma: no cover - import time guard
    raise ImportError(
        "The 'requests' package is required. Install it with 'pip install requests'."
    ) from exc

SUPABASE_URL = "https://yavxzgcgoasicjprzfcv.supabase.co"

SUPPORTED_ROLES = {"regular", "admin", "superadmin"}
PROFILE_POLL_ATTEMPTS = 10
PROFILE_POLL_DELAY_SEC = 0.5


def get_service_role_key() -> str:
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        return key
    try:
        env_file = os.path.join(os.path.dirname(__file__), "../../.env_qa")
        with open(env_file, "r", encoding="utf-8") as env_handle:
            for line in env_handle:
                if line.startswith("SUPABASE_SERVICE_ROLE_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    except Exception:
        pass
    raise ValueError("SUPABASE_SERVICE_ROLE_KEY not found. Set env var or .env_qa entry.")


def build_headers(service_key: str, *, include_prefer: bool = False) -> dict:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    if include_prefer:
        headers["Prefer"] = "return=representation"
    return headers


def get_profile_by_email(email: str, headers: dict) -> Optional[dict]:
    url = f"{SUPABASE_URL}/rest/v1/user_profiles"
    params = {"email": f"eq.{email}", "select": "id,email,role"}
    resp = requests.get(url, headers=headers, params=params, timeout=10)
    if resp.status_code == 200:
        data = resp.json()
        if isinstance(data, list) and data:
            return data[0]
    return None


def wait_for_profile(email: str, headers: dict) -> Optional[dict]:
    for attempt in range(1, PROFILE_POLL_ATTEMPTS + 1):
        profile = get_profile_by_email(email, headers)
        if profile:
            if attempt > 1:
                print(f"ℹ️ Profile for {email} available after {attempt} attempts.", file=sys.stderr)
            return profile
        time.sleep(PROFILE_POLL_DELAY_SEC)
    return None


def update_role(profile_id: str, role: str, headers: dict) -> bool:
    url = f"{SUPABASE_URL}/rest/v1/user_profiles"
    params = {"id": f"eq.{profile_id}"}
    resp = requests.patch(url, headers=headers, params=params, json={"role": role}, timeout=10)
    if resp.status_code in (200, 204):
        return True
    print(f"❌ Failed to update role: {resp.status_code} {resp.text}", file=sys.stderr)
    return False


def clear_admin_assignments(profile_id: str, headers: dict) -> None:
    url = f"{SUPABASE_URL}/rest/v1/admin_organizations"
    params = {"user_id": f"eq.{profile_id}"}
    try:
        resp = requests.delete(url, headers=headers, params=params, timeout=10)
        if resp.status_code not in (200, 204):
            print(f"⚠️ Failed to clear admin assignments ({resp.status_code}): {resp.text}", file=sys.stderr)
    except requests.RequestException as exc:
        print(f"⚠️ Error clearing admin assignments: {exc}", file=sys.stderr)


def assign_admin_to_org(profile_id: str, organization_id: str, headers: dict) -> bool:
    url = f"{SUPABASE_URL}/rest/v1/admin_organizations"
    payload = {"user_id": profile_id, "organization_id": organization_id}
    # Ensure a clean state before inserting the new record
    clear_admin_assignments(profile_id, headers)
    resp = requests.post(
        url,
        headers={**headers, "Prefer": "resolution=merge-duplicates,return=minimal"},
        json=payload,
        timeout=10,
    )
    if resp.status_code in (200, 201, 204):
        print(f"✅ Assigned admin user {profile_id} to organization {organization_id}", file=sys.stderr)
        return True
    if resp.status_code == 409:
        print(f"ℹ️ Admin assignment already exists for organization {organization_id}", file=sys.stderr)
        return True
    print(f"❌ Failed to assign admin organization: {resp.status_code} {resp.text}", file=sys.stderr)
    return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Update Supabase user role for integration tests.")
    parser.add_argument("email", help="Email of the user to update.")
    parser.add_argument("role", choices=sorted(SUPPORTED_ROLES), help="Role to set (regular, admin, superadmin).")
    parser.add_argument(
        "--organization-id",
        dest="organization_id",
        help="Organization UUID to assign when role is admin.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    email = args.email.strip().lower()
    role = args.role.strip().lower()
    organization_id = args.organization_id

    if role == "admin" and not organization_id:
        print("❌ organization-id is required when assigning admin role.", file=sys.stderr)
        sys.exit(1)

    service_key = get_service_role_key()
    base_headers = build_headers(service_key, include_prefer=True)

    profile = wait_for_profile(email, base_headers)
    if not profile:
        print(f"❌ user profile not found for {email}", file=sys.stderr)
        sys.exit(1)

    profile_id = profile.get("id")
    if not profile_id:
        print(f"❌ Profile for {email} missing id field.", file=sys.stderr)
        sys.exit(1)

    if not update_role(profile_id, role, base_headers):
        sys.exit(1)

    if role == "admin":
        if not assign_admin_to_org(profile_id, organization_id, build_headers(service_key)):
            sys.exit(1)
    else:
        clear_admin_assignments(profile_id, build_headers(service_key))

    # Surface the profile id for chaining scripts.
    print(profile_id)
    sys.exit(0)


if __name__ == "__main__":
    main()