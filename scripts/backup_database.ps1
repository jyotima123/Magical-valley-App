# Get your access token from https://supabase.com/dashboard/account/tokens
export SUPABASE_ACCESS_TOKEN="your-access-token"
export PROJECT_REF="your-project-ref"

# List all available backups
curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
"https://api.supabase.com/v1/projects/$PROJECT_REF/database/backups"

# Restore from a PITR backup (replace Unix timestamp with desired restore point)
curl -X POST "https://api.supabase.com/v1/projects/$PROJECT_REF/database/backups/restore-pitr" \
-H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
-H "Content-Type: application/json" \
-d '{
    "recovery_time_target_unix": "1735689600"
  }'