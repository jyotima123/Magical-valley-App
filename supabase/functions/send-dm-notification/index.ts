import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface DMNotificationPayload {
  conversationId: string;
  senderId: string;
  messageContent: string;
}

// ---------- 🔑 Firebase OAuth2 Helper ----------

async function getAccessToken() {
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  if (!privateKey || !clientEmail) throw new Error("Firebase credentials missing");

  const jwtHeader = { alg: "RS256", typ: "JWT" };
  const jwtClaimSet = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000),
  };

  const encoder = new TextEncoder();
  const base64UrlEncode = (input: string) =>
    btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const encodePart = (obj: unknown) => base64UrlEncode(JSON.stringify(obj));

  const unsignedJwt = `${encodePart(jwtHeader)}.${encodePart(jwtClaimSet)}`;

  const keyData = Uint8Array.from(
    atob(
      privateKey
        .replace("-----BEGIN PRIVATE KEY-----", "")
        .replace("-----END PRIVATE KEY-----", "")
        .replace(/\n/g, ""),
    ),
    (c) => c.charCodeAt(0),
  );

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(unsignedJwt),
  );

  const signedJwt = `${unsignedJwt}.${base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signature)),
  )}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`,
  });

  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) throw new Error("Failed to obtain access token");
  return tokenData.access_token as string;
}

// ---------- 📲 Send a single FCM message ----------

async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  conversationId: string,
): Promise<boolean> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: {
            notification_type: "direct_message",
            conversation_id: conversationId,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            notification: {
              icon: "ic_notification",
              color: "#2196F3",
              channel_id: "dm_notifications",
            },
          },
          apns: { payload: { aps: { sound: "default", badge: 1 } } },
        },
      }),
    },
  );
  return res.ok;
}

// ---------- 🔥 Main Function ----------

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const payload: DMNotificationPayload = await req.json();
    const { conversationId, senderId, messageContent } = payload;

    if (!conversationId || !senderId || !messageContent) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
      );
    }

    console.log("Processing DM notification for conversation:", conversationId, "sender:", senderId);

    // ---------- 1. Fetch the conversation ----------
    const { data: conversation, error: convError } = await supabase
      .from("direct_message_conversations")
      .select("user_id, organization_id")
      .eq("id", conversationId)
      .single();

    if (convError || !conversation) {
      console.error("Conversation not found:", convError);
      return new Response(
        JSON.stringify({ success: false, error: "Conversation not found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 },
      );
    }

    const { user_id: conversationUserId, organization_id: organizationId } = conversation;

    // ---------- 2. Determine recipients and notification title ----------
    // If the sender is the regular user → notify only the admins of the org (not superadmins)
    // If the sender is an admin → notify only the regular user (conversation owner)

    let recipientUserIds: string[] = [];
    let notificationTitle: string;

    const senderIsRegularUser = senderId === conversationUserId;

    if (senderIsRegularUser) {
      // Look up sender's display name for the notification title
      const { data: senderProfile } = await supabase
        .from("user_profiles")
        .select("full_name, username")
        .eq("id", senderId)
        .single();

      notificationTitle = senderProfile?.full_name ?? senderProfile?.username ?? "New message";

      // Get admins of this organization only (role = 'admin', NOT 'superadmin')
      const { data: adminRows, error: adminError } = await supabase
        .from("admin_organizations")
        .select("user_id, user_profiles!inner(role)")
        .eq("organization_id", organizationId)
        .eq("user_profiles.role", "admin");

      if (adminError) {
        console.error("Error fetching org admins:", adminError);
        throw adminError;
      }

      recipientUserIds = (adminRows ?? []).map((row: { user_id: string }) => row.user_id);
      console.log(`User sent to org. Notifying ${recipientUserIds.length} admin(s), excluding superadmins.`);
    } else {
      // Admin is replying → notify the regular user only
      // Look up organization name for the notification title
      const { data: org } = await supabase
        .from("organizations")
        .select("name")
        .eq("id", organizationId)
        .single();

      notificationTitle = org?.name ?? "New message";
      recipientUserIds = [conversationUserId];
      console.log("Admin sent message. Notifying regular user:", conversationUserId);
    }

    if (!recipientUserIds.length) {
      return new Response(
        JSON.stringify({ success: true, message: "No recipients to notify" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ---------- 3. Get FCM tokens for recipients ----------
    const { data: tokens, error: tokensError } = await supabase
      .from("user_fcm_tokens")
      .select("user_id, fcm_token")
      .in("user_id", recipientUserIds);

    if (tokensError) throw tokensError;

    if (!tokens?.length) {
      return new Response(
        JSON.stringify({ success: true, message: "No FCM tokens found for recipients" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ---------- 4. Send FCM notifications ----------
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    if (!projectId) throw new Error("FIREBASE_PROJECT_ID env var missing");

    const accessToken = await getAccessToken();

    // Truncate message body to 200 chars for the notification preview
    const notificationBody = messageContent.length > 200
      ? messageContent.substring(0, 197) + "..."
      : messageContent;

    let success = 0;
    let failure = 0;

    for (const { fcm_token } of tokens) {
      const sent = await sendFcmMessage(
        projectId,
        accessToken,
        fcm_token,
        notificationTitle,
        notificationBody,
        conversationId,
      );
      if (sent) success++;
      else failure++;
    }

    console.log(`DM notification result: ${success} sent, ${failure} failed`);

    return new Response(
      JSON.stringify({
        success: true,
        message: `Sent to ${success}/${tokens.length} recipient(s)`,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  } catch (err) {
    console.error("Error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err.message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});
