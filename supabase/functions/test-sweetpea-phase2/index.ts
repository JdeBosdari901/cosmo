import "jsr:@supabase/functions-js/edge-runtime.d.ts";
/**
 * test-sweetpea-phase2 v5 — Phase 3 test harness.
 *
 * Forwards a supplied Shopify-shaped webhook payload to sweetpea-order-mo using
 * the service-role bearer (admin-test bypass), so tests can be driven from SQL/MCP
 * without needing a valid HMAC signature.
 *
 * Usage:
 *   POST /functions/v1/test-sweetpea-phase2
 *   body: { "event": "create" | "cancel", "payload": { ...shopify webhook payload... } }
 */ const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  if (!SUPABASE_URL || !SERVICE_KEY) {
    return new Response(JSON.stringify({
      error: "SUPABASE_URL or SERVICE_KEY not configured"
    }), {
      status: 500
    });
  }
  let outer;
  try {
    outer = await req.json();
  } catch  {
    return new Response(JSON.stringify({
      error: "invalid_json"
    }), {
      status: 400
    });
  }
  const event = (outer.event ?? "create").toLowerCase();
  if (event !== "create" && event !== "cancel") {
    return new Response(JSON.stringify({
      error: `bad event '${event}'`
    }), {
      status: 400
    });
  }
  const payload = outer.payload ?? {};
  const url = `${SUPABASE_URL}/functions/v1/sweetpea-order-mo?event=${event}`;
  const fwd = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${SERVICE_KEY}`
    },
    body: JSON.stringify(payload)
  });
  const text = await fwd.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch  {
    parsed = text;
  }
  return new Response(JSON.stringify({
    forwarded_to: url,
    upstream_status: fwd.status,
    upstream_body: parsed
  }), {
    status: 200,
    headers: {
      "Content-Type": "application/json"
    }
  });
});
