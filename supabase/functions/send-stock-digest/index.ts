import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * send-stock-digest v1
 *
 * Runs at 08:00 Europe/London (scheduled via n8n).
 * Queries katana_stock_sync and product_bom for exceptions.
 * Posts to Slack only if exceptions exist — no news is good news.
 *
 * Three exception categories:
 *
 * 1. OVERSELLING RISK
 *    CONTINUE policy + negative effective_stock + quantity_expected = 0
 *    Nothing credible backing the continued selling. Needs immediate attention.
 *
 * 2. FAILED CORRECTIONS
 *    Rows where notes contain 'error' or 'not found in Shopify', updated
 *    in the last 24 hours. System tried and failed — needs investigation.
 *
 * 3. BOM-BLOCKED
 *    Assembled products (bundles) where a component SKU is DENY in
 *    katana_stock_sync. The assembled product cannot be fulfilled even
 *    if the parent SKU shows CONTINUE.
 */ const SLACK_WEBHOOK_SECRET = "SLACK_WEBHOOK_URL_STOCK_DIGEST";
function fmt(rows) {
  return rows.map((r)=>`  • ${r}`).join("\n");
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
      }
    });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  const slackWebhookUrl = Deno.env.get(SLACK_WEBHOOK_SECRET);
  if (!slackWebhookUrl) {
    return new Response(JSON.stringify({
      error: `${SLACK_WEBHOOK_SECRET} not configured`
    }), {
      status: 500
    });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const sections = [];
  const today = new Date().toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "Europe/London"
  });
  // ── 1. OVERSELLING RISK ───────────────────────────────────────────────────
  // CONTINUE + effective_stock < 0 + quantity_expected = 0
  const { data: overselling } = await supabase.from("katana_stock_sync").select("sku, effective_stock, quantity_in_stock, quantity_expected").eq("shopify_inventory_policy", "CONTINUE").lt("effective_stock", 0).eq("quantity_expected", 0).order("effective_stock", {
    ascending: true
  });
  if (overselling && overselling.length > 0) {
    const lines = overselling.map((r)=>`${r.sku} — effective: ${Math.round(r.effective_stock)} (in stock: ${Math.round(r.quantity_in_stock)}, expected: ${Math.round(r.quantity_expected)})`);
    sections.push(`*:rotating_light: OVERSELLING RISK — ${overselling.length} variant${overselling.length > 1 ? "s" : ""}*\n` + `CONTINUE policy set but no PO exists to justify it. Orders are being taken with no credible fulfilment basis.\n` + fmt(lines));
  }
  // ── 2. FAILED CORRECTIONS ────────────────────────────────────────────────
  // Notes indicate a system error or SKU not found in Shopify, updated in last 25 hours
  const cutoff = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
  const { data: failed } = await supabase.from("katana_stock_sync").select("sku, notes, last_checked_at").or("notes.ilike.%not found in Shopify%,notes.ilike.%error%,notes.ilike.%failed%").gte("last_checked_at", cutoff).order("last_checked_at", {
    ascending: false
  });
  if (failed && failed.length > 0) {
    const lines = failed.map((r)=>`${r.sku} — ${r.notes ?? "unknown error"}`);
    sections.push(`*:warning: FAILED CORRECTIONS — ${failed.length} variant${failed.length > 1 ? "s" : ""}*\n` + `System attempted a policy change in the last 24 hours but could not complete it.\n` + fmt(lines));
  }
  // ── 3. BOM-BLOCKED ───────────────────────────────────────────────────────
  // Assembled products where at least one component is DENY in katana_stock_sync
  const { data: bomBlocked } = await supabase.rpc("get_bom_blocked_products");
  // Falls back gracefully if the function doesn't exist yet
  if (bomBlocked && bomBlocked.length > 0) {
    const lines = bomBlocked.map((r)=>`${r.parent_sku} — blocked by ${r.blocked_component} (stock: ${Math.round(r.component_stock)})`);
    sections.push(`*:package: BOM-BLOCKED — ${bomBlocked.length} assembled product${bomBlocked.length > 1 ? "s" : ""}*\n` + `Component out of stock. Cannot fulfil the assembled product — human decision required.\n` + fmt(lines));
  }
  // ── Send or stay silent ──────────────────────────────────────────────────
  if (sections.length === 0) {
    console.log("No exceptions found — digest suppressed.");
    return new Response(JSON.stringify({
      status: "ok",
      message: "No exceptions — digest suppressed"
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const message = [
    `*Ashridge Stock Digest — ${today}*`,
    ...sections,
    `_${sections.length} exception categor${sections.length > 1 ? "ies" : "y"} require attention._`
  ].join("\n\n");
  const slackResp = await fetch(slackWebhookUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      text: message
    })
  });
  if (!slackResp.ok) {
    const errText = await slackResp.text();
    console.error("Slack post failed:", errText);
    return new Response(JSON.stringify({
      error: "Slack post failed",
      detail: errText
    }), {
      status: 500
    });
  }
  console.log(`Digest sent — ${sections.length} exception categories.`);
  return new Response(JSON.stringify({
    status: "sent",
    exception_categories: sections.length,
    overselling: overselling?.length ?? 0,
    failed_corrections: failed?.length ?? 0,
    bom_blocked: bomBlocked?.length ?? 0
  }), {
    headers: {
      "Content-Type": "application/json"
    }
  });
});
