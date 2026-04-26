import "jsr:@supabase/functions-js/edge-runtime.d.ts";
/**
 * register-sweetpea-webhooks v3
 * v2 note updated to reflect reality: Shopify custom apps sign webhooks with
 * the app's client_secret (SHOPIFY_CLIENT_KEY), no separate webhook secret
 * needs to be configured.
 */ const SHOP = "ashridge-trees";
const API_VERSION = "2024-10";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_TOKEN_URL = `https://${SHOP}.myshopify.com/admin/oauth/access_token`;
const TARGET_BASE = `${Deno.env.get("SUPABASE_URL")}/functions/v1/sweetpea-order-mo`;
const TOPICS = [
  {
    topic: "orders/create",
    query: "create"
  },
  {
    topic: "orders/cancelled",
    query: "cancel"
  }
];
async function getShopifyToken() {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: clientSecret
    }).toString()
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  const data = await resp.json();
  return data.access_token;
}
async function shopifyApi(token, path, init = {}) {
  const url = `https://${SHOP}.myshopify.com/admin/api/${API_VERSION}${path}`;
  const resp = await fetch(url, {
    ...init,
    headers: {
      ...init.headers ?? {},
      "X-Shopify-Access-Token": token,
      "Content-Type": "application/json"
    }
  });
  const text = await resp.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch  {
    body = text;
  }
  return {
    status: resp.status,
    body
  };
}
Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  let token;
  try {
    token = await getShopifyToken();
  } catch (e) {
    return new Response(JSON.stringify({
      error: "token_exchange_failed",
      detail: e.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const results = {};
  for (const { topic, query } of TOPICS){
    const address = `${TARGET_BASE}?event=${query}`;
    const key = topic.replace("/", "_");
    const list = await shopifyApi(token, `/webhooks.json?topic=${encodeURIComponent(topic)}`);
    if (list.status !== 200) {
      results[key] = {
        error: "list_failed",
        status: list.status,
        body: list.body
      };
      continue;
    }
    const existing = list.body.webhooks ?? [];
    for (const wh of existing){
      const delResp = await shopifyApi(token, `/webhooks/${wh.id}.json`, {
        method: "DELETE"
      });
      if (delResp.status !== 200 && delResp.status !== 204) {
        results[`${key}_delete_warning`] = {
          id: wh.id,
          status: delResp.status,
          body: delResp.body
        };
      }
    }
    const createResp = await shopifyApi(token, `/webhooks.json`, {
      method: "POST",
      body: JSON.stringify({
        webhook: {
          topic,
          address,
          format: "json"
        }
      })
    });
    if (createResp.status !== 201) {
      results[key] = {
        error: "create_failed",
        status: createResp.status,
        body: createResp.body,
        address
      };
      continue;
    }
    results[key] = createResp.body.webhook;
  }
  return new Response(JSON.stringify({
    results,
    note: "Shopify signs webhook payloads using the app's client_secret (SHOPIFY_CLIENT_KEY), which is already configured in Supabase Edge Functions secrets. No separate webhook secret needed. The sweetpea-order-mo handler reads SHOPIFY_CLIENT_KEY and validates HMAC-SHA256 automatically."
  }, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json"
    }
  });
});
