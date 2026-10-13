#!/bin/bash

# ============================================================================
# FCM NOTIFICATION TESTER
# ============================================================================
# This script helps you test push notifications manually

echo "🔔 FCM Notification Tester"
echo "=========================="
echo ""

# Configuration - Replace these with your actual values
SUPABASE_PROJECT_REF="yavxzgcgoasicjprzfcv"  # Your project ref from Supabase URL
SUPABASE_ANON_KEY="your-anon-key-here"        # From Project Settings → API
ORGANIZATION_ID="14deab1d-0cde-4030-a604-045feeb63705"  # An org you're following

# Prompt for configuration if not set
if [ "$SUPABASE_ANON_KEY" = "your-anon-key-here" ]; then
    echo "⚠️  Please edit this script and set your configuration values"
    echo ""
    echo "Required values:"
    echo "  - SUPABASE_PROJECT_REF: Your Supabase project reference"
    echo "  - SUPABASE_ANON_KEY: Your Supabase anon key"
    echo "  - ORGANIZATION_ID: An organization/channel ID that you're following"
    echo ""
    exit 1
fi

# Prepare the request
FUNCTION_URL="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/send-fcm-notification"

# Test payload
PAYLOAD=$(cat <<EOF
{
  "postId": "test-$(date +%s)",
  "channelId": "${ORGANIZATION_ID}",
  "title": "Test Notification 🎉",
  "body": "This is a test notification sent at $(date '+%H:%M:%S')",
  "authorName": "Test User"
}
EOF
)

echo "📤 Sending test notification..."
echo ""
echo "URL: $FUNCTION_URL"
echo "Payload: $PAYLOAD"
echo ""

# Send the request
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$FUNCTION_URL" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# Parse response
HTTP_BODY=$(echo "$RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
HTTP_STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

echo "Status Code: $HTTP_STATUS"
echo ""
echo "Response:"
echo "$HTTP_BODY" | jq '.' 2>/dev/null || echo "$HTTP_BODY"
echo ""

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Notification sent successfully!"
else
    echo "❌ Failed to send notification"
fi

echo ""
echo "=========================="
echo ""
echo "Troubleshooting tips:"
echo "1. Make sure the Edge Function is deployed: supabase functions deploy send-fcm-notification"
echo "2. Verify FCM_SERVER_KEY is set in Supabase Edge Functions environment"
echo "3. Check that you have FCM tokens stored in the database"
echo "4. Ensure you're following the organization with ID: $ORGANIZATION_ID"
echo "5. Check Supabase Edge Function logs for errors"

