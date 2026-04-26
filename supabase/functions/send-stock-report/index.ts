import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const DAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday"
];
function getLondonTime() {
  const now = new Date();
  const londonDate = new Date(now.toLocaleString("en-US", {
    timeZone: "Europe/London"
  }));
  return {
    dayOfWeek: londonDate.getDay(),
    hour: londonDate.getHours(),
    minute: londonDate.getMinutes()
  };
}
function formatTime(date) {
  return new Date(date).toLocaleString("en-GB", {
    timeZone: "Europe/London",
    hour: "2-digit",
    minute: "2-digit",
    day: "2-digit",
    month: "short"
  });
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
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const url = new URL(req.url);
  const force = url.searchParams.get("force") === "true";
  // -- 1. Check schedule ------------------------------------------------
  if (!force) {
    const london = getLondonTime();
    const { data: slots } = await supabase.from("alert_schedule").select("*").eq("alert_type", "stock_report").eq("day_of_week", london.dayOfWeek).eq("active", true);
    const matchingSlot = (slots ?? []).find((s)=>{
      const [h, m] = s.report_time.split(":").map(Number);
      const slotMinutes = h * 60 + m;
      const nowMinutes = london.hour * 60 + london.minute;
      return Math.abs(nowMinutes - slotMinutes) <= 30;
    });
    if (!matchingSlot) {
      return new Response(JSON.stringify({
        status: "not_scheduled",
        day: DAY_NAMES[london.dayOfWeek],
        time: `${String(london.hour).padStart(2, "0")}:${String(london.minute).padStart(2, "0")}`,
        message: "No active schedule slot matches the current time"
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
  }
  // -- 2. Query unreported stock changes via database view ---------------
  // Uses v_unreported_stock_changes view because PostgREST cannot do
  // column-to-column comparisons (slack_reported_at < last_changed_at).
  const { data: unreported, error: queryErr } = await supabase.from("v_unreported_stock_changes").select("sku, effective_stock, shopify_inventory_policy, last_changed_at, notes");
  if (queryErr) {
    console.error("Query error:", queryErr);
    return new Response(JSON.stringify({
      error: queryErr.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  if (!unreported || unreported.length === 0) {
    return new Response(JSON.stringify({
      status: "nothing_to_report",
      message: "No unreported stock changes"
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  // -- 3. Look up product names -----------------------------------------
  const skuPrefixes = [
    ...new Set(unreported.map((r)=>r.sku.split("-")[0]))
  ];
  const { data: products } = await supabase.from("katana_products").select("sku_prefix, katana_name").in("sku_prefix", skuPrefixes);
  const nameMap = new Map();
  (products ?? []).forEach((p)=>{
    nameMap.set(p.sku_prefix, p.katana_name);
  });
  // -- 4. Split into out-of-stock (DENY) and back-in-stock (CONTINUE) ---
  const outOfStock = unreported.filter((r)=>r.shopify_inventory_policy === "DENY");
  const backInStock = unreported.filter((r)=>r.shopify_inventory_policy === "CONTINUE");
  // -- 5. Format tabular Slack message ----------------------------------
  const reportTime = new Date().toLocaleString("en-GB", {
    timeZone: "Europe/London",
    weekday: "short",
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit"
  });
  let text = `:package: *Stock Report \u2014 ${reportTime}*\n`;
  if (outOfStock.length > 0) {
    text += `\n:no_entry: *${outOfStock.length} item${outOfStock.length > 1 ? "s" : ""} went out of stock:*\n\n`;
    text += "```\n";
    text += "Product                              SKU                   Effective   Changed\n";
    text += `${"\u2500".repeat(95)}\n`;
    for (const r of outOfStock){
      const prefix = r.sku.split("-")[0];
      const name = (nameMap.get(prefix) ?? r.sku).substring(0, 36).padEnd(36);
      const sku = r.sku.substring(0, 21).padEnd(21);
      const stock = String(r.effective_stock ?? 0).padEnd(11);
      const changed = formatTime(r.last_changed_at);
      text += `${name} ${sku} ${stock} ${changed}\n`;
    }
    text += "```\n";
    text += `All items above have been switched to \u201cno back orders\u201d automatically.\n`;
  }
  if (backInStock.length > 0) {
    text += `\n:white_check_mark: *${backInStock.length} item${backInStock.length > 1 ? "s" : ""} back in stock:*\n\n`;
    text += "```\n";
    text += "Product                              SKU                   Effective   Changed\n";
    text += `${"\u2500".repeat(95)}\n`;
    for (const r of backInStock){
      const prefix = r.sku.split("-")[0];
      const name = (nameMap.get(prefix) ?? r.sku).substring(0, 36).padEnd(36);
      const sku = r.sku.substring(0, 21).padEnd(21);
      const stock = String(r.effective_stock ?? 0).padEnd(11);
      const changed = formatTime(r.last_changed_at);
      text += `${name} ${sku} ${stock} ${changed}\n`;
    }
    text += "```\n";
    text += `Back orders re-enabled for items above.\n`;
  }
  // -- 6. Send Slack message --------------------------------------------
  const webhookUrl = Deno.env.get("SLACK_WEBHOOK_URL_JAIMIE");
  if (!webhookUrl) {
    console.error("SLACK_WEBHOOK_URL_JAIMIE not configured");
    return new Response(JSON.stringify({
      error: "SLACK_WEBHOOK_URL_JAIMIE not configured",
      would_have_sent: text
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const slackResp = await fetch(webhookUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      text
    })
  });
  if (!slackResp.ok) {
    const errText = await slackResp.text();
    console.error("Slack webhook failed:", slackResp.status, errText);
    return new Response(JSON.stringify({
      error: "Slack send failed",
      detail: errText
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  // -- 7. Timestamp reported rows ---------------------------------------
  const now = new Date().toISOString();
  const reportedSkus = unreported.map((r)=>r.sku);
  const { error: updateErr } = await supabase.from("katana_stock_sync").update({
    slack_reported_at: now
  }).in("sku", reportedSkus);
  if (updateErr) {
    console.error("Failed to timestamp reported rows:", updateErr);
  }
  console.log(`Stock report sent: ${outOfStock.length} out-of-stock, ${backInStock.length} back-in-stock`);
  return new Response(JSON.stringify({
    status: "report_sent",
    out_of_stock_count: outOfStock.length,
    back_in_stock_count: backInStock.length,
    skus_reported: reportedSkus
  }), {
    status: 200,
    headers: {
      "Content-Type": "application/json"
    }
  });
});
