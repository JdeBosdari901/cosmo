import "jsr:@supabase/functions-js/edge-runtime.d.ts";
/**
 * sweetpea-backfill v3 — v2 + skip parameter for pagination.
 * Uses verify_jwt=true so Supabase validates JWT.
 * Service role key works natively; anon key is rejected by checking role claim.
 */ const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
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
async function shopifyGraphQL(token, query, variables) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query,
      variables
    })
  });
  if (!resp.ok) throw new Error(`Shopify GraphQL ${resp.status}: ${await resp.text()}`);
  return resp.json();
}
function isSweetpeaSku(sku) {
  if (!sku) return false;
  return sku.startsWith("LATHODO") || sku.startsWith("LATHCOTT-");
}
function checkRole(authHeader) {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const parts = token.split(".");
    if (parts.length !== 3) return {
      ok: false,
      role: "malformed"
    };
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    const role = payload.role ?? "unknown";
    return {
      ok: role === "service_role",
      role
    };
  } catch  {
    return {
      ok: false,
      role: "decode_error"
    };
  }
}
Deno.serve(async (req)=>{
  const authHeader = req.headers.get("authorization") ?? "";
  const check = checkRole(authHeader);
  if (!check.ok) {
    return new Response(JSON.stringify({
      error: "needs_service_role",
      got_role: check.role
    }), {
      status: 403,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const url = new URL(req.url);
  const dryRun = url.searchParams.get("dry_run") !== "0";
  const limit = parseInt(url.searchParams.get("limit") ?? "1000", 10);
  const skip = parseInt(url.searchParams.get("skip") ?? "0", 10);
  const paceMs = parseInt(url.searchParams.get("pace_ms") ?? "5000", 10);
  try {
    const token = await getShopifyToken();
    const orders = [];
    let cursor = null;
    let pages = 0;
    const maxPages = 50;
    while(pages < maxPages){
      const query = `
        query($cursor: String) {
          orders(
            first: 100
            after: $cursor
            sortKey: CREATED_AT
            reverse: false
            query: "fulfillment_status:unfulfilled AND status:open"
          ) {
            pageInfo { hasNextPage endCursor }
            nodes {
              id
              legacyResourceId
              name
              createdAt
              lineItems(first: 100) {
                nodes {
                  sku
                  quantity
                  variant { legacyResourceId }
                }
              }
            }
          }
        }
      `;
      const data = await shopifyGraphQL(token, query, {
        cursor
      });
      if (data.errors) {
        return new Response(JSON.stringify({
          error: "shopify_graphql",
          details: data.errors
        }), {
          status: 500
        });
      }
      const page = data.data.orders;
      for (const node of page.nodes){
        const lines = node.lineItems.nodes.filter((li)=>isSweetpeaSku(li.sku)).map((li)=>({
            sku: li.sku,
            quantity: li.quantity,
            variantId: li.variant ? parseInt(li.variant.legacyResourceId, 10) : null
          }));
        if (lines.length > 0) {
          orders.push({
            id: parseInt(node.legacyResourceId, 10),
            name: node.name,
            createdAt: node.createdAt,
            lineItems: lines
          });
        }
      }
      pages++;
      if (!page.pageInfo.hasNextPage) break;
      cursor = page.pageInfo.endCursor;
    }
    orders.sort((a, b)=>a.createdAt.localeCompare(b.createdAt));
    const processed = orders.slice(skip, skip + limit);
    if (dryRun) {
      const skuTotals = new Map();
      for (const o of processed){
        for (const li of o.lineItems){
          skuTotals.set(li.sku, (skuTotals.get(li.sku) ?? 0) + li.quantity);
        }
      }
      return new Response(JSON.stringify({
        dry_run: true,
        orders_scanned: orders.length,
        skip,
        limit,
        orders_to_process: processed.length,
        earliest: processed[0]?.createdAt ?? null,
        latest: processed[processed.length - 1]?.createdAt ?? null,
        sku_totals: Object.fromEntries([
          ...skuTotals.entries()
        ].sort((a, b)=>b[1] - a[1]))
      }, null, 2), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const RECEIVER_URL = `${SUPABASE_URL}/functions/v1/sweetpea-reservation-receiver?event=create`;
    const results = {
      orders_processed: 0,
      succeeded: 0,
      deduped: 0,
      errors: [],
      first_error_at: null
    };
    for (const order of processed){
      const payload = {
        id: order.id,
        order_number: order.name,
        name: order.name,
        created_at: order.createdAt,
        line_items: order.lineItems.map((li)=>({
            sku: li.sku,
            quantity: li.quantity,
            variant_id: li.variantId
          }))
      };
      try {
        const resp = await fetch(RECEIVER_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${SERVICE_KEY}`
          },
          body: JSON.stringify(payload)
        });
        const text = await resp.text();
        if (resp.status >= 200 && resp.status < 300) {
          results.succeeded++;
          if (text.includes("duplicate_deduped") || text.includes("duplicate")) results.deduped++;
        } else {
          results.errors.push({
            order: order.name,
            status: resp.status,
            body: text.slice(0, 300)
          });
          if (!results.first_error_at) results.first_error_at = order.name;
        }
      } catch (e) {
        results.errors.push({
          order: order.name,
          status: 0,
          body: e instanceof Error ? e.message : String(e)
        });
        if (!results.first_error_at) results.first_error_at = order.name;
      }
      results.orders_processed++;
      if (results.orders_processed < processed.length) {
        await new Promise((r)=>setTimeout(r, paceMs));
      }
    }
    return new Response(JSON.stringify({
      dry_run: false,
      orders_scanned: orders.length,
      skip,
      limit,
      ...results
    }, null, 2), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : String(err)
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
