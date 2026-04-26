import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * sweetpea-watchdog v3 — silent-failure alert pass
 *
 * v3 adds three Phase 5 passes:
 *   F. cancel_error rows unalerted (cancel webhook hit a failure path)
 *   G. cancel_mo_locked rows unalerted (cancel on in-progress or done MO — manual review)
 *   H. DENY_RESTORE_FAILED sentinel on success rows unalerted (golden rule:
 *      a cancel freed headroom but we couldn't restore CONTINUE, so the SKU
 *      is silently sitting off-shelf when it shouldn't be)
 *
 * Does not mutate Katana or Shopify. Returns messages[] for the scheduling
 * n8n workflow to post to #system-alarm (C0ANM4LHYKH).
 *
 * Full alert pass list:
 *   A. mo_error rows (Phase 2/3)
 *   B. Stuck processing rows (>5 min old)
 *   C. Webhook silence (zero rows in last 24h)
 *   D. cg_sold_out rows (Phase 4)
 *   E. cg_mo_error rows (Phase 4)
 *   F. cancel_error rows (Phase 5)
 *   G. cancel_mo_locked rows (Phase 5)
 *   H. DENY_RESTORE_FAILED rows (Phase 5 — golden rule)
 *
 * Ceiling 50 rows/pass prevents alert storms during systemic failure.
 */ const SYSTEM_ALARM_CHANNEL = "C0ANM4LHYKH";
const STUCK_THRESHOLD_MINUTES = 5;
const SILENCE_THRESHOLD_HOURS = 24;
const ALERT_CEILING = 50;
Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const messages = [];
  const errors = [];
  const stats = {
    mo_errors_alerted: 0,
    stuck_processing_alerted: 0,
    silence_alert: false,
    rows_in_window: 0,
    cg_sold_out_alerted: 0,
    cg_mo_errors_alerted: 0,
    cancel_errors_alerted: 0,
    cancel_mo_locked_alerted: 0,
    deny_restore_failed_alerted: 0
  };
  // ── Pass A: mo_error (Phase 2/3) ───────────────────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, processed_at").eq("action", "mo_error").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83D\uDEA8 *Sweet pea \u2014 MO errors* (${rows.length})\n`;
      text += `_Webhook reached a failure path; no MO was opened. Manual investigation needed._\n\n`;
      for (const r of rows){
        const sku = r.sku ?? "(no sku)";
        const qty = r.quantity ?? "?";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} \u2014 \`${sku}\` qty=${qty}\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`mo_error alerted_at update failed: ${updErr.message}`);
      else stats.mo_errors_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`mo_error pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass B: stuck processing rows ──────────────────────────
  try {
    const threshold = new Date(Date.now() - STUCK_THRESHOLD_MINUTES * 60_000).toISOString();
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, processed_at").eq("action", "processing").is("alerted_at", null).lt("processed_at", threshold).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\u26A0\uFE0F *Sweet pea \u2014 stuck processing rows* (${rows.length})\n`;
      text += `_Webhook started but never finalised (>${STUCK_THRESHOLD_MINUTES} min). Likely runtime crash mid-function. Check Supabase EF logs for sweetpea-order-mo._\n\n`;
      for (const r of rows){
        const sku = r.sku ?? "(no sku)";
        const qty = r.quantity ?? "?";
        text += `\u2022 order #${r.shopify_order_number ?? "?"} \u2014 \`${sku}\` qty=${qty} started ${r.processed_at}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`stuck processing alerted_at update failed: ${updErr.message}`);
      else stats.stuck_processing_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`stuck processing pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass C: webhook silence ───────────────────────────────
  try {
    const threshold = new Date(Date.now() - SILENCE_THRESHOLD_HOURS * 3_600_000).toISOString();
    const { count, error } = await supabase.from("sweetpea_webhook_log").select("id", {
      count: "exact",
      head: true
    }).gte("processed_at", threshold);
    if (error) throw error;
    stats.rows_in_window = count ?? 0;
    if ((count ?? 0) === 0) {
      const text = `\uD83D\uDD15 *Sweet pea webhook silence* \u2014 no rows in sweetpea_webhook_log for ${SILENCE_THRESHOLD_HOURS}h.\n` + `_Every Shopify order writes at least a stub row to this table, so silence means webhook plumbing is broken._\n` + `Check: (1) Shopify webhook subscriptions, (2) n8n receiver workflow active, (3) sweetpea-order-mo deployment status.`;
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      stats.silence_alert = true;
    }
  } catch (e) {
    errors.push(`silence check: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass D: cg_sold_out (Phase 4) ──────────────────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, processed_at").eq("action", "cg_sold_out").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83C\uDF3A *Cottage Garden Mix \u2014 sold out* (${rows.length})\n`;
      text += `_Picker couldn't assemble 8 varieties meeting the colour-spread rule. Collection set to DENY; held orders await component recovery._\n\n`;
      for (const r of rows){
        const qty = r.quantity ?? "?";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} qty=${qty}\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`cg_sold_out alerted_at update failed: ${updErr.message}`);
      else stats.cg_sold_out_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`cg_sold_out pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass E: cg_mo_error (Phase 4) ──────────────────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, mo_id, processed_at").eq("action", "cg_mo_error").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83D\uDEA8 *Cottage Garden Mix \u2014 MO errors* (${rows.length})\n`;
      text += `_Phase 4 handler failed at MO creation or recipe reconciliation. Orphan MOs possible; check Katana and Supabase EF logs._\n\n`;
      for (const r of rows){
        const qty = r.quantity ?? "?";
        const mo = r.mo_id ? ` MO=${r.mo_id}` : "";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} qty=${qty}${mo}\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`cg_mo_error alerted_at update failed: ${updErr.message}`);
      else stats.cg_mo_errors_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`cg_mo_error pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass F: cancel_error (Phase 5) ─────────────────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, mo_id, processed_at").eq("action", "cancel_error").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83D\uDEA8 *Sweet pea \u2014 cancellation errors* (${rows.length})\n`;
      text += `_Cancel webhook hit a failure path. MO state may be inconsistent with sweetpea_pending_mos \u2014 investigate before go-live._\n\n`;
      for (const r of rows){
        const sku = r.sku ?? "(no sku)";
        const qty = r.quantity ?? "?";
        const mo = r.mo_id ? ` MO=${r.mo_id}` : "";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} \u2014 \`${sku}\` qty=${qty}${mo}\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`cancel_error alerted_at update failed: ${updErr.message}`);
      else stats.cancel_errors_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`cancel_error pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass G: cancel_mo_locked (Phase 5) ───────────────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, mo_id, processed_at").eq("action", "cancel_mo_locked").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83D\uDD12 *Sweet pea \u2014 cancel on locked MO* (${rows.length})\n`;
      text += `_Customer cancelled but MO has moved beyond NOT_STARTED (components allocated or produced). We can't reverse it automatically \u2014 decide manually whether to keep, rework, or scrap._\n\n`;
      for (const r of rows){
        const sku = r.sku ?? "(no sku)";
        const qty = r.quantity ?? "?";
        const mo = r.mo_id ? ` MO=${r.mo_id}` : "";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} \u2014 \`${sku}\` qty=${qty}${mo}\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`cancel_mo_locked alerted_at update failed: ${updErr.message}`);
      else stats.cancel_mo_locked_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`cancel_mo_locked pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  // ── Pass H: DENY_RESTORE_FAILED (Phase 5 — golden rule) ────────────
  try {
    const { data: rows, error } = await supabase.from("sweetpea_webhook_log").select("id, shopify_order_number, sku, quantity, notes, mo_id, action, processed_at").in("action", [
      "mo_decremented",
      "mo_deleted",
      "cg_mo_decremented",
      "cg_mo_deleted"
    ]).ilike("notes", "%DENY_RESTORE_FAILED%").is("alerted_at", null).order("processed_at", {
      ascending: true
    }).limit(ALERT_CEILING);
    if (error) throw error;
    if (rows && rows.length > 0) {
      let text = `\uD83D\uDD13 *Sweet pea \u2014 DENY restore failed* (${rows.length})\n`;
      text += `_Cancel freed headroom on a DENY'd SKU, but the auto-restore to CONTINUE didn't stick. Golden rule: get these back on the shelf. Clear manual_override=NULL manually and push CONTINUE via fix-batch-deny._\n\n`;
      for (const r of rows){
        const sku = r.sku ?? "(no sku)";
        const qty = r.quantity ?? "?";
        const mo = r.mo_id ? ` MO=${r.mo_id}` : "";
        const notes = (r.notes ?? "(no details)").toString().slice(0, 300);
        text += `\u2022 order #${r.shopify_order_number ?? "?"} \u2014 \`${sku}\` qty=${qty}${mo} (action=${r.action})\n`;
        text += `  ${notes}\n`;
      }
      messages.push({
        channel: SYSTEM_ALARM_CHANNEL,
        text
      });
      const ids = rows.map((r)=>r.id);
      const { error: updErr } = await supabase.from("sweetpea_webhook_log").update({
        alerted_at: new Date().toISOString()
      }).in("id", ids);
      if (updErr) errors.push(`DENY_RESTORE_FAILED alerted_at update failed: ${updErr.message}`);
      else stats.deny_restore_failed_alerted = rows.length;
    }
  } catch (e) {
    errors.push(`DENY_RESTORE_FAILED pass: ${e instanceof Error ? e.message : String(e)}`);
  }
  return new Response(JSON.stringify({
    status: errors.length === 0 ? "complete" : "complete_with_errors",
    stats,
    messages,
    errors
  }), {
    headers: {
      "Content-Type": "application/json"
    }
  });
});
