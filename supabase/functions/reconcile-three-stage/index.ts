import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const GROVE_CROSS = 162781;
const PAGE_SIZE = 250;
const PAGE_DELAY_MS = 2500;
/**
 * Katana GET with 429 retry + exponential backoff.
 */ async function katanaGet(url) {
  for(let attempt = 1; attempt <= 3; attempt++){
    const resp = await fetch(url, {
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`
      }
    });
    if (resp.status === 429) {
      const wait = 5000 * Math.pow(2, attempt - 1);
      console.log(`429 attempt ${attempt}/3 — waiting ${wait}ms`);
      await new Promise((r)=>setTimeout(r, wait));
      continue;
    }
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${await resp.text()}`);
    return await resp.json();
  }
  throw new Error(`429 after 3 retries: ${url}`);
}
/**
 * reconcile-three-stage v3
 *
 * Uses extend=variant and limit=250 to fetch all Katana inventory
 * with SKUs in a single pagination pass (~35 pages, ~90 seconds).
 *
 * Stage 1: Paginate Katana inventory (with variant.sku), upsert via bulk_upsert_katana_stock
 * Stage 2: Call get_policy_mismatches()
 * Stage 3: Fix mismatches via fix-batch-deny
 */ Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const log = [];
  const errors = [];
  const stats = {
    api_pages: 0,
    api_rows_total: 0,
    grove_cross_rows: 0,
    rows_with_sku: 0,
    rows_upserted: 0,
    placeholder_skus_resolved: 0,
    mismatches_detected: 0,
    policies_changed: 0,
    fix_errors: 0
  };
  // ── Stage 1: Paginate Katana inventory with extend=variant ──────
  const rows = [];
  let page = 1;
  try {
    while(true){
      const data = await katanaGet(`https://api.katanamrp.com/v1/inventory?limit=${PAGE_SIZE}&extend=variant&page=${page}`);
      const items = data.data ?? [];
      stats.api_rows_total += items.length;
      for (const r of items){
        if (r.location_id !== GROVE_CROSS) continue;
        stats.grove_cross_rows++;
        const variant = r.variant;
        const sku = variant?.sku;
        if (!sku || typeof sku !== "string") continue;
        stats.rows_with_sku++;
        rows.push({
          vid: r.variant_id,
          sku,
          ins: parseFloat(String(r.quantity_in_stock)) || 0,
          exp: parseFloat(String(r.quantity_expected)) || 0,
          com: parseFloat(String(r.quantity_committed)) || 0,
          saf: parseFloat(String(r.safety_stock_level)) || 0
        });
      }
      stats.api_pages = page;
      if (items.length < PAGE_SIZE) break;
      page++;
      await new Promise((r)=>setTimeout(r, PAGE_DELAY_MS));
    }
    log.push(`Stage 1a: ${stats.api_pages} pages, ${stats.api_rows_total} API rows, ` + `${stats.grove_cross_rows} Grove Cross, ${stats.rows_with_sku} with SKU, ` + `${rows.length} rows to upsert`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`Stage 1a (inventory): ${msg}`);
    log.push(`Stage 1a FAILED at page ${page}: ${msg}`);
  }
  if (rows.length === 0) {
    return new Response(JSON.stringify({
      status: "failed",
      reason: "No inventory data",
      stats,
      log,
      errors
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  // ── Stage 1b: Upsert via bulk_upsert_katana_stock ──────────────
  const chunkSize = 500;
  try {
    for(let i = 0; i < rows.length; i += chunkSize){
      const chunk = rows.slice(i, i + chunkSize);
      const { data, error } = await supabase.rpc("bulk_upsert_katana_stock", {
        rows: chunk
      });
      if (error) throw new Error(`bulk_upsert RPC: ${error.message}`);
      if (Array.isArray(data) && data[0]) {
        stats.rows_upserted += data[0].upserted || 0;
        stats.placeholder_skus_resolved += data[0].updated_skus || 0;
      }
    }
    log.push(`Stage 1b: ${stats.rows_upserted} upserted, ${stats.placeholder_skus_resolved} placeholders resolved`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`Stage 1b (upsert): ${msg}`);
    log.push(`Stage 1b FAILED: ${msg}`);
  }
  // ── Stage 2: Detect mismatches ─────────────────────────────────
  let mismatches = [];
  try {
    const { data, error } = await supabase.rpc("get_policy_mismatches");
    if (error) throw new Error(`get_policy_mismatches RPC: ${error.message}`);
    mismatches = Array.isArray(data) ? data : [];
    stats.mismatches_detected = mismatches.length;
    log.push(`Stage 2: ${mismatches.length} mismatches detected`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`Stage 2 (mismatches): ${msg}`);
    log.push(`Stage 2 FAILED: ${msg}`);
  }
  // ── Stage 3: Fix mismatches via fix-batch-deny ─────────────────
  if (mismatches.length > 0) {
    const toDeny = mismatches.filter((m)=>m.target_policy === "DENY").map((m)=>m.sku);
    const toContinue = mismatches.filter((m)=>m.target_policy === "CONTINUE").map((m)=>m.sku);
    const fixBatchUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/fix-batch-deny`;
    for (const [skus, policy] of [
      [
        toDeny,
        "DENY"
      ],
      [
        toContinue,
        "CONTINUE"
      ]
    ]){
      if (skus.length === 0) continue;
      for(let i = 0; i < skus.length; i += 50){
        const batch = skus.slice(i, i + 50);
        try {
          const fixResp = await fetch(fixBatchUrl, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`
            },
            body: JSON.stringify({
              skus: batch,
              target_policy: policy,
              reason: "reconcile-three-stage v3: mismatch detected"
            })
          });
          if (!fixResp.ok) throw new Error(`fix-batch-deny HTTP ${fixResp.status}: ${await fixResp.text()}`);
          const fixResult = await fixResp.json();
          stats.policies_changed += fixResult.changed || 0;
          stats.fix_errors += fixResult.errors || 0;
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          errors.push(`Stage 3 (batch ${batch[0]}): ${msg}`);
          stats.fix_errors += batch.length;
        }
        if (batch.length >= 50) await new Promise((r)=>setTimeout(r, 2000));
      }
    }
    log.push(`Stage 3: ${stats.policies_changed} changed, ${stats.fix_errors} errors`);
  }
  const status = errors.length === 0 ? "complete" : "complete_with_errors";
  return new Response(JSON.stringify({
    status,
    stats,
    log,
    errors
  }), {
    headers: {
      "Content-Type": "application/json"
    }
  });
});
