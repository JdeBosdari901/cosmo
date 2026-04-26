import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const VERIFY_PRODUCT_URL = "https://cuposlohqvhikyulhrsx.supabase.co/functions/v1/verify-product";
const TODO_CHANNEL = "C0AQHBN15SS"; // #jdeb-todo-list
async function getShopifyToken() {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: clientSecret
    }).toString()
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  return (await resp.json()).access_token;
}
async function shopifyGraphQL(token, query) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query
    })
  });
  if (!resp.ok) throw new Error(`Shopify GraphQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
/**
 * verify-product-sweep v1 — daily drift check
 *
 * Queries Shopify for all products created in the last N hours, runs
 * verify-product on each, and returns Slack messages[] for any ACTIVE
 * product with overall_status = "issues_found".
 *
 * DRAFT products are NOT alerted on — they're expected to have issues
 * (image, weight, etc.) while in the creation pipeline.
 *
 * Called by an n8n workflow on a daily schedule. Does not post to Slack
 * directly; returns messages[] for the n8n Slack node to post to
 * #jdeb-todo-list (C0AQHBN15SS).
 *
 * Input:   { window_hours?: number }  (default 36)
 * Output:  { status, stats, messages: [{channel, text}], errors }
 *
 * The 36-hour default gives 12h of buffer around the daily schedule,
 * so a product created just before one sweep cycle still gets checked
 * by the next cycle if it wasn't picked up immediately.
 */ Deno.serve(async (req)=>{
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
  const body = await req.json().catch(()=>({}));
  const window_hours = typeof body.window_hours === "number" && body.window_hours > 0 ? body.window_hours : 36;
  const messages = [];
  const errors = [];
  const stats = {
    window_hours,
    products_in_window: 0,
    active_checked: 0,
    draft_skipped: 0,
    other_skipped: 0,
    issues_found: 0,
    verify_errors: 0,
    not_found: 0
  };
  try {
    const cutoffISO = new Date(Date.now() - window_hours * 3_600_000).toISOString();
    // Format as YYYY-MM-DDTHH:MM:SSZ for Shopify search
    const cutoff = cutoffISO.replace(/\.\d{3}Z$/, "Z");
    const token = await getShopifyToken();
    // Fetch all products created in the window. Pagination allowed up to 250 —
    // extreme batch days (>250 products) would need pagination; we warn if hit.
    const query = `{
      products(first: 250, query: "created_at:>=${cutoff}") {
        pageInfo { hasNextPage }
        edges {
          node { id handle status createdAt }
        }
      }
    }`;
    const lookup = await shopifyGraphQL(token, query);
    if (lookup.errors) {
      errors.push(`Shopify top-level errors: ${JSON.stringify(lookup.errors)}`);
      return new Response(JSON.stringify({
        status: "error",
        stats,
        messages,
        errors
      }), {
        status: 502,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const productEdges = lookup?.data?.products?.edges ?? [];
    const hasNextPage = lookup?.data?.products?.pageInfo?.hasNextPage ?? false;
    stats.products_in_window = productEdges.length;
    if (hasNextPage) {
      errors.push(`Window contains >250 products; only the first page was checked. Consider a shorter window or add pagination.`);
    }
    const issueRows = [];
    for (const e of productEdges){
      const node = e.node;
      if (node.status === "DRAFT") {
        stats.draft_skipped++;
        continue;
      }
      if (node.status !== "ACTIVE") {
        // ARCHIVED — skip; archived products are hidden
        stats.other_skipped++;
        continue;
      }
      stats.active_checked++;
      try {
        const verifyResp = await fetch(VERIFY_PRODUCT_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            handle: node.handle
          })
        });
        if (!verifyResp.ok) {
          stats.verify_errors++;
          errors.push(`verify-product returned ${verifyResp.status} for handle=${node.handle}`);
          continue;
        }
        const v = await verifyResp.json();
        if (v.overall_status === "not_found") {
          stats.not_found++;
          errors.push(`verify-product reported not_found for handle=${node.handle}`);
          continue;
        }
        if (v.overall_status === "issues_found") {
          stats.issues_found++;
          const numericId = (v.shopify?.gid ?? "").replace("gid://shopify/Product/", "");
          issueRows.push({
            handle: v.handle ?? node.handle,
            title: v.title ?? "(no title)",
            status: v.shopify?.status ?? node.status,
            is_active: !!v.shopify?.is_active,
            admin_url: `https://admin.shopify.com/store/${SHOPIFY_SHOP}/products/${numericId}`,
            live_url: v.shopify?.online_store_url ?? null,
            issues: Array.isArray(v.issues) ? v.issues : []
          });
        }
        // Small spacing to avoid hammering Katana inside verify-product
        await new Promise((r)=>setTimeout(r, 200));
      } catch (e2) {
        stats.verify_errors++;
        const msg = e2 instanceof Error ? e2.message : String(e2);
        errors.push(`verify-product call failed for handle=${node.handle}: ${msg}`);
      }
    }
    if (issueRows.length > 0) {
      let text = `\uD83D\uDD0D *Product verify sweep \u2014 ${issueRows.length} ACTIVE product${issueRows.length === 1 ? "" : "s"} with issues*\n`;
      text += `_Window: last ${window_hours}h. ACTIVE products that have gone live with one or more verification issues. DRAFT products are excluded (still in creation pipeline)._\n\n`;
      for (const r of issueRows){
        text += `\u2022 *${r.title}* (\`${r.handle}\`)\n`;
        for (const issue of r.issues){
          text += `    \u25AB\uFE0F ${issue}\n`;
        }
        text += `    Admin: ${r.admin_url}\n`;
        if (r.live_url) {
          text += `    Live: ${r.live_url}\n`;
        }
      }
      text += `\nFix by: (a) populating the missing fields in Shopify admin, or (b) for silent-tracking failures, calling \`update-variants\` v3 with \`enable_tracking\`.`;
      messages.push({
        channel: TODO_CHANNEL,
        text
      });
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(`sweep top-level failure: ${msg}`);
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
