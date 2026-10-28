#!/bin/bash
# run_integration_tests.sh

export MAILSLURP_API_KEY="f4324fd02b81e84cddc4410f8bb5da38b0353846d0a490b031bf36f73b725864"

echo "🚀 Running Flutter Integration Tests..."

# Make sure we have the dependencies
echo "📦 Getting dependencies..."
flutter pub get

DEVICE_ID=${1:-""}

# First run environment check
echo "🔍 Running environment configuration check..."
flutter test integration_test/test_env_check.dart

if [ $? -eq 0 ]; then
    echo "✅ Environment check passed!"
else
    echo "❌ Environment check failed!"
    exit 1
fi

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

# Run individual test files
echo ""
echo "🔄 Running individual test suites..."

# Login tests
run_test "integration_test/login_tests.dart" "Login"
if [ $? -ne 0 ]; then exit 1; fi

# Signup tests
run_test "integration_test/signup_tests.dart" "Signup"
if [ $? -ne 0 ]; then exit 1; fi

# Password reset tests
run_test "integration_test/password_reset_tests.dart" "Password Reset"
if [ $? -ne 0 ]; then exit 1; fi

# Chat tests
run_test "integration_test/chat_tests.dart" "Chat"
if [ $? -ne 0 ]; then exit 1; fi

echo ""
echo "🎉 All integration tests completed successfully!"

