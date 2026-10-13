import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface VehicleInquiryNotificationPayload {
  conversationId: string;
  senderId: string;
  messageContent: string;
  messageType?: string;
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
            notification_type: "vehicle_inquiry",
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

    const payload: VehicleInquiryNotificationPayload = await req.json();
    const { conversationId, senderId, messageContent, messageType } = payload;

    if (!conversationId || !senderId) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 },
      );
    }

    console.log("Processing vehicle inquiry notification for conversation:", conversationId, "sender:", senderId);

    // ---------- 1. Fetch the listing summary for the notification title ----------
    // `*` rather than named columns: listing_title only exists once migration
    // 081 is applied, and naming it would fail every notification — cars
    // included — on a database that does not have it yet.
    const { data: conversation, error: convError } = await supabase
      .from("vehicle_inquiry_conversations_view")
      .select("*")
      .eq("id", conversationId)
      .single();

    if (convError || !conversation) {
      console.error("Conversation not found:", convError);
      return new Response(
        JSON.stringify({ success: false, error: "Conversation not found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 },
      );
    }

    // ---------- 2. Recipients ----------
    // "The other participant" no longer identifies one person: a dealer
    // conversation has no seller_id and is answered by every current admin of
    // the owning organization. The RPC returns whoever that is, minus the
    // sender, so a replying admin does not notify themselves.
    const { data: recipientRows, error: recipientsError } = await supabase
      .rpc("get_vehicle_inquiry_recipients", {
        p_conversation_id: conversationId,
        p_sender_id: senderId,
      });

    if (recipientsError) throw recipientsError;

    const recipientUserIds = (recipientRows ?? [])
      .map((r: { user_id: string }) => r.user_id)
      .filter(Boolean);

    if (!recipientUserIds.length) {
      return new Response(
        JSON.stringify({ success: true, message: "No recipients for this message" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // ---------- 3. Build the notification title/body ----------
    const { data: senderProfile } = await supabase
      .from("user_profiles")
      .select("full_name, username")
      .eq("id", senderId)
      .single();

    const senderName = senderProfile?.full_name ?? senderProfile?.username ?? "New message";
    // listing_title covers Market items as well as vehicles; the year/make/
    // model fallback is for a database still on the pre-081 view.
    const listingTitle = conversation.listing_title ?? [
      conversation.vehicle_year,
      conversation.vehicle_make,
      conversation.vehicle_model,
    ].filter(Boolean).join(" ");

    const notificationTitle = listingTitle
      ? `${senderName} · ${listingTitle}`
      : senderName;

    let notificationBody: string;
    if (messageType === "image") {
      notificationBody = "📷 Photo";
    } else {
      const content = messageContent ?? "";
      notificationBody = content.length > 200
        ? content.substring(0, 197) + "..."
        : content;
    }

    // ---------- 4. Get FCM tokens for every recipient ----------
    // One dealership admin may have several devices, and several admins may
    // share one inbox, so this is a fan-out over all of their tokens.
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

    // ---------- 5. Send FCM notifications ----------
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    if (!projectId) throw new Error("FIREBASE_PROJECT_ID env var missing");

    const accessToken = await getAccessToken();

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

    console.log(`Vehicle inquiry notification result: ${success} sent, ${failure} failed`);

    return new Response(
      JSON.stringify({
        success: true,
        message: `Sent to ${success}/${tokens.length} device(s)`,
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
