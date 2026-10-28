#!/bin/bash
# test_user_actions.sh
# 
# This script creates a test user, runs action-based tests with that user,
# and then cleans up by deleting the test user.
# 
# Flow:
# 1. Create a test user in Supabase using Python script
# 2. Run Flutter integration tests that use this specific test user
# 3. Delete the test user from Supabase using Python script

set -e  # Exit on error

# Configuration
TEST_EMAIL="test_user_$(date +%s)@integration.test"
TEST_PASSWORD="TestUser123!"
TEST_FULL_NAME="Test User for Integration"
TEST_USERNAME="testuser_$(date +%s)"
TEST_USER_ID=""

# Export environment variable for MailSlurp
export MAILSLURP_API_KEY="f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864"

echo "🚀 Running User-Specific Action Integration Tests..."
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root
cd "$PROJECT_ROOT"

# Make sure we have the dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Optional: Accept device ID as first argument
DEVICE_ID=${1:-""}

# Function to cleanup test user
cleanup() {
    if [ -n "$TEST_USER_ID" ]; then
        echo ""
        echo "🧹 Cleaning up test user..."
        python3 "$SCRIPT_DIR/scripts/delete_test_user.py" "$TEST_USER_ID" || true
        echo "✅ Cleanup completed"
    elif [ -n "$TEST_EMAIL" ]; then
        echo ""
        echo "🧹 Cleaning up test user..."
        python3 "$SCRIPT_DIR/scripts/delete_test_user.py" "$TEST_EMAIL" || true
        echo "✅ Cleanup completed"
    fi
}

# Set up trap to cleanup on exit (success or failure)
trap cleanup EXIT

# Function to run a test file
run_test() {
    local test_file=$1
    local test_name=$2
    
    echo ""
    echo "🧪 Running $test_name tests..."
    echo "📁 Test file: $test_file"
    
    if [ -z "$DEVICE_ID" ]; then
        flutter test $test_file --dart-define=INTEGRATION_TEST=true
    else
        flutter test $test_file -d $DEVICE_ID --dart-define=INTEGRATION_TEST=true
    fi
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "✅ $test_name tests passed!"
    else
        echo "❌ $test_name tests failed!"
        return $exit_code
    fi
}

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

# Check if required Python packages are installed
echo "🔍 Checking Python dependencies..."
python3 -c "import requests" 2>/dev/null || {
    echo "❌ Python 'requests' package not found"
    echo "   Install it with: pip3 install requests"
    exit 1
}

# Run environment check
echo "🔍 Running Flutter environment configuration check..."
flutter test integration_test/test_env_check.dart

if [ $? -eq 0 ]; then
    echo "✅ Environment check passed!"
else
    echo "❌ Environment check failed!"
    exit 1
fi

# Step 1: Create test user
echo ""
echo "👤 Creating test user..."
echo "   Email: $TEST_EMAIL"
echo "   Username: $TEST_USERNAME"

if TEST_USER_ID=$(python3 "$SCRIPT_DIR/scripts/create_test_user.py" "$TEST_EMAIL" "$TEST_PASSWORD" "$TEST_FULL_NAME" "$TEST_USERNAME"); then
    echo "✅ Test user created successfully!"
    echo "   User ID: $TEST_USER_ID"
    
    # Export test user credentials for use in tests (if needed)
    export TEST_USER_EMAIL="$TEST_EMAIL"
    export TEST_USER_PASSWORD="$TEST_PASSWORD"
    export TEST_USER_FULL_NAME="$TEST_FULL_NAME"
    export TEST_USER_USERNAME="$TEST_USERNAME"
    
else
    echo "❌ Failed to create test user!"
    exit 1
fi

# Step 2: Wait a moment for user to be fully ready
echo ""
echo "⏳ Waiting for user to be ready..."
sleep 2

# Step 3: Run integration tests
echo ""
echo "🔄 Starting user action tests..."
TEST_EXIT_CODE=0

# Function to handle test execution and capture exit codes
run_tests_for_user() {
    local overall_exit_code=0
    
    # You can add multiple test files here
    # For now, we'll use the chat_tests.dart as an example
    
    # Example: If you want to run specific tests with this user
    # You might want to create a new test file like user_action_tests.dart
    # that uses the TEST_USER_EMAIL and TEST_USER_PASSWORD environment variables
    
    # For demonstration, we'll just run the chat tests
    # In a real scenario, you might want to create dedicated tests
    
    echo "⚠️  Note: Running default tests. Consider creating dedicated user_action_tests.dart"
    run_test "integration_test/chat_tests.dart" "Chat Actions" || overall_exit_code=$?
    
    return $overall_exit_code
}

run_tests_for_user
TEST_EXIT_CODE=$?

# Print summary
echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "🎉 All user action tests completed successfully!"
else
    echo "❌ Some user action tests failed!"
fi

# The cleanup function will be called by the trap
echo ""
echo "🏁 Test run completed. User will be cleaned up automatically."

# Exit with the test exit code
exit $TEST_EXIT_CODE

