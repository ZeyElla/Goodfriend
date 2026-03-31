// Supabase Edge Function: send-reminder
// Deploy with: supabase functions deploy send-reminder
// Triggered by a cron job or external scheduler every minute.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID")!;
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID")!;
// APNS_PRIVATE_KEY should be the raw p8 key content (no header/footer, newlines replaced with \n)
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY")!;

Deno.serve(async (_req) => {
  const now = new Date().toISOString();

  // Fetch due, un-fired reminders
  const { data: reminders, error } = await supabase
    .from("reminders")
    .select(`
      id, title, description, draft_message, due_date,
      contact:contacts(name),
      user_id
    `)
    .lte("due_date", now)
    .eq("is_fired", false);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const results: string[] = [];

  for (const reminder of reminders ?? []) {
    // Get device tokens for this user
    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", reminder.user_id);

    for (const { token } of tokens ?? []) {
      await sendApnsNotification(token, reminder);
    }

    // Mark as fired
    await supabase
      .from("reminders")
      .update({ is_fired: true })
      .eq("id", reminder.id);

    results.push(reminder.id);
  }

  return new Response(JSON.stringify({ fired: results }), { status: 200 });
});

async function sendApnsNotification(deviceToken: string, reminder: any) {
  const jwt = await buildApnsJwt();
  const contactName = reminder.contact?.name ?? "someone";
  const payload = {
    aps: {
      alert: {
        title: `Reminder: ${contactName}`,
        body: reminder.title,
      },
      sound: "default",
      badge: 1,
    },
    reminderId: reminder.id,
  };

  const url = `https://api.push.apple.com/3/device/${deviceToken}`;
  await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": APNS_BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
}

async function buildApnsJwt(): Promise<string> {
  const header = btoa(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const now = Math.floor(Date.now() / 1000);
  const claims = btoa(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const data = `${header}.${claims}`;
  const keyData = pemToArrayBuffer(APNS_PRIVATE_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(data)
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  return `${data}.${sig}`;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const binary = atob(b64);
  const buf = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) buf[i] = binary.charCodeAt(i);
  return buf.buffer;
}
