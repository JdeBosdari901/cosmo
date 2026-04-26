import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * attribution-aggregate-hourly v1
 *
 * Runs hourly (pg_cron 0 5-22 * * * UTC). Reads Elevar BQ events_enriched
 * over a 14-day trailing window, joins with local Supabase shopify_orders,
 * upserts five mirror tables, reports to workflow_health.
 *
 * Requires: BIGQUERY_SERVICE_ACCOUNT_JSON EF secret (GCP service account with
 *           BigQuery Data Viewer + Job User on project sharp-imprint-433213-s9).
 * If secret absent on invocation: returns 503 so pg_cron can retry next hour.
 */ const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const BQ_PROJECT = "sharp-imprint-433213-s9";
const BQ_TABLE = "`sharp-imprint-433213-s9.elevar.events_enriched`";
const BQ_LOCATION = "EU";
const WORKFLOW_ID = "attribution-aggregate-hourly";
// ── Date range helpers ─────────────────────────────────────────────────────────────
function getDateRange() {
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth();
  const d = now.getUTCDate();
  const toD = new Date(Date.UTC(y, m, d - 1));
  const fromD = new Date(Date.UTC(y, m, d - 14));
  return {
    dateFrom: fromD.toISOString().slice(0, 10),
    dateTo: toD.toISOString().slice(0, 10)
  };
}
// ── Google service-account JWT + token exchange ──────────────────────────────
function b64url(data) {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let b64 = "";
  const CHUNK = 8192;
  for(let i = 0; i < bytes.length; i += CHUNK){
    b64 += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(b64).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}
async function getGCPToken(serviceAccountJson) {
  const sa = JSON.parse(serviceAccountJson);
  const now = Math.floor(Date.now() / 1000);
  const sigInput = b64url(JSON.stringify({
    alg: "RS256",
    typ: "JWT"
  })) + "." + b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/bigquery.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600
  }));
  // Strip PEM headers and decode to DER
  const pemBody = sa.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pemBody), (c)=>c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, {
    name: "RSASSA-PKCS1-v1_5",
    hash: "SHA-256"
  }, false, [
    "sign"
  ]);
  const sigBytes = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(sigInput));
  const jwt = `${sigInput}.${b64url(new Uint8Array(sigBytes))}`;
  const tokenResp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt
    }).toString()
  });
  if (!tokenResp.ok) {
    throw new Error(`GCP token exchange failed: ${await tokenResp.text()}`);
  }
  const { access_token } = await tokenResp.json();
  return access_token;
}
async function runBqQuery(token, sql) {
  const resp = await fetch(`https://bigquery.googleapis.com/bigquery/v2/projects/${BQ_PROJECT}/queries`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      query: sql,
      useLegacySql: false,
      timeoutMs: 30000,
      location: BQ_LOCATION
    })
  });
  if (!resp.ok) throw new Error(`BQ query failed: ${resp.status} ${await resp.text()}`);
  const result = await resp.json();
  if (!result.jobComplete) throw new Error("BQ job did not complete within 30-second timeout");
  const fields = result.schema?.fields ?? [];
  const rows = result.rows ?? [];
  return rows.map((row)=>{
    const obj = {};
    fields.forEach((field, i)=>{
      obj[field.name] = row.f[i]?.v ?? null;
    });
    return obj;
  });
}
// ── SQL query builders ─────────────────────────────────────────────────────────────
function buildQueries(dateFrom, dateTo) {
  const t = BQ_TABLE;
  const where = `WHERE DATE(publish_time) BETWEEN '${dateFrom}' AND '${dateTo}'`;
  const q1 = `SELECT DATE(publish_time) AS date,` + ` COUNTIF(event_name = 'dl_purchase') AS elevar_purchase_events,` + ` COALESCE(SUM(IF(event_name = 'dl_purchase', revenue, 0)), 0) AS elevar_purchase_revenue` + ` FROM ${t} ${where} GROUP BY date ORDER BY date`;
  const q2 = `SELECT DATE(publish_time) AS date, channel,` + ` CASE WHEN channel = 'AI Search' THEN COALESCE(ai_platform, '') ELSE '' END AS ai_platform,` + ` COUNTIF(event_name = 'dl_purchase') AS purchase_events,` + ` COALESCE(SUM(IF(event_name = 'dl_purchase', revenue, 0)), 0) AS purchase_revenue,` + ` COUNTIF(event_name = 'dl_view_item') AS view_item_events,` + ` COUNT(DISTINCT session_id) AS distinct_sessions` + ` FROM ${t} ${where} GROUP BY 1, 2, 3 ORDER BY date, channel`;
  const q3 = `WITH extracted AS (SELECT DATE(publish_time) AS date, ai_platform,` + ` REGEXP_EXTRACT(landing_url, r'^https?://[^/]+(/[^?#]*)') AS landing_page_path,` + ` session_id, event_name, revenue FROM ${t}` + ` WHERE channel = 'AI Search' AND DATE(publish_time) BETWEEN '${dateFrom}' AND '${dateTo}')` + ` SELECT date, ai_platform, landing_page_path,` + ` COUNT(DISTINCT session_id) AS distinct_sessions,` + ` COUNTIF(event_name = 'dl_view_item') AS view_item_events,` + ` COUNTIF(event_name = 'dl_purchase') AS purchase_events,` + ` COALESCE(SUM(IF(event_name = 'dl_purchase', revenue, 0)), 0) AS purchase_revenue` + ` FROM extracted WHERE landing_page_path IS NOT NULL` + ` GROUP BY date, ai_platform, landing_page_path ORDER BY date DESC, distinct_sessions DESC`;
  const q4 = `SELECT DATE(publish_time) AS date,` + ` COUNT(DISTINCT IF(event_name = 'dl_view_item', session_id, NULL)) AS view_sessions,` + ` COUNT(DISTINCT IF(event_name = 'dl_add_to_cart', session_id, NULL)) AS cart_sessions,` + ` COUNT(DISTINCT IF(event_name = 'dl_begin_checkout', session_id, NULL)) AS checkout_sessions,` + ` COUNT(DISTINCT IF(event_name = 'dl_add_shipping_info', session_id, NULL)) AS shipping_sessions,` + ` COUNT(DISTINCT IF(event_name = 'dl_add_payment_info', session_id, NULL)) AS payment_sessions,` + ` COUNT(DISTINCT IF(event_name = 'dl_purchase', session_id, NULL)) AS completed_sessions` + ` FROM ${t} ${where} GROUP BY date ORDER BY date`;
  const q5 = `WITH session_rollup AS (` + `SELECT DATE(publish_time) AS date, session_id,` + ` MAX(IF(email IS NOT NULL, 1, 0)) AS has_email,` + ` MAX(IF(shopify_customer_id IS NOT NULL, 1, 0)) AS has_customer,` + ` MAX(IF(event_name = 'dl_purchase', 1, 0)) AS has_purchase` + ` FROM ${t} ${where} AND session_id IS NOT NULL GROUP BY date, session_id)` + ` SELECT date, COUNT(*) AS distinct_sessions,` + ` SUM(has_email) AS sessions_with_email,` + ` SUM(has_customer) AS sessions_with_shopify_customer,` + ` SUM(has_purchase) AS sessions_with_purchase,` + ` ROUND(SAFE_DIVIDE(SUM(has_email), COUNT(*)) * 100, 2) AS email_attach_rate_pct,` + ` ROUND(SAFE_DIVIDE(SUM(has_customer), COUNT(*)) * 100, 2) AS customer_match_rate_pct` + ` FROM session_rollup GROUP BY date ORDER BY date`;
  return {
    q1,
    q2,
    q3,
    q4,
    q5
  };
}
// ── Parse helpers ─────────────────────────────────────────────────────────────────
const pf = (v)=>parseFloat(String(v ?? 0)) || 0;
const pi = (v)=>parseInt(String(v ?? 0), 10) || 0;
const ps = (v, fallback = "")=>v ?? fallback;
// ── Main handler ─────────────────────────────────────────────────────────────────────
Deno.serve(async (_req)=>{
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const now = new Date().toISOString();
  const saJson = Deno.env.get("BIGQUERY_SERVICE_ACCOUNT_JSON");
  if (!saJson) {
    await supabase.rpc("report_workflow_health", {
      p_workflow_id: WORKFLOW_ID,
      p_status: "error",
      p_error_message: "BIGQUERY_SERVICE_ACCOUNT_JSON not configured"
    });
    return jsonResp({
      error: "BIGQUERY_SERVICE_ACCOUNT_JSON not configured — set this EF secret then re-invoke"
    }, 503);
  }
  try {
    // 1. GCP access token
    const token = await getGCPToken(saJson);
    // 2. Date range
    const { dateFrom, dateTo } = getDateRange();
    const queries = buildQueries(dateFrom, dateTo);
    // 3. Run all 5 BQ queries in sequence
    const [q1Rows, q2Rows, q3Rows, q4Rows, q5Rows] = await Promise.all([
      runBqQuery(token, queries.q1),
      runBqQuery(token, queries.q2),
      runBqQuery(token, queries.q3),
      runBqQuery(token, queries.q4),
      runBqQuery(token, queries.q5)
    ]);
    // 4. Shopify daily stats from local Supabase
    const { data: shopifyStats, error: shopifyErr } = await supabase.rpc("get_shopify_daily_stats", {
      p_date_from: dateFrom,
      p_date_to: dateTo
    });
    if (shopifyErr) throw new Error(`get_shopify_daily_stats failed: ${shopifyErr.message}`);
    // 5. Build upsert payloads
    const refreshed_at = now;
    // Q1 → attribution_daily_snapshot (merge elevar + shopify)
    const elevarMap = new Map(q1Rows.map((r)=>[
        r.date,
        r
      ]));
    const shopifyMap = new Map((shopifyStats ?? []).map((r)=>[
        r.date,
        r
      ]));
    const allDates = new Set([
      ...elevarMap.keys(),
      ...shopifyMap.keys()
    ]);
    const snapshotRows = Array.from(allDates).map((date)=>{
      const e = elevarMap.get(date) ?? {};
      const s = shopifyMap.get(date) ?? {};
      return {
        date,
        elevar_purchase_events: pi(e.elevar_purchase_events),
        elevar_purchase_revenue: pf(e.elevar_purchase_revenue),
        shopify_orders: s.shopify_orders != null ? pi(s.shopify_orders) : null,
        shopify_revenue: s.shopify_revenue != null ? pf(s.shopify_revenue) : null,
        ga4_transactions: null,
        ga4_revenue: null,
        refreshed_at
      };
    });
    // Q2 → attribution_channel_daily
    const channelRows = q2Rows.map((r)=>({
        date: ps(r.date),
        channel: ps(r.channel),
        ai_platform: ps(r.ai_platform, ""),
        purchase_events: pi(r.purchase_events),
        purchase_revenue: pf(r.purchase_revenue),
        view_item_events: pi(r.view_item_events),
        distinct_sessions: pi(r.distinct_sessions),
        refreshed_at
      }));
    // Q3 → ai_search_daily
    const aiSearchRows = q3Rows.map((r)=>({
        date: ps(r.date),
        ai_platform: ps(r.ai_platform),
        landing_page_path: ps(r.landing_page_path),
        distinct_sessions: pi(r.distinct_sessions),
        view_item_events: pi(r.view_item_events),
        purchase_events: pi(r.purchase_events),
        purchase_revenue: pf(r.purchase_revenue),
        refreshed_at
      }));
    // Q4 → checkout_funnel_daily
    const funnelRows = q4Rows.map((r)=>({
        date: ps(r.date),
        view_sessions: pi(r.view_sessions),
        cart_sessions: pi(r.cart_sessions),
        checkout_sessions: pi(r.checkout_sessions),
        shipping_sessions: pi(r.shipping_sessions),
        payment_sessions: pi(r.payment_sessions),
        completed_sessions: pi(r.completed_sessions),
        refreshed_at
      }));
    // Q5 → identity_graph_daily
    const identityRows = q5Rows.map((r)=>({
        date: ps(r.date),
        distinct_sessions: pi(r.distinct_sessions),
        sessions_with_email: pi(r.sessions_with_email),
        sessions_with_shopify_customer: pi(r.sessions_with_shopify_customer),
        sessions_with_purchase: pi(r.sessions_with_purchase),
        email_attach_rate_pct: pf(r.email_attach_rate_pct),
        customer_match_rate_pct: pf(r.customer_match_rate_pct),
        refreshed_at
      }));
    // 6. Upsert all five tables
    const upserts = await Promise.all([
      supabase.from("attribution_daily_snapshot").upsert(snapshotRows, {
        onConflict: "date"
      }),
      supabase.from("attribution_channel_daily").upsert(channelRows, {
        onConflict: "date,channel,ai_platform"
      }),
      supabase.from("ai_search_daily").upsert(aiSearchRows.length ? aiSearchRows : [], {
        onConflict: "date,ai_platform,landing_page_path"
      }),
      supabase.from("checkout_funnel_daily").upsert(funnelRows, {
        onConflict: "date"
      }),
      supabase.from("identity_graph_daily").upsert(identityRows, {
        onConflict: "date"
      })
    ]);
    const upsertErrors = upserts.map((u, i)=>u.error ? `table[${i}]: ${u.error.message}` : null).filter(Boolean);
    if (upsertErrors.length > 0) {
      throw new Error(`Upsert failures: ${upsertErrors.join(" | ")}`);
    }
    // 7. Report health
    await supabase.rpc("report_workflow_health", {
      p_workflow_id: WORKFLOW_ID,
      p_status: "success"
    });
    return jsonResp({
      status: "ok",
      date_from: dateFrom,
      date_to: dateTo,
      rows: {
        attribution_daily_snapshot: snapshotRows.length,
        attribution_channel_daily: channelRows.length,
        ai_search_daily: aiSearchRows.length,
        checkout_funnel_daily: funnelRows.length,
        identity_graph_daily: identityRows.length
      }
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await supabase.rpc("report_workflow_health", {
      p_workflow_id: WORKFLOW_ID,
      p_status: "error",
      p_error_message: msg
    });
    return jsonResp({
      error: msg
    }, 500);
  }
});
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json"
    }
  });
}
