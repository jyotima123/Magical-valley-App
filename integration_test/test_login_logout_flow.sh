#!/bin/bash
# test_login_logout_flow.sh
# 
# This script runs integration tests for the login and logout flow.
# It tests authentication functionality including:
# - Successful login with valid credentials
# - Failed login with invalid credentials
# - Token validation after login
# - User logout functionality
# - Session management

# Export environment variable for MailSlurp (used for email verification in tests)
export MAILSLURP_API_KEY="f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864"

echo "🚀 Running Login & Logout Flow Integration Tests..."
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

# Ensure script fails on unset variables and pipeline errors
set -euo pipefail

# Make sure we have the dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Optional: Accept device ID as first argument
DEVICE_ID=${1:-""}

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$2
    shift 2
    local extra_args=("$@")

    echo ""
    echo "🧪 Running $test_name tests..."
    echo "📁 Test file: $test_file"

    local flutter_args=()
    if [ -n "$DEVICE_ID" ]; then
        flutter_args+=("-d" "$DEVICE_ID")
    fi
    flutter_args+=("--dart-define=INTEGRATION_TEST=true")
    flutter_args+=("${extra_args[@]}")

    if flutter test "$test_file" "${flutter_args[@]}"; then
        echo "✅ $test_name tests passed!"
    else
        local exit_code=$?
        echo "❌ $test_name tests failed!"
        return $exit_code
    fi
}

# -----------------------------------------------------------------------------
# Temporary role-based test users
# -----------------------------------------------------------------------------
ROLE_TEST_PASSWORD=${ROLE_TEST_PASSWORD:-"12345678Aa"}
ADMIN_ORG_ID=${ADMIN_ORG_ID:-"14deab1d-0cde-4030-a604-045feeb63705"}
UNIQUE_SUFFIX="$(date +%s%N)"

REG_EMAIL=""
SUP_EMAIL=""
ADM_EMAIL=""

cleanup() {
    echo -e "\n🧹 Cleaning up temporary login role users..."
    if [ -n "$REG_EMAIL" ]; then
        python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$REG_EMAIL" || true
    fi
    if [ -n "$SUP_EMAIL" ]; then
        python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$SUP_EMAIL" || true
    fi
    if [ -n "$ADM_EMAIL" ]; then
        python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$ADM_EMAIL" || true
    fi
}
trap cleanup EXIT

create_role_user() {
    local role=$1
    local email_var=$2
    local full_name=$3
    local username_prefix=$4

    local email="integration+${role}.${UNIQUE_SUFFIX}@fullpond.co"
    local username="${username_prefix}_${UNIQUE_SUFFIX}"
    username=$(echo "$username" | cut -c1-24)

    echo -e "\n👤 Creating $role user: $email"
    python3 "$PROJECT_ROOT/integration_test/scripts/create_test_user.py" "$email" "$ROLE_TEST_PASSWORD" "$full_name" "$username" >/dev/null

    case "$role" in
        admin)
            python3 "$PROJECT_ROOT/integration_test/scripts/set_user_role.py" "$email" admin --organization-id "$ADMIN_ORG_ID" >/dev/null
            ;;
        superadmin)
            python3 "$PROJECT_ROOT/integration_test/scripts/set_user_role.py" "$email" superadmin >/dev/null
            ;;
        regular)
            # No role update required; ensure profile exists
            ;;
        *)
            echo "❌ Unknown role: $role"
            exit 1
            ;;
    esac

    printf -v "$email_var" '%s' "$email"
    return 0
}

# Run environment check first
echo "🔍 Running environment configuration check..."
flutter test integration_test/test_env_check.dart

if [ $? -eq 0 ]; then
    echo "✅ Environment check passed!"
else
    echo "❌ Environment check failed!"
    exit 1
fi

# -----------------------------------------------------------------------------
# Create dedicated users for role-based login tests
# -----------------------------------------------------------------------------
create_role_user "regular" REG_EMAIL "Regular Role Test User" "regular_role"
create_role_user "superadmin" SUP_EMAIL "Superadmin Role Test User" "superadmin_role"
create_role_user "admin" ADM_EMAIL "Admin Role Test User" "admin_role"

ROLE_LOGIN_FLAGS=(
    "--dart-define=LOGIN_TEST_REGULAR_EMAIL=$REG_EMAIL"
    "--dart-define=LOGIN_TEST_REGULAR_PASSWORD=$ROLE_TEST_PASSWORD"
    "--dart-define=LOGIN_TEST_SUPERADMIN_EMAIL=$SUP_EMAIL"
    "--dart-define=LOGIN_TEST_SUPERADMIN_PASSWORD=$ROLE_TEST_PASSWORD"
    "--dart-define=LOGIN_TEST_ADMIN_EMAIL=$ADM_EMAIL"
    "--dart-define=LOGIN_TEST_ADMIN_PASSWORD=$ROLE_TEST_PASSWORD"
)

# Run the login tests
echo ""
echo "🔄 Starting login and logout flow tests..."
echo "ℹ️ Tests cover the new 'Continue with email' step in the login flow."
run_test "integration_test/login_tests.dart" "Login & Logout" "${ROLE_LOGIN_FLAGS[@]}"
TEST_EXIT_CODE=$?

# Print summary
echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "🎉 All login/logout flow tests completed successfully!"
    exit 0
else
    echo "❌ Login/logout flow tests failed!"
    exit $TEST_EXIT_CODE
fi

