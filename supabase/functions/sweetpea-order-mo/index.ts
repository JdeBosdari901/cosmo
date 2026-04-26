import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * sweetpea-order-mo v8 — Phase 2 (Pack-of-4) + Phase 3 (fixed collections)
 *                       + Phase 4 (Cottage Garden Mix pool)
 *                       + Phase 5 (cancellations)
 *
 * Phase 5 cancellation behaviour (new in v8):
 *   - No pending MO → cancel_no_mo (normal: held create, closed MO, etc.)
 *   - Pending MO, cancelled qty > current_qty → cancel_error (data drift)
 *   - Pending MO, status != NOT_STARTED → cancel_mo_locked (manual review)
 *   - Pending MO, qty reduces to 0 → DELETE MO, DELETE pending row, mo_deleted / cg_mo_deleted
 *   - Pending MO, qty reduces but stays > 0 → PATCH MO, UPDATE pending.current_qty, mo_decremented / cg_mo_decremented
 *   - After a successful decrement/delete, the handler auto-restores CONTINUE
 *     on any DENY'd SKU (golden rule: keep product on the shelf). If the
 *     restore fails, notes are tagged DENY_RESTORE_FAILED so the watchdog
 *     alerts separately (pass H).
 *
 * DRY_RUN: default TRUE. Live Katana/Shopify writes only when
 * SWEETPEA_MO_DRY_RUN="false" (case-insensitive).
 */ const SHOPIFY_SECRET = Deno.env.get("SHOPIFY_CLIENT_KEY") ?? "";
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const KATANA_BASE = "https://api.katanamrp.com/v1";
const GROVE_CROSS = 162781;
const SINGLES_BUFFER = 5;
const SINGLES_FLOOR_CG = 50;
const MAX_PROBE_N = 20;
const COTTAGE_MIX_SKU = "LATHCOTT-8Plgs";
const DRY_RUN = (Deno.env.get("SWEETPEA_MO_DRY_RUN") ?? "").toLowerCase() !== "false";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ALL_SEGMENTS = [
  "red_scarlet",
  "salmon_coral",
  "cream_ivory",
  "pink",
  "maroon_claret_near_black",
  "purple_violet",
  "light_blue",
  "dark_blue"
];
function isSweetpeaSku(sku) {
  if (!sku) return false;
  return sku.startsWith("LATHODO") || sku.startsWith("LATHCOTT-");
}
function isPackOfFour(sku) {
  if (!sku.startsWith("LATHODO")) return false;
  return sku.includes("-Pack of 4") || sku.endsWith("-Pk4");
}
function isFixedCollection(sku) {
  return sku === "LATHCOTT-Pastel 8pk" || sku === "LATHCOTT-Royal 8pk" || sku === "LATHCOTT-Twilight 8pk";
}
function isCottagePool(sku) {
  return sku === COTTAGE_MIX_SKU;
}
function isCollection(sku) {
  return sku.startsWith("LATHCOTT-");
}
function todayYYMMDD() {
  const d = new Date();
  const yy = String(d.getUTCFullYear()).slice(2);
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yy}${mm}${dd}`;
}
function packShortName(sku) {
  if (sku === COTTAGE_MIX_SKU) return "Cottage";
  if (sku.startsWith("LATHCOTT-")) {
    return sku.slice("LATHCOTT-".length).split(/\s+/)[0].slice(0, 10);
  }
  return sku.replace(/^LATHODO[R]?/, "").replace(/-.*$/, "").slice(0, 10);
}
async function verifyHmac(body, providedB64) {
  if (!SHOPIFY_SECRET || !providedB64) return false;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode(SHOPIFY_SECRET), {
    name: "HMAC",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(body));
  const computed = btoa(String.fromCharCode(...new Uint8Array(sig)));
  if (computed.length !== providedB64.length) return false;
  let diff = 0;
  for(let i = 0; i < computed.length; i++){
    diff |= computed.charCodeAt(i) ^ providedB64.charCodeAt(i);
  }
  return diff === 0;
}
async function katanaFetch(path, method, body) {
  for(let attempt = 1; attempt <= 3; attempt++){
    const opts = {
      method,
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`,
        "Content-Type": "application/json"
      }
    };
    if (body) opts.body = JSON.stringify(body);
    const resp = await fetch(`${KATANA_BASE}${path}`, opts);
    if (resp.status === 429) {
      await new Promise((r)=>setTimeout(r, 5000 * Math.pow(2, attempt - 1)));
      continue;
    }
    if (resp.status === 204) return {
      status: 204,
      data: null
    };
    const text = await resp.text();
    try {
      return {
        status: resp.status,
        data: JSON.parse(text)
      };
    } catch  {
      return {
        status: resp.status,
        data: null,
        rawText: text
      };
    }
  }
  throw new Error(`Katana 429 after 3 retries: ${method} ${path}`);
}
async function findNextN(short, date) {
  for(let n = 1; n <= MAX_PROBE_N; n++){
    const orderNo = `MO-${short}-${date}-${n}`;
    const resp = await katanaFetch(`/manufacturing_orders?order_no=${encodeURIComponent(orderNo)}`, "GET");
    if (resp.status !== 200) return null;
    const rows = resp.data?.data ?? [];
    if (rows.length === 0) return n;
  }
  return null;
}
async function getInventoryForVariant(variantId) {
  const resp = await katanaFetch(`/inventory?variant_id=${variantId}&location_id=${GROVE_CROSS}`, "GET");
  if (resp.status !== 200 || !resp.data) return null;
  const rows = resp.data.data ?? [];
  const row = rows.find((r)=>Number(r.location_id) === GROVE_CROSS && Number(r.variant_id) === variantId);
  if (!row) return null;
  const inStock = parseFloat(String(row.quantity_in_stock)) || 0;
  const committed = parseFloat(String(row.quantity_committed)) || 0;
  return {
    inStock,
    committed,
    freeSingles: inStock - committed
  };
}
async function getMoStatus(moId) {
  const resp = await katanaFetch(`/manufacturing_orders/${moId}`, "GET");
  if (resp.status === 404) return null;
  if (resp.status !== 200 || !resp.data) return null;
  return resp.data.status ?? null;
}
async function getMoRecipeRows(moId) {
  const resp = await katanaFetch(`/manufacturing_order_recipe_rows?manufacturing_order_id=${moId}&limit=250`, "GET");
  if (resp.status !== 200 || !resp.data) return null;
  const rows = resp.data.data ?? [];
  return rows.map((r)=>({
      id: Number(r.id),
      manufacturing_order_id: Number(r.manufacturing_order_id),
      variant_id: Number(r.variant_id),
      planned_quantity_per_unit: parseFloat(String(r.planned_quantity_per_unit))
    }));
}
async function createMoRecipeRow(moId, variantId, qtyPerUnit) {
  const resp = await katanaFetch("/manufacturing_order_recipe_rows", "POST", {
    manufacturing_order_id: moId,
    variant_id: variantId,
    planned_quantity_per_unit: qtyPerUnit
  });
  if (resp.status !== 200 && resp.status !== 201) return null;
  const r = resp.data;
  if (!r || !r.id) return null;
  return {
    id: Number(r.id),
    manufacturing_order_id: Number(r.manufacturing_order_id),
    variant_id: Number(r.variant_id),
    planned_quantity_per_unit: parseFloat(String(r.planned_quantity_per_unit))
  };
}
async function updateMoRecipeRow(rowId, qtyPerUnit) {
  const resp = await katanaFetch(`/manufacturing_order_recipe_rows/${rowId}`, "PATCH", {
    planned_quantity_per_unit: qtyPerUnit
  });
  return resp.status === 200;
}
async function deleteMoRecipeRow(rowId) {
  const resp = await katanaFetch(`/manufacturing_order_recipe_rows/${rowId}`, "DELETE");
  return resp.status === 200 || resp.status === 204;
}
async function pushDenyToShopify(sku, reason) {
  try {
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/fix-batch-deny`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SERVICE_KEY}`
      },
      body: JSON.stringify({
        skus: [
          sku
        ],
        target_policy: "DENY",
        reason
      })
    });
    const text = await resp.text();
    if (!resp.ok) return {
      ok: false,
      detail: `${resp.status} ${text.slice(0, 200)}`
    };
    return {
      ok: true,
      detail: text.slice(0, 200)
    };
  } catch (err) {
    return {
      ok: false,
      detail: err instanceof Error ? err.message : String(err)
    };
  }
}
async function pushContinueToShopify(sku, reason) {
  try {
    const resp = await fetch(`${SUPABASE_URL}/functions/v1/fix-batch-deny`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SERVICE_KEY}`
      },
      body: JSON.stringify({
        skus: [
          sku
        ],
        target_policy: "CONTINUE",
        reason
      })
    });
    const text = await resp.text();
    if (!resp.ok) return {
      ok: false,
      detail: `${resp.status} ${text.slice(0, 200)}`
    };
    return {
      ok: true,
      detail: text.slice(0, 200)
    };
  } catch (err) {
    return {
      ok: false,
      detail: err instanceof Error ? err.message : String(err)
    };
  }
}
async function insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, phaseNote, eventType = "create") {
  const { data, error } = await supabase.from("sweetpea_webhook_log").insert({
    shopify_order_id: orderId,
    shopify_order_number: orderNumber,
    event_type: eventType,
    sku,
    quantity,
    action: "processing",
    notes: phaseNote
  }).select("id").single();
  if (error) {
    if (error.code === "23505") return "duplicate";
    return "error";
  }
  return {
    id: data.id
  };
}
async function finaliseRow(supabase, rowId, action, notes, moId) {
  const patch = {
    action,
    notes
  };
  if (moId !== undefined && moId !== null) patch.mo_id = moId;
  await supabase.from("sweetpea_webhook_log").update(patch).eq("id", rowId);
}
Deno.serve(async (req)=>{
  if (req.method !== "POST") return jsonResp({
    error: "POST required"
  }, 405);
  const rawBody = await req.text();
  const providedHmac = req.headers.get("x-shopify-hmac-sha256") ?? "";
  const topic = req.headers.get("x-shopify-topic") ?? "";
  const url = new URL(req.url);
  const queryEvent = url.searchParams.get("event") ?? "";
  let eventType;
  if (topic === "orders/create") eventType = "create";
  else if (topic === "orders/cancelled") eventType = "cancel";
  else if (queryEvent === "create" || queryEvent === "cancel") eventType = queryEvent;
  else return jsonResp({
    error: `unknown event; topic='${topic}' event='${queryEvent}'`
  }, 400);
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const authHeader = req.headers.get("authorization") ?? "";
  const isAdminTest = authHeader.startsWith("Bearer ") && authHeader.slice(7) === SERVICE_KEY;
  if (!isAdminTest) {
    if (!SHOPIFY_SECRET) {
      await supabase.from("sweetpea_webhook_log").insert({
        shopify_order_id: 0,
        event_type: eventType,
        action: "hmac_rejected",
        notes: "SHOPIFY_CLIENT_KEY not configured"
      });
      return jsonResp({
        error: "secret_not_configured"
      }, 500);
    }
    const valid = await verifyHmac(rawBody, providedHmac);
    if (!valid) {
      await supabase.from("sweetpea_webhook_log").insert({
        shopify_order_id: 0,
        event_type: eventType,
        action: "hmac_rejected",
        notes: `HMAC mismatch. topic='${topic}'`
      });
      return jsonResp({
        error: "hmac_invalid"
      }, 401);
    }
  }
  let payload;
  try {
    payload = JSON.parse(rawBody);
  } catch  {
    return jsonResp({
      error: "invalid_json"
    }, 400);
  }
  const orderId = Number(payload.id ?? 0);
  const orderNumber = String(payload.order_number ?? payload.name ?? "");
  const lineItems = payload.line_items ?? [];
  const sweetpeaLines = lineItems.filter((li)=>isSweetpeaSku(li.sku));
  if (sweetpeaLines.length === 0) {
    await supabase.from("sweetpea_webhook_log").insert({
      shopify_order_id: orderId,
      shopify_order_number: orderNumber,
      event_type: eventType,
      action: "stub_logged",
      notes: `no sweet pea line items (total lines: ${lineItems.length})`,
      raw_payload: {
        verified: !isAdminTest,
        admin_test: isAdminTest,
        phase: "v8"
      }
    });
    return jsonResp({
      status: "ok",
      order_id: orderId,
      phase: "v8",
      skipped: "no_sweetpea"
    });
  }
  const results = [];
  for (const li of sweetpeaLines){
    const sku = String(li.sku ?? "");
    const quantity = Number(li.quantity ?? 0);
    if (quantity <= 0) {
      results.push({
        sku,
        action: "skipped",
        reason: "zero_qty"
      });
      continue;
    }
    if (eventType === "cancel") {
      const result = await handleCancelLine(supabase, orderId, orderNumber, sku, quantity);
      results.push(result);
      continue;
    }
    if (isFixedCollection(sku)) {
      results.push(await handleCollectionLine(supabase, orderId, orderNumber, sku, quantity));
      continue;
    }
    if (isCottagePool(sku)) {
      results.push(await handleCottagePoolLine(supabase, orderId, orderNumber, sku, quantity));
      continue;
    }
    if (isCollection(sku)) {
      const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "unknown LATHCOTT shape");
      if (row === "duplicate") {
        results.push({
          sku,
          action: "duplicate"
        });
        continue;
      }
      if (row === "error") {
        results.push({
          sku,
          action: "log_error"
        });
        continue;
      }
      await finaliseRow(supabase, row.id, "phase_4_deferred", `unrecognised LATHCOTT- SKU — no Phase 3/4 handler matches '${sku}'`, null);
      results.push({
        sku,
        action: "phase_4_deferred"
      });
      continue;
    }
    if (!isPackOfFour(sku)) {
      const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "unexpected sweetpea shape");
      if (row === "duplicate") {
        results.push({
          sku,
          action: "duplicate"
        });
        continue;
      }
      if (row === "error") {
        results.push({
          sku,
          action: "log_error"
        });
        continue;
      }
      await finaliseRow(supabase, row.id, "mo_error", "non-Pack-of-4 sweet pea SKU — unexpected for customer order", null);
      results.push({
        sku,
        action: "mo_error",
        reason: "not_pack_of_4"
      });
      continue;
    }
    results.push(await handlePackOfFourLine(supabase, orderId, orderNumber, sku, quantity));
  }
  return jsonResp({
    status: "ok",
    order_id: orderId,
    order_number: orderNumber,
    event_type: eventType,
    phase: "v8",
    dry_run: DRY_RUN,
    results
  });
});
// ── Phase 5: cancel handler ───────────────────────────
async function handleCancelLine(supabase, orderId, orderNumber, sku, quantity) {
  const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "phase 5 entry", "cancel");
  if (row === "duplicate") return {
    sku,
    action: "duplicate"
  };
  if (row === "error") return {
    sku,
    action: "log_error"
  };
  const { data: pending, error: pendingErr } = await supabase.from("sweetpea_pending_mos").select("*").eq("sku", sku).maybeSingle();
  if (pendingErr) {
    await finaliseRow(supabase, row.id, "cancel_error", `${sku}: sweetpea_pending_mos lookup failed: ${pendingErr.message}`);
    return {
      sku,
      action: "cancel_error",
      reason: "pending_lookup_failed"
    };
  }
  if (!pending) {
    const { data: createRow } = await supabase.from("sweetpea_webhook_log").select("action, notes, processed_at").eq("shopify_order_id", orderId).eq("sku", sku).eq("event_type", "create").maybeSingle();
    const prior = createRow ? `prior create action=${createRow.action}` : "no matching create row in log";
    await finaliseRow(supabase, row.id, "cancel_no_mo", `${sku}: no pending MO (${prior}). Nothing to unwind.`);
    return {
      sku,
      action: "cancel_no_mo",
      prior_create_action: createRow?.action ?? null
    };
  }
  const moId = pending.katana_mo_id;
  const currentQty = pending.current_qty;
  const isCottage = pending.cg_recipe !== null;
  const prefix = isCottage ? "cg_" : "";
  if (quantity > currentQty) {
    await finaliseRow(supabase, row.id, "cancel_error", `${sku}: cancelled qty=${quantity} exceeds MO current_qty=${currentQty}. Data drift — MO not modified.`, moId);
    return {
      sku,
      action: "cancel_error",
      reason: "qty_exceeds_current",
      mo_id: moId
    };
  }
  const moStatus = DRY_RUN ? "NOT_STARTED" : await getMoStatus(moId);
  if (moStatus !== "NOT_STARTED") {
    await finaliseRow(supabase, row.id, "cancel_mo_locked", `${sku}: MO ${moId} status=${moStatus ?? "unknown"} — cannot decrement or delete. Components already allocated or consumed. Manual review.`, moId);
    return {
      sku,
      action: "cancel_mo_locked",
      mo_id: moId,
      mo_status: moStatus
    };
  }
  const newQty = currentQty - quantity;
  if (newQty === 0) {
    if (DRY_RUN) {
      await finaliseRow(supabase, row.id, `dry_run_would_${prefix}delete`, `DRY_RUN — would DELETE MO ${moId} (sku=${sku}, cancelled ${quantity} of ${currentQty})`, moId);
      return {
        sku,
        action: `dry_run_would_${prefix}delete`,
        mo_id: moId,
        from: currentQty,
        to: 0
      };
    }
    const del = await katanaFetch(`/manufacturing_orders/${moId}`, "DELETE");
    if (del.status !== 200 && del.status !== 204) {
      await finaliseRow(supabase, row.id, "cancel_error", `${sku}: Katana DELETE failed for MO ${moId}: ${del.status} ${del.rawText?.slice(0, 200) ?? ""}`, moId);
      return {
        sku,
        action: "cancel_error",
        reason: "delete_failed",
        mo_id: moId,
        status: del.status
      };
    }
    const { error: delPendErr } = await supabase.from("sweetpea_pending_mos").delete().eq("sku", sku);
    const pendingNote = delPendErr ? `pending_mos delete failed: ${delPendErr.message}` : "pending_mos row removed";
    const denyNote = await clearDenyIfDenied(supabase, sku, `sweetpea-order-mo [cancel]: MO ${moId} deleted (cancel freed ${quantity} units)`);
    await finaliseRow(supabase, row.id, `${prefix}mo_deleted`, `${sku}: MO ${moId} deleted (current_qty ${currentQty}→0). ${pendingNote}. ${denyNote}`, moId);
    return {
      sku,
      action: `${prefix}mo_deleted`,
      mo_id: moId,
      from: currentQty,
      to: 0,
      deny_note: denyNote
    };
  }
  if (DRY_RUN) {
    await finaliseRow(supabase, row.id, `dry_run_would_${prefix}decrement`, `DRY_RUN — would PATCH MO ${moId} planned_quantity ${currentQty}→${newQty} (sku=${sku}, cancelled ${quantity})`, moId);
    return {
      sku,
      action: `dry_run_would_${prefix}decrement`,
      mo_id: moId,
      from: currentQty,
      to: newQty
    };
  }
  const patch = await katanaFetch(`/manufacturing_orders/${moId}`, "PATCH", {
    planned_quantity: newQty
  });
  if (patch.status !== 200) {
    await finaliseRow(supabase, row.id, "cancel_error", `${sku}: Katana PATCH failed for MO ${moId} decrement: ${patch.status} ${patch.rawText?.slice(0, 200) ?? ""}`, moId);
    return {
      sku,
      action: "cancel_error",
      reason: "patch_failed",
      mo_id: moId,
      status: patch.status
    };
  }
  const { error: updPendErr } = await supabase.from("sweetpea_pending_mos").update({
    current_qty: newQty,
    updated_at: new Date().toISOString()
  }).eq("sku", sku);
  const pendingNote = updPendErr ? `pending_mos update failed: ${updPendErr.message}` : `pending_mos.current_qty updated to ${newQty}`;
  const denyNote = await clearDenyIfDenied(supabase, sku, `sweetpea-order-mo [cancel]: MO ${moId} decremented (cancel freed ${quantity} units)`);
  await finaliseRow(supabase, row.id, `${prefix}mo_decremented`, `${sku}: MO ${moId} planned_quantity ${currentQty}→${newQty} (cancelled ${quantity}). ${pendingNote}. ${denyNote}`, moId);
  return {
    sku,
    action: `${prefix}mo_decremented`,
    mo_id: moId,
    from: currentQty,
    to: newQty,
    deny_note: denyNote
  };
}
async function clearDenyIfDenied(supabase, sku, reason) {
  const { data: stockRow, error: stockErr } = await supabase.from("katana_stock_sync").select("manual_override").eq("sku", sku).maybeSingle();
  if (stockErr) return `DENY_RESTORE_FAILED: stock lookup error: ${stockErr.message}`;
  if (!stockRow || stockRow.manual_override !== "DENY") return "no DENY override to clear";
  if (DRY_RUN) return "DRY_RUN — would clear DENY override and push CONTINUE to Shopify";
  const push = await pushContinueToShopify(sku, reason);
  if (!push.ok) return `DENY_RESTORE_FAILED: fix-batch-deny error: ${push.detail}`;
  const { error: clearErr } = await supabase.from("katana_stock_sync").update({
    manual_override: null,
    notes: reason
  }).eq("sku", sku);
  if (clearErr) return `DENY_RESTORE_FAILED: override clear failed: ${clearErr.message}`;
  return "DENY cleared and CONTINUE pushed to Shopify";
}
// ── Phase 2: Pack-of-4 handler (unchanged from v7) ────────────────
async function handlePackOfFourLine(supabase, orderId, orderNumber, sku, quantity) {
  const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "phase 2 entry");
  if (row === "duplicate") return {
    sku,
    action: "duplicate"
  };
  if (row === "error") return {
    sku,
    action: "log_error"
  };
  const { data: cfg, error: cfgErr } = await supabase.from("bom_monitoring_config").select("pack_variant_id, component_variant_id, pack_product_name").eq("pack_sku", sku).maybeSingle();
  if (cfgErr || !cfg) {
    await finaliseRow(supabase, row.id, "mo_error", `bom_monitoring_config lookup failed for ${sku}`);
    return {
      sku,
      action: "mo_error",
      reason: "no_config"
    };
  }
  const packVid = cfg.pack_variant_id;
  const componentVid = cfg.component_variant_id;
  if (!packVid || !componentVid) {
    await finaliseRow(supabase, row.id, "mo_error", `bom_monitoring_config missing variant_ids (pack=${packVid}, component=${componentVid})`);
    return {
      sku,
      action: "mo_error",
      reason: "missing_variant_ids"
    };
  }
  const inv = await getInventoryForVariant(componentVid);
  if (!inv) {
    await finaliseRow(supabase, row.id, "mo_error", `Katana inventory lookup failed for SINGLE variant ${componentVid}`);
    return {
      sku,
      action: "mo_error",
      reason: "inventory_failed"
    };
  }
  const required = quantity * 4;
  const bufferOk = inv.freeSingles - required >= SINGLES_BUFFER;
  if (!bufferOk) {
    const shortfall = required + SINGLES_BUFFER - inv.freeSingles;
    const holdNote = `order #${orderNumber} qty=${quantity} required=${required} free=${inv.freeSingles} shortfall=${shortfall}`;
    return await pushHold(supabase, row.id, sku, "pack_of_4", holdNote, {
      shortfall
    });
  }
  return await createOrIncrementMO(supabase, row.id, sku, packVid, quantity);
}
async function handleCollectionLine(supabase, orderId, orderNumber, sku, quantity) {
  const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "phase 3 entry");
  if (row === "duplicate") return {
    sku,
    action: "duplicate"
  };
  if (row === "error") return {
    sku,
    action: "log_error"
  };
  const { data: stockRow, error: stockErr } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", sku).maybeSingle();
  if (stockErr || !stockRow?.katana_variant_id) {
    await finaliseRow(supabase, row.id, "mo_error", `collection ${sku}: katana_stock_sync lookup failed for pack_variant_id`);
    return {
      sku,
      action: "mo_error",
      reason: "no_stock_row"
    };
  }
  const packVid = stockRow.katana_variant_id;
  const { data: recipeRows, error: recipeErr } = await supabase.from("bom_collection_components").select("component_sku, component_variant_id, quantity, is_pool_member").eq("pack_variant_id", packVid).eq("is_pool_member", false);
  if (recipeErr || !recipeRows || recipeRows.length === 0) {
    await finaliseRow(supabase, row.id, "mo_error", `collection ${sku}: no recipe rows in bom_collection_components (pack_variant_id=${packVid})`);
    return {
      sku,
      action: "mo_error",
      reason: "no_recipe"
    };
  }
  const recipe = recipeRows.map((r)=>({
      component_sku: r.component_sku,
      component_variant_id: r.component_variant_id,
      qty_per_pack: r.quantity
    }));
  const checks = [];
  for (const comp of recipe){
    const inv = await getInventoryForVariant(comp.component_variant_id);
    if (!inv) {
      await finaliseRow(supabase, row.id, "mo_error", `collection ${sku}: Katana inventory lookup failed for component ${comp.component_sku} (variant ${comp.component_variant_id})`);
      return {
        sku,
        action: "mo_error",
        reason: "inventory_failed",
        component: comp.component_sku
      };
    }
    const required = quantity * comp.qty_per_pack;
    const pass = inv.freeSingles - required >= SINGLES_BUFFER;
    const shortfall = pass ? 0 : required + SINGLES_BUFFER - inv.freeSingles;
    checks.push({
      component_sku: comp.component_sku,
      required,
      free: inv.freeSingles,
      pass,
      shortfall
    });
  }
  const failures = checks.filter((c)=>!c.pass);
  if (failures.length > 0) {
    const detail = failures.map((c)=>`${c.component_sku}(req=${c.required},free=${c.free},short=${c.shortfall})`).join(", ");
    const holdNote = `order #${orderNumber} qty=${quantity} failed components: ${detail}`;
    const maxShortfall = failures.reduce((m, c)=>Math.max(m, c.shortfall), 0);
    return await pushHold(supabase, row.id, sku, "collection", holdNote, {
      shortfall: maxShortfall,
      failed_components: failures.map((c)=>c.component_sku)
    });
  }
  return await createOrIncrementMO(supabase, row.id, sku, packVid, quantity);
}
async function pickCottagePoolRecipe(supabase, quantity) {
  const { data: poolRows, error: poolErr } = await supabase.from("sweetpea_colour_map").select("single_sku, colour_category").eq("in_cottage_pool", true);
  if (poolErr || !poolRows || poolRows.length === 0) {
    return {
      ok: false,
      reason: `pool read failed: ${poolErr?.message ?? "no pool rows"}`
    };
  }
  const singleSkus = poolRows.map((r)=>r.single_sku);
  const { data: stockRows, error: stockErr } = await supabase.from("katana_stock_sync").select("sku, katana_variant_id").in("sku", singleSkus);
  if (stockErr || !stockRows) {
    return {
      ok: false,
      reason: `stock sync lookup failed: ${stockErr?.message ?? "no rows"}`
    };
  }
  const vidBySku = new Map();
  for (const s of stockRows){
    if (s.katana_variant_id) vidBySku.set(s.sku, s.katana_variant_id);
  }
  const normalised = [];
  const missing = [];
  for (const r of poolRows){
    const sku = r.single_sku;
    const vid = vidBySku.get(sku);
    if (vid) normalised.push({
      single_sku: sku,
      colour_category: r.colour_category,
      variant_id: vid
    });
    else missing.push(sku);
  }
  const candidates = [];
  for (const n of normalised){
    const inv = await getInventoryForVariant(n.variant_id);
    if (!inv) continue;
    candidates.push({
      single_sku: n.single_sku,
      variant_id: n.variant_id,
      colour_category: n.colour_category,
      freeSingles: inv.freeSingles
    });
  }
  const eligible = candidates.filter((c)=>c.freeSingles >= quantity + SINGLES_FLOOR_CG);
  const bySegment = new Map();
  for (const seg of ALL_SEGMENTS)bySegment.set(seg, []);
  for (const c of eligible){
    const arr = bySegment.get(c.colour_category) ?? [];
    arr.push(c);
    bySegment.set(c.colour_category, arr);
  }
  for (const seg of ALL_SEGMENTS){
    const arr = bySegment.get(seg);
    arr.sort((a, b)=>b.freeSingles - a.freeSingles);
  }
  const nonEmptySegments = ALL_SEGMENTS.filter((s)=>(bySegment.get(s)?.length ?? 0) > 0);
  const emptySegments = ALL_SEGMENTS.filter((s)=>(bySegment.get(s)?.length ?? 0) === 0);
  const emptyCount = emptySegments.length;
  const diagnostics = {
    total_pool: candidates.length,
    eligible: eligible.length,
    non_empty_segments: nonEmptySegments.length,
    empty_segments: emptySegments,
    missing_from_stock_sync: missing
  };
  if (emptyCount >= 4) {
    return {
      ok: false,
      sold_out: true,
      reason: `${emptyCount} segments empty (need ≤3). Empty: ${emptySegments.join(", ")}`,
      diagnostics
    };
  }
  const segmentRichness = nonEmptySegments.map((s)=>({
      seg: s,
      richness: (bySegment.get(s) ?? []).reduce((sum, c)=>sum + c.freeSingles, 0)
    })).sort((a, b)=>b.richness - a.richness);
  const doubledSegments = segmentRichness.slice(0, emptyCount).map((x)=>x.seg);
  const singleSegments = segmentRichness.slice(emptyCount).map((x)=>x.seg);
  const recipe = [];
  for (const seg of doubledSegments){
    const members = bySegment.get(seg) ?? [];
    const doubled = members.find((c)=>c.freeSingles >= 2 * quantity + SINGLES_FLOOR_CG);
    if (!doubled) {
      return {
        ok: false,
        sold_out: true,
        reason: `segment '${seg}' chosen for doubling but no variety has freeSingles >= ${2 * quantity + SINGLES_FLOOR_CG}`,
        diagnostics
      };
    }
    recipe.push({
      single_sku: doubled.single_sku,
      variant_id: doubled.variant_id,
      qty_per_pack: 2,
      colour_category: seg,
      recipe_row_id: null,
      free_at_pick: doubled.freeSingles
    });
  }
  for (const seg of singleSegments){
    const pick = (bySegment.get(seg) ?? [])[0];
    if (!pick) return {
      ok: false,
      sold_out: true,
      reason: `segment '${seg}' unexpectedly empty`,
      diagnostics
    };
    recipe.push({
      single_sku: pick.single_sku,
      variant_id: pick.variant_id,
      qty_per_pack: 1,
      colour_category: seg,
      recipe_row_id: null,
      free_at_pick: pick.freeSingles
    });
  }
  const totalUnits = recipe.reduce((s, r)=>s + r.qty_per_pack, 0);
  if (totalUnits !== 8) return {
    ok: false,
    reason: `internal picker error: total units ${totalUnits} != 8`,
    diagnostics
  };
  return {
    ok: true,
    stage: emptyCount,
    recipe,
    diagnostics
  };
}
async function handleCottagePoolLine(supabase, orderId, orderNumber, sku, quantity) {
  const row = await insertProcessingRow(supabase, orderId, orderNumber, sku, quantity, "phase 4 entry");
  if (row === "duplicate") return {
    sku,
    action: "duplicate"
  };
  if (row === "error") return {
    sku,
    action: "log_error"
  };
  const { data: stockRow, error: stockErr } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", sku).maybeSingle();
  if (stockErr || !stockRow?.katana_variant_id) {
    await finaliseRow(supabase, row.id, "cg_mo_error", `cottage ${sku}: katana_stock_sync lookup failed`);
    return {
      sku,
      action: "cg_mo_error",
      reason: "no_stock_row"
    };
  }
  const packVid = stockRow.katana_variant_id;
  const { data: existing } = await supabase.from("sweetpea_pending_mos").select("*").eq("sku", sku).maybeSingle();
  if (existing) {
    const status = DRY_RUN ? "NOT_STARTED" : await getMoStatus(existing.katana_mo_id);
    if (status === "NOT_STARTED") return await incrementCottageMO(supabase, row.id, sku, existing, quantity);
    await supabase.from("sweetpea_pending_mos").delete().eq("sku", sku);
  }
  const pick = await pickCottagePoolRecipe(supabase, quantity);
  if (!pick.ok) {
    if (pick.sold_out) return await cottageSoldOut(supabase, row.id, sku, quantity, pick.reason ?? "unknown", pick.diagnostics);
    await finaliseRow(supabase, row.id, "cg_mo_error", `picker failed: ${pick.reason}`);
    return {
      sku,
      action: "cg_mo_error",
      reason: pick.reason
    };
  }
  return await createCottageMO(supabase, row.id, sku, packVid, quantity, pick);
}
async function incrementCottageMO(supabase, rowId, sku, existing, quantity) {
  const moId = existing.katana_mo_id;
  const currentQty = existing.current_qty;
  const newQty = currentQty + quantity;
  if (DRY_RUN) {
    await finaliseRow(supabase, rowId, "dry_run_would_cg_increment", `DRY_RUN — would PATCH MO ${moId} planned_quantity ${currentQty}→${newQty} (sku=${sku})`, moId);
    return {
      sku,
      action: "dry_run_would_cg_increment",
      mo_id: moId,
      from: currentQty,
      to: newQty
    };
  }
  const patch = await katanaFetch(`/manufacturing_orders/${moId}`, "PATCH", {
    planned_quantity: newQty
  });
  if (patch.status !== 200) {
    await finaliseRow(supabase, rowId, "cg_mo_error", `Katana PATCH failed on increment: ${patch.status} ${patch.rawText?.slice(0, 200) ?? ""}`, moId);
    return {
      sku,
      action: "cg_mo_error",
      reason: "patch_failed",
      status: patch.status
    };
  }
  await supabase.from("sweetpea_pending_mos").update({
    current_qty: newQty,
    updated_at: new Date().toISOString()
  }).eq("sku", sku);
  await finaliseRow(supabase, rowId, "cg_mo_incremented", `planned_quantity ${currentQty}→${newQty} (sku=${sku}) — recipe unchanged (Katana auto-scales)`, moId);
  return {
    sku,
    action: "cg_mo_incremented",
    mo_id: moId,
    from: currentQty,
    to: newQty
  };
}
async function cottageSoldOut(supabase, rowId, sku, quantity, reason, diagnostics) {
  const diagNote = diagnostics ? `pool=${diagnostics.total_pool} eligible=${diagnostics.eligible} non_empty=${diagnostics.non_empty_segments}/8 empty=[${diagnostics.empty_segments.join(",")}]` : "";
  if (DRY_RUN) {
    await finaliseRow(supabase, rowId, "dry_run_would_cg_sold_out", `DRY_RUN — CG sold out for qty=${quantity}. ${reason}. ${diagNote}. Would set DENY and push to Shopify.`);
    return {
      sku,
      action: "dry_run_would_cg_sold_out",
      reason,
      diagnostics
    };
  }
  const { error: ovErr } = await supabase.from("katana_stock_sync").update({
    manual_override: "DENY",
    notes: `sweetpea-order-mo [cottage]: sold out — ${reason}`
  }).eq("sku", sku);
  const ovDetail = ovErr ? `manual_override update error: ${ovErr.message}` : "manual_override=DENY set";
  const push = await pushDenyToShopify(sku, `sweetpea-order-mo [cottage]: sold out — ${reason}`);
  const pushDetail = push.ok ? `fix-batch-deny ok: ${push.detail}` : `fix-batch-deny FAIL: ${push.detail}`;
  await finaliseRow(supabase, rowId, "cg_sold_out", `qty=${quantity} sold out: ${reason}. ${diagNote} | ${ovDetail} | ${pushDetail}`);
  return {
    sku,
    action: "cg_sold_out",
    reason,
    manual_override_ok: !ovErr,
    shopify_deny_pushed: push.ok,
    diagnostics
  };
}
async function createCottageMO(supabase, rowId, sku, packVid, quantity, pick) {
  const recipe = pick.recipe;
  const short = packShortName(sku);
  const date = todayYYMMDD();
  if (DRY_RUN) {
    const orderNo = `MO-${short}-${date}-1`;
    const recipeSummary = recipe.map((r)=>`${r.colour_category}:${r.single_sku.replace("-SINGLE", "")}×${r.qty_per_pack}`).join(", ");
    await finaliseRow(supabase, rowId, "dry_run_would_cg_create", `DRY_RUN — would POST MO ${orderNo} qty=${quantity} variant_id=${packVid} stage=${pick.stage} recipe=[${recipeSummary}]`);
    return {
      sku,
      action: "dry_run_would_cg_create",
      order_no: orderNo,
      qty: quantity,
      stage: pick.stage,
      recipe: recipe.map((r)=>({
          single_sku: r.single_sku,
          qty_per_pack: r.qty_per_pack,
          colour_category: r.colour_category,
          free_at_pick: r.free_at_pick
        }))
    };
  }
  const n = await findNextN(short, date);
  if (n === null) {
    await finaliseRow(supabase, rowId, "cg_mo_error", `probe exhausted: MO-${short}-${date}-{1..${MAX_PROBE_N}} all taken`);
    return {
      sku,
      action: "cg_mo_error",
      reason: "probe_exhausted"
    };
  }
  const orderNo = `MO-${short}-${date}-${n}`;
  const post = await katanaFetch("/manufacturing_orders", "POST", {
    order_no: orderNo,
    variant_id: packVid,
    planned_quantity: quantity,
    location_id: GROVE_CROSS
  });
  if (post.status !== 200 && post.status !== 201) {
    await finaliseRow(supabase, rowId, "cg_mo_error", `Katana POST failed: ${post.status} ${post.rawText?.slice(0, 200) ?? ""}`);
    return {
      sku,
      action: "cg_mo_error",
      reason: "post_failed",
      status: post.status
    };
  }
  const moId = Number(post.data?.id ?? 0);
  if (!moId) {
    await finaliseRow(supabase, rowId, "cg_mo_error", "Katana POST response missing id");
    return {
      sku,
      action: "cg_mo_error",
      reason: "no_mo_id"
    };
  }
  const autoRows = await getMoRecipeRows(moId);
  if (autoRows === null) {
    await finaliseRow(supabase, rowId, "cg_mo_error", `MO ${moId} created but recipe row GET failed — orphan MO`, moId);
    return {
      sku,
      action: "cg_mo_error",
      reason: "recipe_get_failed",
      mo_id: moId
    };
  }
  const chosenVariantIds = new Set(recipe.map((r)=>r.variant_id));
  for (const autoRow of autoRows){
    if (!chosenVariantIds.has(autoRow.variant_id)) {
      const ok = await deleteMoRecipeRow(autoRow.id);
      if (!ok) {
        await finaliseRow(supabase, rowId, "cg_mo_error", `MO ${moId}: failed to DELETE non-chosen recipe row ${autoRow.id} (variant ${autoRow.variant_id})`, moId);
        return {
          sku,
          action: "cg_mo_error",
          reason: "recipe_delete_failed",
          mo_id: moId
        };
      }
    }
  }
  for (const entry of recipe){
    const existingRow = autoRows.find((ar)=>ar.variant_id === entry.variant_id);
    if (existingRow) {
      if (Math.abs(existingRow.planned_quantity_per_unit - entry.qty_per_pack) > 0.0001) {
        const ok = await updateMoRecipeRow(existingRow.id, entry.qty_per_pack);
        if (!ok) {
          await finaliseRow(supabase, rowId, "cg_mo_error", `MO ${moId}: failed to PATCH recipe row ${existingRow.id}`, moId);
          return {
            sku,
            action: "cg_mo_error",
            reason: "recipe_patch_failed",
            mo_id: moId
          };
        }
      }
      entry.recipe_row_id = existingRow.id;
    } else {
      const created = await createMoRecipeRow(moId, entry.variant_id, entry.qty_per_pack);
      if (!created) {
        await finaliseRow(supabase, rowId, "cg_mo_error", `MO ${moId}: failed to POST recipe row for variant ${entry.variant_id}`, moId);
        return {
          sku,
          action: "cg_mo_error",
          reason: "recipe_post_failed",
          mo_id: moId
        };
      }
      entry.recipe_row_id = created.id;
    }
  }
  const { error: insErr } = await supabase.from("sweetpea_pending_mos").insert({
    sku,
    katana_mo_id: moId,
    katana_variant_id: packVid,
    current_qty: quantity,
    cg_recipe: recipe
  });
  if (insErr) {
    await finaliseRow(supabase, rowId, "cg_mo_created", `opened ${orderNo} qty=${quantity} — pending_mos insert race: ${insErr.message}`, moId);
    return {
      sku,
      action: "cg_mo_created",
      mo_id: moId,
      order_no: orderNo,
      note: "pending_race"
    };
  }
  const recipeSummary = recipe.map((r)=>`${r.colour_category}:${r.single_sku.replace("-SINGLE", "")}×${r.qty_per_pack}`).join(", ");
  await finaliseRow(supabase, rowId, "cg_mo_created", `opened ${orderNo} qty=${quantity} stage=${pick.stage} recipe=[${recipeSummary}]`, moId);
  return {
    sku,
    action: "cg_mo_created",
    mo_id: moId,
    order_no: orderNo,
    stage: pick.stage,
    recipe: recipe.map((r)=>({
        single_sku: r.single_sku,
        qty_per_pack: r.qty_per_pack,
        colour_category: r.colour_category,
        recipe_row_id: r.recipe_row_id
      }))
  };
}
// ── Phase 2/3 commit helper (unchanged from v7) ────────────────
async function createOrIncrementMO(supabase, rowId, sku, packVid, quantity) {
  const { data: existing } = await supabase.from("sweetpea_pending_mos").select("*").eq("sku", sku).maybeSingle();
  if (existing) {
    const status = DRY_RUN ? "NOT_STARTED" : await getMoStatus(existing.katana_mo_id);
    if (status === "NOT_STARTED") {
      const moId = existing.katana_mo_id;
      const newQty = existing.current_qty + quantity;
      if (DRY_RUN) {
        await finaliseRow(supabase, rowId, "dry_run_would_increment", `DRY_RUN — would PATCH MO ${moId} planned_quantity ${existing.current_qty}→${newQty} (sku=${sku})`, moId);
        return {
          sku,
          action: "dry_run_would_increment",
          mo_id: moId,
          from: existing.current_qty,
          to: newQty
        };
      }
      const patch = await katanaFetch(`/manufacturing_orders/${moId}`, "PATCH", {
        planned_quantity: newQty
      });
      if (patch.status !== 200) {
        await finaliseRow(supabase, rowId, "mo_error", `Katana PATCH failed: ${patch.status} ${patch.rawText?.slice(0, 200) ?? ""}`, moId);
        return {
          sku,
          action: "mo_error",
          reason: "patch_failed",
          status: patch.status
        };
      }
      await supabase.from("sweetpea_pending_mos").update({
        current_qty: newQty,
        updated_at: new Date().toISOString()
      }).eq("sku", sku);
      await finaliseRow(supabase, rowId, "mo_incremented", `planned_quantity ${existing.current_qty}→${newQty} (sku=${sku})`, moId);
      return {
        sku,
        action: "mo_incremented",
        mo_id: moId,
        from: existing.current_qty,
        to: newQty
      };
    }
    await supabase.from("sweetpea_pending_mos").delete().eq("sku", sku);
  }
  const short = packShortName(sku);
  const date = todayYYMMDD();
  if (DRY_RUN) {
    const orderNo = `MO-${short}-${date}-1`;
    await finaliseRow(supabase, rowId, "dry_run_would_create", `DRY_RUN — would POST MO ${orderNo} qty=${quantity} variant_id=${packVid} (sku=${sku})`);
    return {
      sku,
      action: "dry_run_would_create",
      order_no: orderNo,
      qty: quantity
    };
  }
  const n = await findNextN(short, date);
  if (n === null) {
    await finaliseRow(supabase, rowId, "mo_error", `probe exhausted: MO-${short}-${date}-{1..${MAX_PROBE_N}} all taken`);
    return {
      sku,
      action: "mo_error",
      reason: "probe_exhausted"
    };
  }
  const orderNo = `MO-${short}-${date}-${n}`;
  const post = await katanaFetch("/manufacturing_orders", "POST", {
    order_no: orderNo,
    variant_id: packVid,
    planned_quantity: quantity,
    location_id: GROVE_CROSS
  });
  if (post.status !== 200 && post.status !== 201) {
    await finaliseRow(supabase, rowId, "mo_error", `Katana POST failed: ${post.status} ${post.rawText?.slice(0, 200) ?? ""}`);
    return {
      sku,
      action: "mo_error",
      reason: "post_failed",
      status: post.status
    };
  }
  const moId = Number(post.data?.id ?? 0);
  if (!moId) {
    await finaliseRow(supabase, rowId, "mo_error", "Katana POST response missing id");
    return {
      sku,
      action: "mo_error",
      reason: "no_mo_id"
    };
  }
  const { error: insErr } = await supabase.from("sweetpea_pending_mos").insert({
    sku,
    katana_mo_id: moId,
    katana_variant_id: packVid,
    current_qty: quantity
  });
  if (insErr) {
    await finaliseRow(supabase, rowId, "mo_created", `opened ${orderNo} qty=${quantity} — pending_mos insert race: ${insErr.message}`, moId);
    return {
      sku,
      action: "mo_created",
      mo_id: moId,
      order_no: orderNo,
      note: "pending_race"
    };
  }
  await finaliseRow(supabase, rowId, "mo_created", `opened ${orderNo} qty=${quantity}`, moId);
  return {
    sku,
    action: "mo_created",
    mo_id: moId,
    order_no: orderNo
  };
}
async function pushHold(supabase, rowId, sku, kind, baseNote, extra) {
  if (DRY_RUN) {
    await finaliseRow(supabase, rowId, "dry_run_would_hold", `DRY_RUN — buffer fails [${kind}]. ${baseNote}. Would set manual_override=DENY and call fix-batch-deny.`);
    return {
      sku,
      action: "dry_run_would_hold",
      ...extra
    };
  }
  const { error: ovErr } = await supabase.from("katana_stock_sync").update({
    manual_override: "DENY",
    notes: `sweetpea-order-mo [${kind}]: low singles buffer. ${baseNote}`
  }).eq("sku", sku);
  const ovDetail = ovErr ? `manual_override update error: ${ovErr.message}` : "manual_override=DENY set";
  const reason = `sweetpea-order-mo [${kind}]: low singles buffer — ${baseNote}`;
  const push = await pushDenyToShopify(sku, reason);
  const pushDetail = push.ok ? `fix-batch-deny ok: ${push.detail}` : `fix-batch-deny FAIL: ${push.detail}`;
  await finaliseRow(supabase, rowId, "mo_held_low_singles", `${baseNote} | ${ovDetail} | ${pushDetail}`);
  return {
    sku,
    action: "mo_held_low_singles",
    manual_override_ok: !ovErr,
    shopify_deny_pushed: push.ok,
    ...extra
  };
}
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json"
    }
  });
}
