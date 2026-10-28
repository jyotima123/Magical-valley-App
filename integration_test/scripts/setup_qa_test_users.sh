#!/usr/bin/env zsh
#
# Setup QA test users for manual testing.
# This script creates predictable test users with different roles:
# - 1 superadmin user
# - 1 regular user
# - 2 admin users (assigned to different organizations)
#
# If users already exist, they will be deleted and recreated to ensure
# a clean, predictable state for QA testing.
#

set -e  # Exit on error


# Script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$PROJECT_ROOT/integration_test/mvc_tests/bin/activate"

# Python scripts
CREATE_USER_SCRIPT="$SCRIPT_DIR/create_test_user.py"
DELETE_USER_SCRIPT="$SCRIPT_DIR/delete_test_user.py"
SET_ROLE_SCRIPT="$SCRIPT_DIR/set_user_role.py"

# Organization IDs
ORG_ART_TEST="14deab1d-0cde-4030-a604-045feeb63705"
ORG_QA_TEST="513b3132-1fe1-4cdf-93a0-69bceed73f1e"

# Test user definitions
# Format: email|password|full_name|username|role|organization_id
declare -a TEST_USERS=(
  "qa-superadmin@test.local|TestPass123!|QA Superadmin|qa_superadmin|superadmin|"
  "qa-regular@test.local|TestPass123!|QA Regular User|qa_regular|regular|"
  "qa-admin-art@test.local|TestPass123!|QA Admin Art|qa_admin_art|admin|$ORG_ART_TEST"
  "qa-admin-qa@test.local|TestPass123!|QA Admin QA|qa_admin_qa|admin|$ORG_QA_TEST"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to print colored messages
print_info() {
  echo "${BLUE}ℹ️  $1${NC}"
}

print_success() {
  echo "${GREEN}✅ $1${NC}"
}

print_warning() {
  echo "${YELLOW}⚠️  $1${NC}"
}

print_error() {
  echo "${RED}❌ $1${NC}" >&2
}

# Check if Python scripts exist
check_scripts() {
  local missing_scripts=()
  
  [[ ! -f "$CREATE_USER_SCRIPT" ]] && missing_scripts+=("create_test_user.py")
  [[ ! -f "$DELETE_USER_SCRIPT" ]] && missing_scripts+=("delete_test_user.py")
  [[ ! -f "$SET_ROLE_SCRIPT" ]] && missing_scripts+=("set_user_role.py")
  
  if [[ ${#missing_scripts[@]} -gt 0 ]]; then
    print_error "Missing required scripts: ${missing_scripts[*]}"
    exit 1
  fi
  
  # Make scripts executable
  chmod +x "$CREATE_USER_SCRIPT" "$DELETE_USER_SCRIPT" "$SET_ROLE_SCRIPT"
}

# Delete a user if it exists
delete_user_if_exists() {
  local email="$1"
  
  print_info "Checking if user exists: $email"
  
  # Try to delete (script handles non-existence gracefully)
  if python3 "$DELETE_USER_SCRIPT" "$email" 2>/dev/null; then
    print_success "Deleted existing user: $email"
    # Small delay to ensure deletion is complete
    sleep 1
  else
    print_info "User does not exist or already deleted: $email"
  fi
}

# Create a test user
create_user() {
  local email="$1"
  local password="$2"
  local full_name="$3"
  local username="$4"
  
  print_info "Creating user: $email ($username)"
  
  if user_id=$(python3 "$CREATE_USER_SCRIPT" "$email" "$password" "$full_name" "$username" 2>&1); then
    print_success "Created user: $email (ID: ${user_id//$'\n'})"
    echo "${user_id//$'\n'}"  # Return user_id without newlines
  else
    print_error "Failed to create user: $email"
    return 1
  fi
}

# Set user role
set_user_role() {
  local email="$1"
  local role="$2"
  local org_id="$3"
  
  print_info "Setting role '$role' for user: $email"
  
  if [[ -n "$org_id" ]]; then
    if python3 "$SET_ROLE_SCRIPT" "$email" "$role" --organization-id "$org_id" 2>&1; then
      print_success "Set role '$role' for user: $email (org: $org_id)"
    else
      print_error "Failed to set role for user: $email"
      return 1
    fi
  else
    if python3 "$SET_ROLE_SCRIPT" "$email" "$role" 2>&1; then
      print_success "Set role '$role' for user: $email"
    else
      print_error "Failed to set role for user: $email"
      return 1
    fi
  fi
}

# Main execution
main() {
  print_info "Starting QA test user setup..."
  print_info "This will delete and recreate test users for predictable QA testing"
  echo ""
  
  # Check scripts exist
  check_scripts
  
  # Step 1: Delete existing users
  print_info "Step 1: Cleaning up existing test users..."
  for user_def in "${TEST_USERS[@]}"; do
    IFS='|' read -r email password full_name username role org_id <<< "$user_def"
    delete_user_if_exists "$email"
  done
  
  echo ""
  print_info "Step 2: Creating new test users..."
  
  # Step 2: Create users
  for user_def in "${TEST_USERS[@]}"; do
    IFS='|' read -r email password full_name username role org_id <<< "$user_def"
    
    echo ""
    print_info "Processing: $email ($role)"
    
    # Create user
    if ! create_user "$email" "$password" "$full_name" "$username"; then
      print_error "Failed to create user: $email"
      exit 1
    fi
    
    # Small delay to ensure user is fully created
    sleep 1
    
    # Set role (this also handles admin organization assignment)
    if [[ -n "$org_id" ]]; then
      if ! set_user_role "$email" "$role" "$org_id"; then
        print_error "Failed to set role for user: $email"
        exit 1
      fi
    else
      if ! set_user_role "$email" "$role" ""; then
        print_error "Failed to set role for user: $email"
        exit 1
      fi
    fi
  done
  
  echo ""
  print_success "QA test users setup complete!"
  echo ""
  print_info "Created users:"
  echo "  • qa-superadmin@test.local (superadmin)"
  echo "  • qa-regular@test.local (regular)"
  echo "  • qa-admin-art@test.local (admin - Art Test org)"
  echo "  • qa-admin-qa@test.local (admin - QA Organization Test org)"
  echo ""
  print_info "All users have password: TestPass123!"
}

# Run main function
main "$@"

