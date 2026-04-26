// ============================================================
// sweetpea-reservation-receiver v3 — v2 + 429 retry with backoff
// Patches applied:
//   1. Removed broken pg_advisory_lock/unlock RPC calls
//      (PostgREST doesn't expose built-in Postgres functions)
//      Partial-unique indexes are the real concurrency safety net.
//   2. Outer try/catch wraps the handler to surface crashes as
//      JSON 500 with error message, logged to sweetpea_error_state.
// ============================================================
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { pickRecipe } from "./sweetpea-picker.ts";
// ─── Config ─────────────────────────────────────────────────
const SHOPIFY_SECRET = Deno.env.get("SHOPIFY_CLIENT_KEY") ?? "";
const KATANA_TOKEN = Deno.env.get("KATANA_TOKEN") ?? "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const KATANA_BASE = Deno.env.get("KATANA_BASE") ?? "https://api.katanamrp.com/v1";
const GROVE_CROSS = 162781;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DRY_RUN = (Deno.env.get("SWEETPEA_RESERVATION_DRY_RUN") ?? "false").toLowerCase() === "true";
const doFetch = (...args)=>fetch(...args);
// ─── SKU classification ─────────────────────────────────────
function isSweetpeaSku(sku) {
  if (!sku) return false;
  return sku.startsWith("LATHODO") || sku.startsWith("LATHCOTT-");
}
function isPackOfFour(sku) {
  if (!sku.startsWith("LATHODO")) return false;
  return sku.includes("-Pack of 4") || sku.endsWith("-Pk4");
}
function isCollection(sku) {
  return sku.startsWith("LATHCOTT-");
}
// ─── HMAC ───────────────────────────────────────────────────
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
async function katanaCall(path, method, body) {
  const opts = {
    method,
    headers: {
      Authorization: `Bearer ${KATANA_TOKEN}`,
      "Content-Type": "application/json"
    }
  };
  if (body) opts.body = JSON.stringify(body);
  // Katana is 30 calls/min (2s minimum per call). Retry on 429 with backoff,
  // and on 5xx with a shorter retry. Three attempts total.
  let lastStatus = 0;
  let lastText = "";
  for(let attempt = 1; attempt <= 3; attempt++){
    const resp = await doFetch(`${KATANA_BASE}${path}`, opts);
    lastStatus = resp.status;
    if (resp.status === 204) return {
      status: 204,
      data: null
    };
    if (resp.status === 429 && attempt < 3) {
      // Rate-limited. Back off generously — Katana's window is 60s.
      const backoffMs = attempt === 1 ? 5000 : 30000;
      await new Promise((r)=>setTimeout(r, backoffMs));
      continue;
    }
    if (resp.status >= 500 && attempt < 3) {
      await new Promise((r)=>setTimeout(r, 2000));
      continue;
    }
    const text = await resp.text();
    lastText = text;
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
  return {
    status: lastStatus,
    data: null,
    rawText: `retry loop exhausted: ${lastText}`
  };
}
// ─── Logging helpers ───────────────────────────────────────
async function logError(sb, params) {
  await sb.from("sweetpea_error_state").insert({
    category: params.category,
    subcategory: params.subcategory,
    severity: params.severity,
    detector: params.detector ?? "sweetpea-reservation-receiver",
    affected_sku: params.affectedSku ?? null,
    affected_mo_id: params.affectedMoId ?? null,
    detail: params.detail,
    status: "open"
  });
}
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json"
    }
  });
}
// ─── Entry ─────────────────────────────────────────────────
Deno.serve(async (req)=>{
  // Outer try/catch: surface any uncaught crash as JSON 500 with error details.
  try {
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
    const sb = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: {
        persistSession: false
      }
    });
    const authHeader = req.headers.get("authorization") ?? "";
    const isAdminTest = authHeader.startsWith("Bearer ") && authHeader.slice(7) === SERVICE_KEY;
    if (!isAdminTest) {
      if (!SHOPIFY_SECRET) {
        await logError(sb, {
          category: "authentication",
          subcategory: "secret_not_configured",
          severity: "critical",
          detail: {
            topic,
            hint: "SHOPIFY_CLIENT_KEY env var missing"
          }
        });
        return jsonResp({
          error: "secret_not_configured"
        }, 500);
      }
      const valid = await verifyHmac(rawBody, providedHmac);
      if (!valid) {
        await logError(sb, {
          category: "authentication",
          subcategory: "hmac_invalid",
          severity: "critical",
          detail: {
            topic,
            event_type: eventType
          }
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
      await logError(sb, {
        category: "payload",
        subcategory: "invalid_json",
        severity: "warning",
        detail: {
          body_preview: rawBody.slice(0, 200)
        }
      });
      return jsonResp({
        error: "invalid_json"
      }, 400);
    }
    const orderId = Number(payload.id ?? 0);
    const orderNumber = String(payload.order_number ?? payload.name ?? "");
    const lineItemsRaw = payload.line_items;
    if (!orderId || !Array.isArray(lineItemsRaw)) {
      await logError(sb, {
        category: "payload",
        subcategory: "malformed_payload",
        severity: "warning",
        detail: {
          has_order_id: !!orderId,
          has_line_items_array: Array.isArray(lineItemsRaw),
          event_type: eventType
        }
      });
      return jsonResp({
        error: "malformed_payload"
      }, 400);
    }
    const lineItems = lineItemsRaw;
    for (const li of lineItems){
      if (li.sku === undefined || li.sku === null || typeof li.sku !== "string") {
        await logError(sb, {
          category: "payload",
          subcategory: "malformed_payload",
          severity: "warning",
          detail: {
            issue: "line_item missing sku",
            order_id: orderId
          }
        });
        return jsonResp({
          error: "malformed_line_item"
        }, 400);
      }
      if (li.quantity === undefined || li.quantity === null) {
        await logError(sb, {
          category: "payload",
          subcategory: "malformed_payload",
          severity: "warning",
          detail: {
            issue: "line_item missing quantity",
            sku: li.sku,
            order_id: orderId
          }
        });
        return jsonResp({
          error: "malformed_line_item"
        }, 400);
      }
    }
    const sweetpeaLines = lineItems.filter((li)=>isSweetpeaSku(li.sku));
    if (sweetpeaLines.length === 0) {
      const { error: stubErr } = await sb.from("sweetpea_webhook_log").insert({
        shopify_order_id: orderId,
        shopify_order_number: orderNumber,
        event_type: eventType,
        action: "no_sweetpea_lines",
        notes: `total lines: ${lineItems.length}`,
        raw_payload: {
          phase: "v2_receiver",
          stub: true
        }
      });
      if (stubErr && stubErr.code === "23505") {
        return jsonResp({
          status: "duplicate_deduped",
          order_id: orderId
        });
      }
      return jsonResp({
        status: "ok",
        order_id: orderId,
        skipped: "no_sweetpea"
      });
    }
    const results = [];
    for (const li of sweetpeaLines){
      const sku = String(li.sku);
      const quantity = Number(li.quantity);
      if (!Number.isFinite(quantity) || quantity <= 0) {
        results.push({
          sku,
          action: "skipped",
          reason: "non_positive_qty"
        });
        continue;
      }
      if (eventType === "cancel") {
        results.push(await handleCancel(sb, orderId, orderNumber, sku, quantity));
        continue;
      }
      results.push(await handleCreate(sb, orderId, orderNumber, sku, quantity));
    }
    return jsonResp({
      status: "ok",
      order_id: orderId,
      order_number: orderNumber,
      event_type: eventType,
      dry_run: DRY_RUN,
      results
    });
  } catch (err) {
    // Diagnostic: capture uncaught exception details
    const msg = err instanceof Error ? err.message : String(err);
    const stack = err instanceof Error ? err.stack ?? "" : "";
    try {
      const sbDiag = createClient(SUPABASE_URL, SERVICE_KEY, {
        auth: {
          persistSession: false
        }
      });
      await sbDiag.from("sweetpea_error_state").insert({
        category: "receiver",
        subcategory: "uncaught_exception",
        severity: "critical",
        detector: "sweetpea-reservation-receiver",
        detail: {
          error: msg,
          stack: stack.slice(0, 2000)
        },
        status: "open"
      });
    } catch (_) {}
    return jsonResp({
      error: "internal_error",
      message: msg,
      stack_preview: stack.slice(0, 500)
    }, 500);
  }
});
async function writeLogRow(sb, orderId, orderNumber, sku, quantity, eventType, phaseNote) {
  const { data, error } = await sb.from("sweetpea_webhook_log").insert({
    shopify_order_id: orderId,
    shopify_order_number: orderNumber,
    event_type: eventType,
    sku,
    quantity,
    action: "processing",
    notes: phaseNote
  }).select("id").single();
  if (error) {
    if (error.code === "23505") return {
      kind: "duplicate"
    };
    return {
      kind: "error",
      detail: error.message
    };
  }
  return {
    kind: "ok",
    id: data.id
  };
}
async function finaliseLog(sb, logId, action, notes, moId) {
  const patch = {
    action,
    notes
  };
  if (moId !== undefined && moId !== null) patch.mo_id = moId;
  await sb.from("sweetpea_webhook_log").update(patch).eq("id", logId);
}
// ─── Create path ───────────────────────────────────────────
async function handleCreate(sb, orderId, orderNumber, sku, quantity) {
  const logRes = await writeLogRow(sb, orderId, orderNumber, sku, quantity, "create", "v3 create entry");
  if (logRes.kind === "duplicate") {
    await logError(sb, {
      category: "idempotency",
      subcategory: "duplicate_webhook",
      severity: "info",
      affectedSku: sku,
      detail: {
        order_id: orderId,
        sku,
        event_type: "create"
      }
    });
    return {
      sku,
      action: "duplicate_deduped"
    };
  }
  if (logRes.kind === "error") {
    return {
      sku,
      action: "log_error",
      detail: logRes.detail
    };
  }
  const logId = logRes.id;
  // Advisory lock removed — pg_advisory_lock isn't exposed via PostgREST
  // RPC. Partial unique indexes provide the concurrency safety net.
  if (isPackOfFour(sku)) {
    return await processPackLine(sb, logId, sku, quantity);
  }
  if (isCollection(sku)) {
    return await processCollectionLine(sb, logId, sku, quantity);
  }
  await finaliseLog(sb, logId, "mo_error", `unexpected sweet pea shape: ${sku}`);
  await logError(sb, {
    category: "classification",
    subcategory: "unknown_sku_shape",
    severity: "warning",
    affectedSku: sku,
    detail: {
      sku,
      reason: "not Pack-of-4, not LATHCOTT-"
    }
  });
  return {
    sku,
    action: "mo_error",
    reason: "unknown_sku_shape"
  };
}
// ─── Pack-of-4 path ────────────────────────────────────────
async function processPackLine(sb, logId, sku, quantity) {
  const { data: bom, error: bomErr } = await sb.from("bom_monitoring_config").select("pack_variant_id, component_sku, component_variant_id, bom_multiplier").eq("pack_sku", sku).maybeSingle();
  if (bomErr || !bom) {
    await finaliseLog(sb, logId, "mo_error", `BOM lookup failed for ${sku}: ${bomErr?.message ?? "no row"}`);
    await logError(sb, {
      category: "configuration",
      subcategory: "bom_missing",
      severity: "warning",
      affectedSku: sku,
      detail: {
        sku,
        error: bomErr?.message ?? "no bom row"
      }
    });
    return {
      sku,
      action: "mo_error",
      reason: "no_bom"
    };
  }
  const componentSku = bom.component_sku;
  const bomMultiplier = bom.bom_multiplier;
  const packVid = bom.pack_variant_id;
  const { data: allocRow, error: allocErr } = await sb.from("v_sweetpea_allocatable").select("sku, allocatable").eq("sku", componentSku).maybeSingle();
  const allocatable = allocErr || !allocRow ? 0 : Number(allocRow.allocatable) || 0;
  const { data: existingActive } = await sb.from("sweetpea_pending_mos").select("*").eq("sku", sku).eq("flavour", "reservation").in("status", [
    "NOT_STARTED",
    "pending_katana_create"
  ]).maybeSingle();
  const { data: existingBlocked } = await sb.from("sweetpea_pending_mos").select("*").eq("sku", sku).eq("flavour", "reservation").eq("status", "blocked_on_supply").maybeSingle();
  const allocSnapshot = new Map([
    [
      componentSku,
      allocatable
    ]
  ]);
  const pickerInput = {
    outputSku: sku,
    requestedQuantity: quantity,
    allocatableSnapshot: allocSnapshot,
    pack: {
      component_sku: componentSku,
      bom_multiplier: bomMultiplier
    }
  };
  const result = pickRecipe(pickerInput);
  if (result.kind === "ok") {
    if (existingActive) {
      return await incrementExistingMo(sb, logId, sku, existingActive, quantity);
    }
    return await createReservationMo(sb, logId, sku, packVid, quantity, result.recipe, "NOT_STARTED");
  }
  if (result.kind === "split") {
    const primaryQty = result.primaryQuantity;
    const shortfall = result.shortfallQuantity;
    let primaryMo = null;
    if (primaryQty > 0) {
      if (existingActive) {
        primaryMo = await incrementExistingMo(sb, logId, sku, existingActive, primaryQty);
      } else {
        primaryMo = await createReservationMo(sb, logId, sku, packVid, primaryQty, result.primaryRecipe, "NOT_STARTED");
      }
    }
    let blockedMo = null;
    if (existingBlocked) {
      blockedMo = await incrementExistingBlocked(sb, logId, sku, existingBlocked, shortfall);
    } else {
      blockedMo = await createBlockedMo(sb, logId, sku, packVid, shortfall);
    }
    await finaliseLog(sb, logId, "split_created", `primary qty=${primaryQty} blocked qty=${shortfall}`, null);
    return {
      sku,
      action: "split",
      primary: primaryMo,
      blocked: blockedMo
    };
  }
  await finaliseLog(sb, logId, "needs_decision", JSON.stringify(result.diagnostics));
  await logError(sb, {
    category: "picker",
    subcategory: "needs_decision",
    severity: "warning",
    affectedSku: sku,
    detail: {
      reason: result.reason,
      diagnostics: result.diagnostics
    }
  });
  return {
    sku,
    action: "needs_decision",
    reason: result.reason
  };
}
// ─── Collection path ───────────────────────────────────────
async function processCollectionLine(sb, logId, sku, quantity) {
  const { data: segRows, error: segErr } = await sb.from("sweetpea_collection_segments").select("segment_name, segment_order, pack_size, qty_per_pack_fixed, singles_floor, emptiness_tolerance").eq("collection_sku", sku);
  if (segErr || !segRows || segRows.length === 0) {
    await finaliseLog(sb, logId, "mo_error", `collection ${sku}: no segment config`);
    await logError(sb, {
      category: "configuration",
      subcategory: "collection_segments_missing",
      severity: "warning",
      affectedSku: sku,
      detail: {
        sku
      }
    });
    return {
      sku,
      action: "mo_error",
      reason: "no_segments"
    };
  }
  const segments = segRows.map((r)=>({
      segment_name: r.segment_name,
      segment_order: r.segment_order,
      pack_size: r.pack_size,
      qty_per_pack_fixed: r.qty_per_pack_fixed,
      singles_floor: r.singles_floor,
      emptiness_tolerance: r.emptiness_tolerance
    }));
  const { data: stockRow } = await sb.from("katana_stock_sync").select("katana_variant_id").eq("sku", sku).maybeSingle();
  const packVid = stockRow?.katana_variant_id;
  if (!packVid) {
    await finaliseLog(sb, logId, "mo_error", `collection ${sku}: no katana_variant_id`);
    return {
      sku,
      action: "mo_error",
      reason: "no_pack_variant_id"
    };
  }
  const { data: cmapRows } = await sb.from("sweetpea_colour_map").select("variety_stub, single_sku, colour_category, in_cottage_pool").eq("in_cottage_pool", true);
  const colourMap = new Map();
  for (const c of cmapRows ?? []){
    colourMap.set(c.single_sku, {
      colour_category: c.colour_category,
      in_cottage_pool: c.in_cottage_pool,
      variety_stub: c.variety_stub ?? undefined
    });
  }
  const { data: allocRows } = await sb.from("v_sweetpea_allocatable").select("sku, allocatable");
  const allocSnapshot = new Map();
  for (const a of allocRows ?? []){
    allocSnapshot.set(a.sku, Number(a.allocatable) || 0);
  }
  const { data: existingActive } = await sb.from("sweetpea_pending_mos").select("*").eq("sku", sku).eq("flavour", "reservation").in("status", [
    "NOT_STARTED",
    "pending_katana_create"
  ]).maybeSingle();
  const pickerInput = {
    outputSku: sku,
    requestedQuantity: quantity,
    allocatableSnapshot: allocSnapshot,
    collection: {
      colourMap,
      segmentConfig: {
        collection_sku: sku,
        segments
      }
    }
  };
  const result = pickRecipe(pickerInput);
  if (result.kind === "needs_decision") {
    await finaliseLog(sb, logId, "needs_decision", JSON.stringify(result.diagnostics));
    await logError(sb, {
      category: "picker",
      subcategory: "needs_decision",
      severity: "warning",
      affectedSku: sku,
      detail: {
        reason: result.reason,
        diagnostics: result.diagnostics
      }
    });
    return {
      sku,
      action: "needs_decision",
      reason: result.reason
    };
  }
  if (result.kind === "split") {
    await finaliseLog(sb, logId, "needs_decision", "collection unexpectedly returned SPLIT");
    return {
      sku,
      action: "needs_decision",
      reason: "collection_split_unexpected"
    };
  }
  if (existingActive) {
    return await incrementExistingMo(sb, logId, sku, existingActive, quantity);
  }
  return await createReservationMo(sb, logId, sku, packVid, quantity, result.recipe, "NOT_STARTED");
}
// ─── Two-phase MO create ───────────────────────────────────
async function createReservationMo(sb, logId, sku, packVid, quantity, recipe, targetStatus) {
  const { data: ins, error: insErr } = await sb.from("sweetpea_pending_mos").insert({
    sku,
    katana_variant_id: packVid,
    planned_quantity: quantity,
    status: "pending_katana_create",
    flavour: "reservation"
  }).select("id").single();
  if (insErr) {
    if (insErr.code === "23505") {
      await finaliseLog(sb, logId, "mo_race", `partial unique fired on INSERT; retry would increment`);
      return {
        sku,
        action: "mo_race",
        reason: "insert_race"
      };
    }
    await finaliseLog(sb, logId, "mo_error", `pending_mos INSERT failed: ${insErr.message}`);
    return {
      sku,
      action: "mo_error",
      reason: "insert_failed",
      detail: insErr.message
    };
  }
  const moRowId = ins.id;
  for (const r of recipe){
    await sb.from("sweetpea_mo_recipes").insert({
      mo_id: moRowId,
      single_sku: r.single_sku,
      qty_per_pack: r.qty_per_pack,
      segment_name: r.segment_name
    });
  }
  if (DRY_RUN) {
    await sb.from("sweetpea_pending_mos").update({
      status: "NOT_STARTED",
      katana_mo_id: 999999
    }).eq("id", moRowId);
    await finaliseLog(sb, logId, "mo_created_dry", `DRY_RUN mo_row=${moRowId} sku=${sku} qty=${quantity}`, moRowId);
    return {
      sku,
      action: "mo_created_dry",
      mo_row_id: moRowId,
      qty: quantity
    };
  }
  const orderNo = `RES-${sku.replace(/[^A-Za-z0-9]/g, "").slice(0, 16)}-${moRowId}`;
  const katanaResp = await katanaCall("/manufacturing_orders", "POST", {
    order_no: orderNo,
    variant_id: packVid,
    planned_quantity: quantity,
    location_id: GROVE_CROSS
  });
  if (katanaResp.status !== 200 && katanaResp.status !== 201) {
    await sb.from("sweetpea_pending_mos").update({
      status: "mo_error"
    }).eq("id", moRowId);
    await logError(sb, {
      category: "katana",
      subcategory: "post_failed",
      severity: "critical",
      affectedSku: sku,
      affectedMoId: moRowId,
      detail: {
        status: katanaResp.status,
        body: (katanaResp.rawText ?? "").slice(0, 500),
        order_no: orderNo
      }
    });
    await finaliseLog(sb, logId, "mo_error", `Katana POST failed status=${katanaResp.status}`, moRowId);
    return {
      sku,
      action: "mo_error",
      reason: "katana_post_failed",
      status: katanaResp.status
    };
  }
  const katanaMoId = Number(katanaResp.data?.id ?? 0);
  await sb.from("sweetpea_pending_mos").update({
    status: targetStatus,
    katana_mo_id: katanaMoId || null
  }).eq("id", moRowId);
  await finaliseLog(sb, logId, "mo_created", `sku=${sku} qty=${quantity} katana_mo=${katanaMoId} order_no=${orderNo}`, moRowId);
  return {
    sku,
    action: "mo_created",
    mo_row_id: moRowId,
    katana_mo_id: katanaMoId,
    order_no: orderNo,
    qty: quantity
  };
}
async function incrementExistingMo(sb, logId, sku, existing, addQty) {
  const moRowId = existing.id;
  const katanaMoId = existing.katana_mo_id;
  const currentQty = existing.planned_quantity;
  const newQty = currentQty + addQty;
  if (katanaMoId && !DRY_RUN) {
    const patch = await katanaCall(`/manufacturing_orders/${katanaMoId}`, "PATCH", {
      planned_quantity: newQty
    });
    if (patch.status !== 200) {
      await logError(sb, {
        category: "katana",
        subcategory: "patch_drift",
        severity: "warning",
        affectedSku: sku,
        affectedMoId: moRowId,
        detail: {
          katana_mo_id: katanaMoId,
          attempted_qty: newQty,
          status: patch.status,
          body: (patch.rawText ?? "").slice(0, 500)
        }
      });
      await finaliseLog(sb, logId, "mo_error", `Katana PATCH failed status=${patch.status}`, moRowId);
      return {
        sku,
        action: "mo_error",
        reason: "katana_patch_failed",
        status: patch.status
      };
    }
  }
  await sb.from("sweetpea_pending_mos").update({
    planned_quantity: newQty,
    updated_at: new Date().toISOString()
  }).eq("id", moRowId);
  await finaliseLog(sb, logId, "mo_incremented", `sku=${sku} ${currentQty}→${newQty}`, moRowId);
  return {
    sku,
    action: "mo_incremented",
    mo_row_id: moRowId,
    katana_mo_id: katanaMoId,
    from: currentQty,
    to: newQty
  };
}
async function createBlockedMo(sb, logId, sku, packVid, quantity) {
  const { data: ins, error: insErr } = await sb.from("sweetpea_pending_mos").insert({
    sku,
    katana_variant_id: packVid,
    planned_quantity: quantity,
    status: "blocked_on_supply",
    flavour: "reservation"
  }).select("id").single();
  if (insErr) {
    if (insErr.code === "23505") {
      return {
        sku,
        action: "blocked_race",
        reason: "blocked_unique_fired"
      };
    }
    await logError(sb, {
      category: "pending_mo",
      subcategory: "blocked_insert_failed",
      severity: "warning",
      affectedSku: sku,
      detail: {
        sku,
        quantity,
        error: insErr.message
      }
    });
    return {
      sku,
      action: "mo_error",
      reason: "blocked_insert_failed",
      detail: insErr.message
    };
  }
  const moRowId = ins.id;
  await logError(sb, {
    category: "allocation",
    subcategory: "blocked_on_supply",
    severity: "info",
    affectedSku: sku,
    affectedMoId: moRowId,
    detail: {
      sku,
      quantity,
      note: "reservation blocked pending supply; reconciler will promote"
    }
  });
  return {
    sku,
    action: "blocked_on_supply_created",
    mo_row_id: moRowId,
    qty: quantity
  };
}
async function incrementExistingBlocked(sb, logId, sku, existing, addQty) {
  const moRowId = existing.id;
  const currentQty = existing.planned_quantity;
  const newQty = currentQty + addQty;
  await sb.from("sweetpea_pending_mos").update({
    planned_quantity: newQty,
    updated_at: new Date().toISOString()
  }).eq("id", moRowId);
  return {
    sku,
    action: "blocked_incremented",
    mo_row_id: moRowId,
    from: currentQty,
    to: newQty
  };
}
// ─── Cancel path ───────────────────────────────────────────
async function handleCancel(sb, orderId, orderNumber, sku, quantity) {
  const logRes = await writeLogRow(sb, orderId, orderNumber, sku, quantity, "cancel", "v3 cancel entry");
  if (logRes.kind === "duplicate") {
    return {
      sku,
      action: "duplicate_deduped"
    };
  }
  if (logRes.kind === "error") {
    return {
      sku,
      action: "log_error",
      detail: logRes.detail
    };
  }
  const logId = logRes.id;
  const { data: active } = await sb.from("sweetpea_pending_mos").select("*").eq("sku", sku).eq("flavour", "reservation").in("status", [
    "NOT_STARTED",
    "pending_katana_create"
  ]).maybeSingle();
  if (!active) {
    const { data: blocked } = await sb.from("sweetpea_pending_mos").select("*").eq("sku", sku).eq("flavour", "reservation").eq("status", "blocked_on_supply").maybeSingle();
    if (blocked) {
      const currentQty = blocked.planned_quantity;
      const newQty = currentQty - quantity;
      if (newQty <= 0) {
        await sb.from("sweetpea_pending_mos").delete().eq("id", blocked.id);
        await finaliseLog(sb, logId, "blocked_deleted", `cancelled ${quantity} of ${currentQty} blocked`, blocked.id);
        return {
          sku,
          action: "blocked_deleted",
          mo_row_id: blocked.id,
          from: currentQty,
          to: 0
        };
      }
      await sb.from("sweetpea_pending_mos").update({
        planned_quantity: newQty
      }).eq("id", blocked.id);
      await finaliseLog(sb, logId, "blocked_decremented", `${currentQty}→${newQty}`, blocked.id);
      return {
        sku,
        action: "blocked_decremented",
        mo_row_id: blocked.id,
        from: currentQty,
        to: newQty
      };
    }
    await finaliseLog(sb, logId, "cancel_no_mo", `no open MO to decrement for ${sku}`);
    return {
      sku,
      action: "cancel_no_mo"
    };
  }
  const moRowId = active.id;
  const katanaMoId = active.katana_mo_id;
  const currentQty = active.planned_quantity;
  if (quantity > currentQty) {
    await logError(sb, {
      category: "cancel",
      subcategory: "qty_exceeds_current",
      severity: "warning",
      affectedSku: sku,
      affectedMoId: moRowId,
      detail: {
        sku,
        cancelled_qty: quantity,
        current_qty: currentQty
      }
    });
    await finaliseLog(sb, logId, "cancel_error", `cancel qty ${quantity} > current ${currentQty}`, moRowId);
    return {
      sku,
      action: "cancel_error",
      reason: "qty_exceeds_current"
    };
  }
  const newQty = currentQty - quantity;
  if (newQty === 0) {
    if (katanaMoId && !DRY_RUN) {
      const del = await katanaCall(`/manufacturing_orders/${katanaMoId}`, "DELETE");
      if (del.status !== 200 && del.status !== 204) {
        await logError(sb, {
          category: "katana",
          subcategory: "delete_failed",
          severity: "critical",
          affectedSku: sku,
          affectedMoId: moRowId,
          detail: {
            katana_mo_id: katanaMoId,
            status: del.status,
            body: (del.rawText ?? "").slice(0, 300)
          }
        });
        await finaliseLog(sb, logId, "cancel_error", `Katana DELETE failed status=${del.status}`, moRowId);
        return {
          sku,
          action: "cancel_error",
          reason: "katana_delete_failed"
        };
      }
    }
    await sb.from("sweetpea_mo_recipes").delete().eq("mo_id", moRowId);
    await sb.from("sweetpea_pending_mos").delete().eq("id", moRowId);
    await finaliseLog(sb, logId, "mo_deleted", `sku=${sku} cancelled ${quantity} of ${currentQty}`, moRowId);
    return {
      sku,
      action: "mo_deleted",
      mo_row_id: moRowId,
      from: currentQty,
      to: 0
    };
  }
  if (katanaMoId && !DRY_RUN) {
    const patch = await katanaCall(`/manufacturing_orders/${katanaMoId}`, "PATCH", {
      planned_quantity: newQty
    });
    if (patch.status !== 200) {
      await logError(sb, {
        category: "katana",
        subcategory: "patch_drift",
        severity: "warning",
        affectedSku: sku,
        affectedMoId: moRowId,
        detail: {
          katana_mo_id: katanaMoId,
          attempted_qty: newQty,
          status: patch.status
        }
      });
      await finaliseLog(sb, logId, "cancel_error", `Katana PATCH failed status=${patch.status}`, moRowId);
      return {
        sku,
        action: "cancel_error",
        reason: "katana_patch_failed"
      };
    }
  }
  await sb.from("sweetpea_pending_mos").update({
    planned_quantity: newQty,
    updated_at: new Date().toISOString()
  }).eq("id", moRowId);
  await finaliseLog(sb, logId, "mo_decremented", `sku=${sku} ${currentQty}→${newQty}`, moRowId);
  return {
    sku,
    action: "mo_decremented",
    mo_row_id: moRowId,
    from: currentQty,
    to: newQty
  };
}
