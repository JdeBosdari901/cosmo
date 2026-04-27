import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * sync-bom-active-status v2
 *
 * Daily sync: checks Shopify product status for every variant_sku in product_bom.
 * Sets active_on_site = false when the Shopify product is DRAFT or ARCHIVED.
 * Sets active_on_site = true when the Shopify product is ACTIVE.
 *
 * Called by n8n on a daily schedule.
 *
 * v2 (27 April 2026): added report_workflow_health() RPC calls on success and error
 * paths so the EF Watchdog Pattern 3 dead-man's switch can detect missed runs.
 * Per-SKU errors collected in the local errors array do not trigger workflow-level
 * error reporting — only catastrophic failures (caught in the top-level try/catch)
 * report status='error' to workflow_health.
 */

const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const WORKFLOW_ID = "sync-bom-active-status";

async function getShopifyToken(): Promise<string> {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: clientSecret,
    }).toString(),
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  const data = await resp.json();
  return data.access_token;
}

async function shopifyGraphQL(token: string, query: string, variables?: Record<string, unknown>) {
  const body: Record<string, unknown> = { query };
  if (variables) body.variables = variables;
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": token },
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`Shopify GraphQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST required" }), { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const log: string[] = [];
  const errors: string[] = [];

  try {
    // 1. Get all distinct variant_skus from product_bom
    const { data: bomSkus, error: bomErr } = await supabase
      .from('product_bom')
      .select('variant_sku')
      .order('variant_sku');
    if (bomErr) throw new Error(`Failed to read product_bom: ${bomErr.message}`);

    const uniqueSkus = [...new Set((bomSkus ?? []).map((r: { variant_sku: string }) => r.variant_sku))];
    log.push(`Distinct variant_skus in product_bom: ${uniqueSkus.length}`);

    // 2. Get Shopify token
    const token = await getShopifyToken();
    log.push('Shopify token acquired');

    // 3. Look up each SKU in Shopify, cache product status by GID
    const productStatusCache: Record<string, string> = {}; // productGid -> status
    const skuToProductGid: Record<string, string> = {};
    const skuNotFound: string[] = [];

    for (const sku of uniqueSkus) {
      try {
        const result = await shopifyGraphQL(token, `{
          productVariants(first: 1, query: "sku:'${sku.replace(/'/g, "\\'")}") {
            edges {
              node {
                id
                product {
                  id
                  status
                }
              }
            }
          }
        }`);

        const variant = result?.data?.productVariants?.edges?.[0]?.node;
        if (!variant) {
          skuNotFound.push(sku);
          continue;
        }

        const productGid = variant.product.id;
        const status = variant.product.status; // ACTIVE, DRAFT, or ARCHIVED
        productStatusCache[productGid] = status;
        skuToProductGid[sku] = productGid;
      } catch (e: unknown) {
        errors.push(`SKU ${sku}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }

    log.push(`Shopify lookups complete: ${Object.keys(skuToProductGid).length} found, ${skuNotFound.length} not found`);
    if (skuNotFound.length > 0) {
      log.push(`Not found in Shopify: ${skuNotFound.join(', ')}`);
    }

    // 4. Determine active_on_site for each SKU
    //    ACTIVE = true, DRAFT/ARCHIVED/not-found = false
    const setTrue: string[] = [];
    const setFalse: string[] = [];

    for (const sku of uniqueSkus) {
      const productGid = skuToProductGid[sku];
      if (!productGid) {
        // Not found in Shopify at all
        setFalse.push(sku);
        continue;
      }
      const status = productStatusCache[productGid];
      if (status === 'ACTIVE') {
        setTrue.push(sku);
      } else {
        setFalse.push(sku);
      }
    }

    log.push(`Active: ${setTrue.length}, Inactive: ${setFalse.length}`);

    // 5. Update product_bom
    let updatedTrue = 0;
    let updatedFalse = 0;

    if (setTrue.length > 0) {
      const { error: errT } = await supabase
        .from('product_bom')
        .update({ active_on_site: true })
        .in('variant_sku', setTrue)
        .eq('active_on_site', false); // Only update rows that changed
      if (errT) errors.push(`Update active=true: ${errT.message}`);
      else updatedTrue = setTrue.length;
    }

    if (setFalse.length > 0) {
      const { error: errF } = await supabase
        .from('product_bom')
        .update({ active_on_site: false })
        .in('variant_sku', setFalse)
        .eq('active_on_site', true); // Only update rows that changed
      if (errF) errors.push(`Update active=false: ${errF.message}`);
      else updatedFalse = setFalse.length;
    }

    log.push(`Updates applied: ${updatedTrue} set true, ${updatedFalse} set false`);

    // 6. Report workflow health (success path — per-SKU errors don't count)
    await supabase.rpc("report_workflow_health", {
      p_workflow_id: WORKFLOW_ID,
      p_status: "success",
    });

    const status = errors.length === 0 ? 'complete' : 'complete_with_errors';
    return new Response(
      JSON.stringify({ status, log, errors, summary: { total: uniqueSkus.length, active: setTrue.length, inactive: setFalse.length, not_found: skuNotFound.length } }),
      { headers: { 'Content-Type': 'application/json' } }
    );

  } catch (e: unknown) {
    // Catastrophic failure — report to workflow_health as error
    const msg = e instanceof Error ? e.message : String(e);
    try {
      await supabase.rpc("report_workflow_health", {
        p_workflow_id: WORKFLOW_ID,
        p_status: "error",
        p_error_message: msg,
      });
    } catch (_rpcErr) {
      // If the RPC itself fails, swallow — we're already in the error path
      // and don't want to mask the original failure.
    }
    return new Response(
      JSON.stringify({ status: 'failed', error: msg, log, errors }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
