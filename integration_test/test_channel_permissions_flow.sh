#!/bin/bash
# Orchestrates channel permission flow tests with user setup and cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🚀 Running Channel Permissions Flow Tests..."

# Configurable test users (unique per run if desired)
REG_EMAIL=${REG_EMAIL:-"alisson+reg_$(date +%s)@fullpond.co"}
ADM_EMAIL=${ADM_EMAIL:-"alisson+adm_$(date +%s)@fullpond.co"}
SUP_EMAIL=${SUP_EMAIL:-"alisson+sup_$(date +%s)@fullpond.co"}
TEST_PASSWORD=${TEST_PASSWORD:-"12345678"}
ADMIN_ORG_ID=${ADMIN_ORG_ID:-"14deab1d-0cde-4030-a604-045feeb63705"}

cleanup() {
  echo "\n🧹 Cleaning up test users..."
  python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$REG_EMAIL" || true
  python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$ADM_EMAIL" || true
  python3 "$PROJECT_ROOT/integration_test/scripts/delete_test_user.py" "$SUP_EMAIL" || true
}
trap cleanup EXIT

echo "📦 Getting Flutter dependencies..."
flutter pub get

echo "\n👤 Creating Regular user: $REG_EMAIL"
python3 "$PROJECT_ROOT/integration_test/scripts/create_test_user.py" "$REG_EMAIL" "$TEST_PASSWORD" "Regular Test" "reg_user"

echo "\n👤 Creating Admin user: $ADM_EMAIL"
python3 "$PROJECT_ROOT/integration_test/scripts/create_test_user.py" "$ADM_EMAIL" "$TEST_PASSWORD" "Admin Test" "adm_user"
python3 "$PROJECT_ROOT/integration_test/scripts/set_user_role.py" "$ADM_EMAIL" admin --organization-id "$ADMIN_ORG_ID"

echo "\n👤 Creating Superadmin user: $SUP_EMAIL"
python3 "$PROJECT_ROOT/integration_test/scripts/create_test_user.py" "$SUP_EMAIL" "$TEST_PASSWORD" "Superadmin Test" "sup_user"
python3 "$PROJECT_ROOT/integration_test/scripts/set_user_role.py" "$SUP_EMAIL" superadmin

echo "\n🔧 Passing test user credentials to Dart via --dart-define"

FLAGS=(
  --dart-define=INTEGRATION_TEST=true
  --dart-define=REG_EMAIL="$REG_EMAIL"
  --dart-define=REG_PASSWORD="$TEST_PASSWORD"
  --dart-define=ADM_EMAIL="$ADM_EMAIL"
  --dart-define=ADM_PASSWORD="$TEST_PASSWORD"
  --dart-define=SUP_EMAIL="$SUP_EMAIL"
  --dart-define=SUP_PASSWORD="$TEST_PASSWORD"
)

TEST_FILE="integration_test/channel_permissions_flow_test.dart"

echo "\n🧪 Running Channel Permissions flow test..."
flutter test "$TEST_FILE" "${FLAGS[@]}"

echo "\n🎉 Channel permissions flow test completed!"


