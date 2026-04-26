import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * monitor-bom-stock v3 — state-watcher only (Option C-strict)
 *
 * MO creation removed entirely. sweetpea-order-mo v5+ owns all MO creation via
 * Shopify webhook. This function now does four things:
 *
 *   1. Recovery: if a SKU is on manual_override=DENY but singles have returned
 *      (in stock or expected), clear the override and Slack a recovery message.
 *   2. Sell-through detection: if free singles = 0, none expected, but packs are
 *      still on the shelf, set manual_override=DENY so Shopify stops accepting
 *      new orders while the remaining packs sell down. Slack the transition.
 *   3. Pool rotation alert: if a pool collection's constraining component is
 *      exhausted with none expected, Slack a rotation-needed message.
 *   4. Held-order alert pass: scan sweetpea_webhook_log for mo_held_low_singles
 *      rows with alerted_at IS NULL, Slack a consolidated list, mark alerted.
 *
 * Schedule: every 15 minutes via n8n workflow d9XkbnE3DBNuTgnx.
 *
 * Data sources:
 *   bom_monitoring_config — pack/component variant IDs, collection_type
 *   bom_collection_components — collection recipes
 *   Katana /v1/inventory — live stock (paginated, Grove Cross only)
 *   katana_stock_sync — manual_override read/write
 *   sweetpea_webhook_log — held-order alert pass
 *
 * Outputs:
 *   manual_override set/cleared in katana_stock_sync
 *   bom_monitoring_config.last_checked_at touched
 *   Slack messages returned for n8n to send
 */ const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const GROVE_CROSS = 162781;
const SLACK_CHANNEL = "C0AQHBN15SS";
const PAGE_SIZE = 250;
const API_DELAY_MS = 2000;
// ── Katana HTTP helpers with 429 retry ──────────────────────────────
async function katanaFetch(url, method) {
  for(let attempt = 1; attempt <= 3; attempt++){
    const opts = {
      method,
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`,
        "Content-Type": "application/json"
      }
    };
    const resp = await fetch(url, opts);
    if (resp.status === 429) {
      const wait = 5000 * Math.pow(2, attempt - 1);
      await new Promise((r)=>setTimeout(r, wait));
      continue;
    }
    if (resp.status === 204) return {
      status: 204,
      data: null
    };
    const text = await resp.text();
    if (!resp.ok) throw new Error(`${method} ${resp.status}: ${text.slice(0, 300)}`);
    return {
      status: resp.status,
      data: JSON.parse(text)
    };
  }
  throw new Error(`429 after 3 retries: ${method} ${url}`);
}
// ── Main ─────────────────────────────────────────────────────────
Deno.serve(async (req)=>{
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
  const actions = [];
  const messages = [];
  const stats = {
    configs_checked: 0,
    inventory_pages: 0,
    variants_matched: 0,
    recoveries: 0,
    sell_through_entered: 0,
    pool_rotation_alerts: 0,
    held_orders_alerted: 0
  };
  // ── 1. Read monitoring config ─────────────────────────────────────
  const { data: configs, error: cfgErr } = await supabase.from("bom_monitoring_config").select("*").eq("status", "active");
  if (cfgErr || !configs) {
    return jsonResp({
      status: "failed",
      reason: cfgErr?.message ?? "no config"
    });
  }
  stats.configs_checked = configs.length;
  const pack4s = configs.filter((c)=>!c.collection_type);
  const collections = configs.filter((c)=>c.collection_type);
  log.push(`Config: ${pack4s.length} Pack of 4, ${collections.length} collections`);
  // ── 2. Read collection components ────────────────────────────────
  const { data: collComps } = await supabase.from("bom_collection_components").select("*");
  const recipes = new Map();
  for (const cc of collComps ?? []){
    const list = recipes.get(cc.pack_variant_id) ?? [];
    list.push({
      vid: cc.component_variant_id,
      sku: cc.component_sku,
      qty: cc.quantity,
      pool: cc.is_pool_member
    });
    recipes.set(cc.pack_variant_id, list);
  }
  // ── 3. Collect variant IDs we need inventory for ───────────────
  const neededVids = new Set();
  for (const c of configs){
    neededVids.add(c.pack_variant_id);
    if (c.component_variant_id) neededVids.add(c.component_variant_id);
  }
  for (const cc of collComps ?? []){
    neededVids.add(cc.component_variant_id);
  }
  const inventory = new Map();
  let page = 1;
  try {
    while(true){
      const { data } = await katanaFetch(`https://api.katanamrp.com/v1/inventory?location_id=${GROVE_CROSS}&limit=${PAGE_SIZE}&page=${page}`, "GET");
      const items = data?.data ?? [];
      if (items.length === 0) break;
      for (const r of items){
        const vid = r.variant_id;
        if (neededVids.has(vid)) {
          inventory.set(vid, {
            inStock: parseFloat(String(r.quantity_in_stock)) || 0,
            expected: parseFloat(String(r.quantity_expected)) || 0,
            committed: parseFloat(String(r.quantity_committed)) || 0
          });
        }
      }
      stats.inventory_pages = page;
      if (items.length < PAGE_SIZE) break;
      page++;
      await new Promise((r)=>setTimeout(r, API_DELAY_MS));
    }
    stats.variants_matched = inventory.size;
    log.push(`Inventory: ${stats.inventory_pages} pages, ${inventory.size}/${neededVids.size} variants found`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`Inventory fetch page ${page}: ${msg}`);
  }
  if (inventory.size === 0) {
    return jsonResp({
      status: "no_data",
      reason: "No inventory found",
      stats,
      log,
      errors
    });
  }
  function freeSingles(vid) {
    const inv = inventory.get(vid);
    if (!inv) return 0;
    return Math.max(0, inv.inStock - inv.committed);
  }
  function expectedSingles(vid) {
    return inventory.get(vid)?.expected ?? 0;
  }
  // ── 5. Pack-of-4 state pass ─────────────────────────────────────
  for (const cfg of pack4s){
    const packInv = inventory.get(cfg.pack_variant_id);
    const packStock = packInv?.inStock ?? 0;
    const singleVid = cfg.component_variant_id;
    const singleFree = freeSingles(singleVid);
    const singleExpected = expectedSingles(singleVid);
    // Recovery: override is DENY but singles have reappeared
    if (singleFree > 0 || singleExpected > 0) {
      const { data: syncRow } = await supabase.from("katana_stock_sync").select("manual_override").eq("sku", cfg.pack_sku).maybeSingle();
      if (syncRow?.manual_override === "DENY") {
        await supabase.from("katana_stock_sync").update({
          manual_override: null
        }).eq("sku", cfg.pack_sku);
        stats.recoveries++;
        actions.push({
          type: "recovery",
          sku: cfg.pack_sku
        });
        messages.push({
          channel: SLACK_CHANNEL,
          text: `✅ *${cfg.pack_product_name}* recovered — singles available, override cleared`
        });
        log.push(`Recovery: ${cfg.pack_sku} override cleared`);
      }
    }
    // Sell-through detection: stock-signature — no free singles, none expected,
    // but packs still on the shelf. Flip to DENY if not already set.
    if (singleFree === 0 && singleExpected === 0 && packStock > 0) {
      const { data: syncRow } = await supabase.from("katana_stock_sync").select("manual_override").eq("sku", cfg.pack_sku).maybeSingle();
      if (!syncRow?.manual_override) {
        await supabase.from("katana_stock_sync").update({
          manual_override: "DENY"
        }).eq("sku", cfg.pack_sku);
        stats.sell_through_entered++;
        actions.push({
          type: "sell_through",
          sku: cfg.pack_sku,
          packs_remaining: packStock
        });
        messages.push({
          channel: SLACK_CHANNEL,
          text: `⚠️ *${cfg.pack_product_name}* entering sell-through — ${packStock} packs on shelf, singles exhausted and none expected`
        });
        log.push(`Sell-through: ${cfg.pack_sku}, ${packStock} packs on shelf`);
      }
    }
    await touchConfig(supabase, cfg.id);
  }
  // ── 6. Collection state pass ────────────────────────────────────
  for (const cfg of collections){
    const packInv = inventory.get(cfg.pack_variant_id);
    const packStock = packInv?.inStock ?? 0;
    const comps = recipes.get(cfg.pack_variant_id) ?? [];
    if (comps.length === 0) {
      log.push(`Collection ${cfg.pack_sku}: no components, skipping`);
      await touchConfig(supabase, cfg.id);
      continue;
    }
    // Recovery: any required component has stock or expected stock
    const anyAvailable = comps.some((c)=>freeSingles(c.vid) > 0 || expectedSingles(c.vid) > 0);
    if (anyAvailable) {
      const { data: syncRow } = await supabase.from("katana_stock_sync").select("manual_override").eq("sku", cfg.pack_sku).maybeSingle();
      if (syncRow?.manual_override === "DENY") {
        await supabase.from("katana_stock_sync").update({
          manual_override: null
        }).eq("sku", cfg.pack_sku);
        stats.recoveries++;
        actions.push({
          type: "collection_recovery",
          sku: cfg.pack_sku
        });
        messages.push({
          channel: SLACK_CHANNEL,
          text: `✅ *${cfg.pack_product_name}* recovered — components available, override cleared`
        });
        log.push(`Collection recovery: ${cfg.pack_sku} override cleared`);
      }
    }
    // Sell-through / pool rotation detection: find the first component that is
    // exhausted with none expected. That component is the constrainer.
    const constrainer = comps.find((c)=>freeSingles(c.vid) === 0 && expectedSingles(c.vid) === 0);
    if (constrainer && packStock > 0) {
      if (cfg.collection_type === "pool") {
        // Pool: rotation alert, no DENY flip (Phase 4 will own pool DENY logic)
        messages.push({
          channel: SLACK_CHANNEL,
          text: `🔄 *${cfg.pack_product_name}* — \`${constrainer.sku}\` exhausted in BOM. Pool rotation needed in Katana UI.`
        });
        stats.pool_rotation_alerts++;
        log.push(`Pool rotation needed: ${cfg.pack_sku}, constrainer=${constrainer.sku}`);
      } else {
        // Fixed collection: flip to DENY if not already set
        const { data: syncRow } = await supabase.from("katana_stock_sync").select("manual_override").eq("sku", cfg.pack_sku).maybeSingle();
        if (!syncRow?.manual_override) {
          await supabase.from("katana_stock_sync").update({
            manual_override: "DENY"
          }).eq("sku", cfg.pack_sku);
          stats.sell_through_entered++;
          actions.push({
            type: "collection_sell_through",
            sku: cfg.pack_sku,
            packs_remaining: packStock,
            constrained_by: constrainer.sku
          });
          messages.push({
            channel: SLACK_CHANNEL,
            text: `⚠️ *${cfg.pack_product_name}* entering sell-through — ${packStock} collections on shelf, \`${constrainer.sku}\` exhausted and none expected`
          });
          log.push(`Collection sell-through: ${cfg.pack_sku}, ${packStock} on shelf, constrainer=${constrainer.sku}`);
        }
      }
    }
    await touchConfig(supabase, cfg.id);
  }
  // ── 7. Held-order alert pass (unchanged from v2) ─────────────────
  try {
    const { data: heldRows } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, processed_at").eq("action", "mo_held_low_singles").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(50);
    if (heldRows && heldRows.length > 0) {
      let text = `🚫 *Sweet pea orders held — low singles buffer* (${heldRows.length})\n`;
      text += `_These orders landed in Shopify but were not booked against an MO. The affected SKUs have been DENY'd to prevent further orders. Action may be needed._\n\n`;
      for (const r of heldRows){
        text += `• order #${r.shopify_order_number} — \`${r.sku}\` qty=${r.quantity}\n`;
        text += `  ${r.notes ?? "(no details)"}\n`;
      }
      messages.push({
        channel: SLACK_CHANNEL,
        text
      });
      const ids = heldRows.map((r)=>r.id);
      const nowIso = new Date().toISOString();
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: nowIso
      }).in("id", ids);
      if (updErr) {
        errors.push(`held-order alerted_at update failed: ${updErr.message}`);
      } else {
        stats.held_orders_alerted = heldRows.length;
        log.push(`Held orders alerted: ${heldRows.length}`);
      }
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`held-order alert pass: ${msg}`);
  }
  const status = errors.length === 0 ? "complete" : "complete_with_errors";
  log.push(`Done: ${stats.recoveries} recoveries, ${stats.sell_through_entered} sell-throughs, ` + `${stats.pool_rotation_alerts} pool alerts, ${stats.held_orders_alerted} held-order alerts`);
  return jsonResp({
    status,
    stats,
    actions,
    messages,
    log,
    errors
  });
});
// ── Helpers ─────────────────────────────────────────────────────
async function touchConfig(supabase, id) {
  await supabase.from("bom_monitoring_config").update({
    last_checked_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  }).eq("id", id);
}
function jsonResp(body) {
  return new Response(JSON.stringify(body), {
    headers: {
      "Content-Type": "application/json"
    }
  });
}
