import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
// ---------- 🔑 Firebase OAuth2 Helper ----------
async function getAccessToken() {
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  if (!privateKey || !clientEmail) throw new Error("Firebase credentials missing");
  const jwtHeader = {
    alg: "RS256",
    typ: "JWT"
  };
  const jwtClaimSet = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    exp: Math.floor(Date.now() / 1000) + 3600,
    iat: Math.floor(Date.now() / 1000)
  };
  const encoder = new TextEncoder();
  const base64UrlEncode = (input)=>btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const encodePart = (obj)=>base64UrlEncode(JSON.stringify(obj));
  const unsignedJwt = `${encodePart(jwtHeader)}.${encodePart(jwtClaimSet)}`;
  const keyData = Uint8Array.from(atob(privateKey.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "").replace(/\n/g, "")), (c)=>c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey("pkcs8", keyData, {
    name: "RSASSA-PKCS1-v1_5",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, encoder.encode(unsignedJwt));
  const signedJwt = `${unsignedJwt}.${base64UrlEncode(String.fromCharCode(...new Uint8Array(signature)))}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${signedJwt}`
  });
  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) throw new Error("Failed to obtain access token");
  return tokenData.access_token;
}
// ---------- 🔥 Main Function ----------
serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "", {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });
    const payload = await req.json();
    const { postId, channelId, title, body, authorName } = payload;
    console.log("Processing notification for post:", postId, "in channel:", channelId);
    // Get followers who have FCM tokens
    // First get all followers
    const { data: followsData, error: followersError } = await supabase.from("user_follows").select("user_id").eq("organization_id", channelId);
    if (followersError) throw followersError;
    if (!followsData?.length) {
      return new Response(JSON.stringify({
        success: true,
        message: "No followers"
      }), {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json"
        }
      });
    }
    const userIds = followsData.map((f)=>f.user_id);
    // Get FCM tokens for these users
    const { data: tokens, error: tokensError } = await supabase.from("user_fcm_tokens").select("user_id, fcm_token").in("user_id", userIds);
    if (tokensError) throw tokensError;
    if (!tokens?.length) {
      return new Response(JSON.stringify({
        success: true,
        message: "No FCM tokens found"
      }), {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json"
        }
      });
    }
    // Get notification preferences
    const { data: prefs } = await supabase.from("notification_preferences").select("user_id, notifications_enabled").eq("channel_id", channelId).in("user_id", userIds);
    const prefMap = new Map();
    prefs?.forEach((p)=>prefMap.set(p.user_id, p.notifications_enabled));
    // Filter tokens based on preferences
    const fcmTokens = [];
    const skippedUsers = [];
    tokens.forEach((t)=>{
      const enabled = prefMap.get(t.user_id) ?? true // Default to enabled
      ;
      if (enabled) {
        fcmTokens.push(t.fcm_token);
      } else {
        skippedUsers.push(t.user_id);
      }
    });
    console.log(`Filtered: ${fcmTokens.length} enabled, ${skippedUsers.length} muted`);
    if (!fcmTokens.length) {
      return new Response(JSON.stringify({
        success: true,
        message: "No tokens to send"
      }), {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json"
        }
      });
    }
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    const accessToken = await getAccessToken();
    // Send one message per token (simple reliable approach)
    let success = 0, failure = 0;
    for (const token of fcmTokens){
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title,
              body
            },
            data: {
              post_id: postId,
              channel_id: channelId,
              author_name: authorName,
              click_action: "FLUTTER_NOTIFICATION_CLICK"
            },
            android: {
              notification: {
                icon: "ic_notification",
                color: "#2196F3",
                channel_id: "post_notifications"
              }
            },
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  badge: 1
                }
              }
            }
          }
        })
      });
      if (res.ok) success++;
      else failure++;
    }
    // Log notification summary
    await supabase.from("notification_logs").insert({
      post_id: postId,
      channel_id: channelId,
      recipient_count: fcmTokens.length,
      success_count: success,
      failure_count: failure,
      sent_at: new Date().toISOString()
    });
    return new Response(JSON.stringify({
      success: true,
      message: `Sent to ${success}/${fcmTokens.length}`
    }), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json"
      },
      status: 200
    });
  } catch (err) {
    console.error("Error:", err);
    return new Response(JSON.stringify({
      success: false,
      error: err.message
    }), {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json"
      },
      status: 500
    });
  }
});
