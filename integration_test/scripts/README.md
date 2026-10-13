# Integration Test Scripts

This directory contains Python scripts for managing test users in Supabase during integration testing.

## Prerequisites

1. **Python 3** must be installed on your system
2. **Python `requests` package** must be installed:
   ```bash
   pip3 install requests
   ```

3. **Supabase Service Role Key** must be configured in your `.env_qa` file

## Getting Your Supabase Service Role Key

The service role key is required to create and delete users directly in the Supabase database. Here's how to get it:

1. Go to your [Supabase Dashboard](https://app.supabase.com)
2. Select your project (`yavxzgcgoasicjprzfcv`)
3. Navigate to **Settings** → **API**
4. Find the **service_role** key in the **Project API keys** section
5. Copy the key (it starts with `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`)
6. Add it to your `.env_qa` file:

   ```bash
   SUPABASE_SERVICE_ROLE_KEY=your-actual-service-role-key-here
   ```

⚠️ **Important:** The service role key has admin privileges. Never commit it to version control or share it publicly.

## Scripts

### `create_test_user.py`

Creates a test user in Supabase Auth and User Profiles.

**Usage:**
```bash
python3 create_test_user.py <email> <password> <full_name> <username>
```

**Example:**
```bash
python3 create_test_user.py test@example.com "Test123!" "Test User" "testuser"
```

**Returns:**
- Exit code 0 on success with `user_id` printed to stdout
- Exit code 1 on failure with error message

### `delete_test_user.py`

Deletes a test user from Supabase Auth and User Profiles.

**Usage:**
```bash
python3 delete_test_user.py <user_id_or_email>
```

**Example:**
```bash
# By email
python3 delete_test_user.py test@example.com

# By user ID
python3 delete_test_user.py 123e4567-e89b-12d3-a456-426614174000
```

**Returns:**
- Exit code 0 on success
- Exit code 1 on failure

## Environment Setup

The scripts automatically read configuration from:
1. Environment variable `SUPABASE_SERVICE_ROLE_KEY`
2. `.env_qa` file in the project root

They use the Supabase URL configured in `.env_qa` for your project.

## Integration with Test Scripts

These scripts are used by the main integration test bash scripts:

- `test_user_actions.sh` - Uses both scripts to create and cleanup test users

The test scripts handle:
- Creating test users before running tests
- Passing credentials to Flutter tests via environment variables
- Automatically cleaning up test users after tests complete (even on failure)

## Troubleshooting

### "SUPABASE_SERVICE_ROLE_KEY not found"

Make sure you've added the service role key to `.env_qa`:
```bash
SUPABASE_SERVICE_ROLE_KEY=your-actual-key-here
```

### "Python 'requests' package not found"

Install the requests package:
```bash
pip3 install requests
```

### "Failed to create auth user"

- Verify your service role key is correct
- Check that the email isn't already in use
- Ensure your Supabase project is active and accessible

### "Failed to delete user"

- The user may have already been deleted
- Check that the email/user_id is correct
- Verify your service role key has admin privileges

## Security Notes

⚠️ **Never commit the service role key to version control!**

- The `.env_qa` file is already in `.gitignore`
- The service role key bypasses Row Level Security (RLS) policies
- Anyone with this key has admin access to your Supabase project

