import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * backfill-shopify-total-price v3
 *
 * Mode D (read-only status probe) — added in v3.
 *   GET  ?status=1
 *   POST {"action":"status"}
 *   Returns backfill_state row + live currentBulkOperation from Shopify.
 *   No mutation: no bulk op creation, no JSONL download, no RPC call.
 *
 * Mode A — no state row present, default invocation:
 *   Starts a new Shopify Bulk Operation (created_at >= 2026-01-01).
 *
 * Mode B — state row present, bulk op still running:
 *   Polls currentBulkOperation and returns status.
 *
 * Mode C — state row present, bulk op COMPLETED:
 *   Downloads JSONL, batch-updates shopify_orders, clears state.
 */ const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const STATE_ID = "shopify-total-price-backfill";
async function getShopifyToken() {
  const secret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!secret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: secret
    }).toString()
  });
  if (!resp.ok) throw new Error(`Shopify token failed (${resp.status}): ${await resp.text()}`);
  return (await resp.json()).access_token;
}
async function shopifyGql(token, query) {
  const resp = await fetch(GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query
    })
  });
  if (!resp.ok) throw new Error(`Shopify GQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
function extractOrderId(gid) {
  const m = gid.match(/\/Order\/(\d+)$/);
  return m ? m[1] : null;
}
Deno.serve(async (req)=>{
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  // ── Mode D: read-only status probe ────────────────────────────────────────
  const url = new URL(req.url);
  const isGet = req.method === "GET";
  const isPost = req.method === "POST";
  let isStatusProbe = isGet && url.searchParams.has("status");
  if (isPost && !isStatusProbe) {
    // Peek at body to check for action flag without consuming it for Mode A/B/C
    const contentType = req.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const body = await req.json().catch(()=>({}));
      if (body.action === "status") isStatusProbe = true;
      // Re-attach consumed body isn't possible in standard Fetch — for status probe
      // we branch here; for normal flow the body is not needed beyond action check.
      if (!isStatusProbe) {
      // Body was consumed but not needed for Mode A/B/C — proceed normally.
      }
      if (isStatusProbe) {
        return await handleStatusProbe(supabase);
      }
    }
  }
  if (isStatusProbe) {
    return await handleStatusProbe(supabase);
  }
  // ── Modes A / B / C ───────────────────────────────────────────────────────
  try {
    const { data: stateRow } = await supabase.from("backfill_state").select("*").eq("id", STATE_ID).maybeSingle();
    const token = await getShopifyToken();
    // Mode A
    if (!stateRow) {
      const mutation = `mutation {
        bulkOperationRunQuery(query: """
          {
            orders(query: \"created_at:>=2026-01-01\") {
              edges { node { id currentTotalPriceSet { shopMoney { amount } } } }
            }
          }
        """) {
          bulkOperation { id status }
          userErrors { field message }
        }
      }`;
      const result = await shopifyGql(token, mutation);
      const gqlData = result.data;
      const bor = gqlData?.bulkOperationRunQuery;
      const errors = bor?.userErrors ?? [];
      if (errors.length > 0) return jsonResp({
        error: "bulk_op_start_failed",
        details: errors
      }, 500);
      const bulkOp = bor?.bulkOperation;
      const opId = bulkOp?.id;
      if (!opId) return jsonResp({
        error: "no_op_id_returned",
        raw: result
      }, 500);
      await supabase.from("backfill_state").upsert({
        id: STATE_ID,
        operation_id: opId,
        status: "RUNNING",
        notes: "v3: created_at>=2026-01-01",
        updated_at: new Date().toISOString()
      });
      return jsonResp({
        mode: "A_started",
        op_id: opId,
        message: "Bulk op started. Wait ~3 min, then invoke again to poll."
      });
    }
    // Mode B / C: poll
    const savedOpId = stateRow.operation_id;
    const pollResult = await shopifyGql(token, `{ currentBulkOperation { id status url errorCode objectCount } }`);
    const op = pollResult.data?.currentBulkOperation;
    if (!op) {
      await supabase.from("backfill_state").delete().eq("id", STATE_ID);
      return jsonResp({
        mode: "B_no_active_op",
        saved_op_id: savedOpId,
        note: "State cleared."
      });
    }
    const status = op.status;
    if (status === "RUNNING" || status === "CREATED" || status === "CANCELLING") {
      return jsonResp({
        mode: "B_polling",
        status,
        op_id: op.id,
        object_count: op.objectCount
      });
    }
    if (status === "FAILED" || status === "CANCELLED") {
      await supabase.from("backfill_state").delete().eq("id", STATE_ID);
      return jsonResp({
        mode: "C_failed",
        status,
        error_code: op.errorCode
      }, 500);
    }
    if (status !== "COMPLETED") {
      return jsonResp({
        mode: "unknown_status",
        status,
        op
      });
    }
    // Mode C: completed
    const downloadUrl = op.url;
    if (!downloadUrl) {
      await supabase.from("backfill_state").delete().eq("id", STATE_ID);
      return jsonResp({
        mode: "C_no_url",
        note: "No JSONL. State cleared."
      });
    }
    const dlResp = await fetch(downloadUrl);
    if (!dlResp.ok) return jsonResp({
      error: "download_failed",
      http_status: dlResp.status
    }, 500);
    const text = await dlResp.text();
    const lines = text.trim().split("\n").filter((l)=>l.trim());
    const updates = [];
    for (const line of lines){
      try {
        const obj = JSON.parse(line);
        const gid = obj.id;
        const priceSet = obj.currentTotalPriceSet;
        const amount = priceSet?.shopMoney?.amount;
        if (!gid || amount === undefined) continue;
        const numericId = extractOrderId(gid);
        if (!numericId) continue;
        updates.push({
          shopify_order_id: numericId,
          total_price: amount
        });
      } catch  {}
    }
    const CHUNK = 500;
    let totalUpdated = 0;
    for(let i = 0; i < updates.length; i += CHUNK){
      const chunk = updates.slice(i, i + CHUNK);
      const { data: rpcData, error: rpcErr } = await supabase.rpc("batch_update_shopify_total_price", {
        p_rows: chunk
      });
      if (rpcErr) return jsonResp({
        error: "batch_update_failed",
        detail: rpcErr.message,
        at_chunk: i / CHUNK
      }, 500);
      totalUpdated += rpcData?.updated ?? chunk.length;
    }
    await supabase.from("backfill_state").delete().eq("id", STATE_ID);
    return jsonResp({
      mode: "C_complete",
      lines_in_jsonl: lines.length,
      rows_updated: totalUpdated
    });
  } catch (err) {
    return jsonResp({
      error: err instanceof Error ? err.message : String(err)
    }, 500);
  }
});
// ── Mode D handler (pure read) ─────────────────────────────────────────────
async function handleStatusProbe(supabase) {
  try {
    const { data: stateRow } = await supabase.from("backfill_state").select("*").eq("id", STATE_ID).maybeSingle();
    if (!stateRow) {
      return jsonResp({
        mode: "D_status",
        backfill_state: null,
        shopify_bulk_op: null,
        summary: "No op in progress. Next default invocation will start Mode A."
      });
    }
    // Fetch live Shopify status (read-only poll, no mutation)
    let shopifyOp = null;
    try {
      const token = await getShopifyToken();
      const pollResult = await shopifyGql(token, `{ currentBulkOperation { id status url errorCode objectCount } }`);
      shopifyOp = pollResult.data?.currentBulkOperation ?? null;
    } catch (e) {
      shopifyOp = {
        error: e instanceof Error ? e.message : String(e)
      };
    }
    return jsonResp({
      mode: "D_status",
      backfill_state: stateRow,
      shopify_bulk_op: shopifyOp,
      summary: shopifyOp?.status === "COMPLETED" ? "Op complete. Next default invocation will download JSONL and update rows (Mode C)." : `Op ${shopifyOp?.status ?? "unknown"}. No action taken by this probe.`
    });
  } catch (err) {
    return jsonResp({
      error: err instanceof Error ? err.message : String(err)
    }, 500);
  }
}
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json"
    }
  });
}
