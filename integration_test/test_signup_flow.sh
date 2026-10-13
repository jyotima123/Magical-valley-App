#!/bin/bash
# test_signup_flow.sh
# 
# This script runs integration tests for the signup flow.
# It tests user registration functionality including:
# - Creating a new user account
# - Email validation
# - Password validation
# - Error handling for existing users

set -e  # Exit on error

# Export environment variable for MailSlurp (used for email verification in tests)
export MAILSLURP_API_KEY="f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864"

echo "🚀 Running Signup Flow Integration Tests..."
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

# Function to run tests with graceful error handling
run_tests_with_cleanup() {
    local exit_code=0
    
    # Run signup tests
    run_test "integration_test/signup_tests.dart" "Signup"
    exit_code=$?
    
    return $exit_code
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

# Run the signup flow tests
echo ""
echo "🔄 Starting signup flow tests..."
run_tests_with_cleanup
TEST_EXIT_CODE=$?

# Print summary
echo ""
if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "🎉 All signup flow tests completed successfully!"
    exit 0
else
    echo "❌ Signup flow tests failed!"
    exit $TEST_EXIT_CODE
fi

