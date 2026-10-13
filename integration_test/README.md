# Integration Tests

This directory contains integration tests for the MVC App. The tests are organized into separate test suites that can be run individually or together.

## Overview

Integration tests verify the complete user flows in the app, testing interactions between different parts of the system including:
- Authentication (Sign up, Login, Logout)
- User interactions (Chat, Posts, etc.)
- Database operations
- API integrations

## Test Organization

The tests are now separated into 3 main categories:

### 1. Signup Flow Tests
Tests the user registration functionality:
- Creating new accounts
- Email validation
- Password validation
- Error handling for duplicate accounts

**Run with:**
```bash
./integration_test/test_signup_flow.sh
```

### 2. Login & Logout Flow Tests
Tests authentication functionality:
- Successful login with valid credentials
- Failed login with invalid credentials
- Token validation
- Logout functionality
- Session management

**Run with:**
```bash
./integration_test/test_login_logout_flow.sh
```

### 3. User-Specific Action Tests
Creates a test user, runs action-based tests, and cleans up:
- Creates a test user in the database
- Runs tests with that specific user
- Automatically deletes the test user after completion

**Run with:**
```bash
./integration_test/test_user_actions.sh
```

## Prerequisites

Before running integration tests, you need:

1. **Flutter SDK** installed and configured
2. **Python 3** installed
3. **Python `requests` package**:
   ```bash
   pip3 install requests
   ```
4. **Supabase Service Role Key** configured in `.env_qa`
   - See `scripts/README.md` for instructions on getting this key
5. **MailSlurp API Key** configured (for email verification tests)

## Running Tests

### Run All Tests Together

Use the original script to run all tests in sequence:

```bash
./integration_test/run_integration_tests.sh
```

### Run Individual Test Categories

```bash
# Signup tests only
./integration_test/test_signup_flow.sh

# Login/logout tests only
./integration_test/test_login_logout_flow.sh

# User action tests only
./integration_test/test_user_actions.sh
```

### Run on Specific Device

All scripts accept an optional device ID:

```bash
./integration_test/test_signup_flow.sh <device_id>
```

To list available devices:
```bash
flutter devices
```

## Test File Structure

```
integration_test/
├── signup_tests.dart          # Signup flow tests
├── login_tests.dart           # Login/logout tests
├── chat_tests.dart            # Chat functionality tests
├── password_reset_tests.dart  # Password reset tests
├── test_helpers.dart          # Shared test utilities
├── auth_helpers.dart          # Authentication helper functions
├── navigation_helpers.dart    # Navigation helper functions
├── email_helpers.dart         # Email verification helpers
├── test_config.dart           # Test configuration
├── test_env_check.dart        # Environment validation
├── scripts/                   # Python scripts for user management
│   ├── create_test_user.py   # Create test users
│   ├── delete_test_user.py   # Delete test users
│   └── README.md             # Scripts documentation
├── test_signup_flow.sh       # Signup tests script
├── test_login_logout_flow.sh # Login/logout tests script
├── test_user_actions.sh      # User action tests script
└── run_integration_tests.sh  # Run all tests
```

## Test Configuration

### Environment Variables

The tests use the following environment variables:

- `MAILSLURP_API_KEY`: For email verification in tests
- `TEST_USER_EMAIL`: Test user email (set by test_user_actions.sh)
- `TEST_USER_PASSWORD`: Test user password (set by test_user_actions.sh)
- `INTEGRATION_TEST`: Set to `true` during test runs

### Test Data

Test credentials are defined in `test_helpers.dart`:

```dart
const String testEmail = 'alisson+1@fullpond.co';
const String testPassword = '12345678Aa';
const String testFullName = 'Test User';
```

## Test User Management

The `test_user_actions.sh` script uses Python scripts to manage test users:

1. **Creation**: Creates users directly in Supabase using the service role key
2. **Testing**: Runs Flutter tests with the created user
3. **Cleanup**: Automatically deletes the test user, even if tests fail

The Python scripts handle:
- Creating auth users in Supabase
- Creating user profiles in the database
- Deleting users from both auth and profiles
- Error handling and logging

See `scripts/README.md` for detailed documentation on the Python scripts.

## Debugging Tests

### Enable Verbose Output

Flutter tests already have detailed logging enabled. Check the console output for:
- Step-by-step navigation logs
- Error messages and stack traces
- API call results

### Common Issues

**Test Environment Not Set Up**
```bash
# Run environment check
flutter test integration_test/test_env_check.dart
```

**Python Scripts Failing**
```bash
# Check if requests is installed
python3 -c "import requests"

# Test create script
python3 integration_test/scripts/create_test_user.py test@example.com "Test123!" "Test User" "testuser"
```

**Device Not Found**
```bash
# List available devices
flutter devices

# Run with specific device
./integration_test/test_signup_flow.sh <device_id>
```

### Test Failures

If a test fails:
1. Check the console output for specific error messages
2. Verify the test environment is properly configured
3. Ensure the app is running the QA/Development environment (`.env_qa`)
4. Check Supabase dashboard for any issues
5. Verify test user credentials if using user-specific tests

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run Integration Tests
  run: |
    cd integration_test
    ./test_signup_flow.sh
    ./test_login_logout_flow.sh
    ./test_user_actions.sh
```

Make sure to:
- Set up environment variables in CI
- Configure Supabase service role key as a secret
- Set up a test device/emulator
- Handle test cleanup on failure

## Best Practices

1. **Isolation**: Each test category can be run independently
2. **Cleanup**: Test users are automatically cleaned up
3. **Idempotency**: Tests can be run multiple times safely
4. **Error Handling**: Scripts handle errors gracefully
5. **Logging**: Detailed logs help with debugging

## Contributing

When adding new tests:

1. Add test files to the `integration_test/` directory
2. Follow the existing test structure
3. Use helper functions from `test_helpers.dart`, `auth_helpers.dart`, etc.
4. Update the appropriate test script if adding a new category
5. Test locally before committing

## Resources

- [Flutter Integration Testing](https://docs.flutter.dev/testing/integration-tests)
- [Supabase Admin API](https://supabase.com/docs/reference/javascript/auth-admin-api)
- [MailSlurp Documentation](https://docs.mailslurp.com/)

