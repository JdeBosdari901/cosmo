import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
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
  if (!resp.ok) throw new Error(`Shopify token failed (${resp.status}): ${await resp.text()}`);
  return (await resp.json()).access_token;
}
async function shopifyGraphQL(token, query, variables) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query,
      ...variables ? {
        variables
      } : {}
    })
  });
  if (!resp.ok) throw new Error(`Shopify GraphQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
/**
 * v3: Syncs katana_stock_sync when Shopify already has the correct policy.
 * Fixes the "perpetual mismatch" bug where fix-batch-deny found already_correct
 * but never updated the stale katana_stock_sync record, so the mismatch
 * reappeared every cycle.
 */ Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  const { skus, target_policy, reason: batchReason } = await req.json();
  if (!Array.isArray(skus) || skus.length === 0) {
    return new Response(JSON.stringify({
      error: "skus array required"
    }), {
      status: 400
    });
  }
  const policy = target_policy === "CONTINUE" ? "CONTINUE" : "DENY";
  const auditReason = batchReason || `batch fix to ${policy}`;
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const results = [];
  try {
    const shopifyToken = await getShopifyToken();
    for (const sku of skus){
      try {
        const safeSku = sku.replace(/'/g, "\\'");
        const lookupResult = await shopifyGraphQL(shopifyToken, `
          { productVariants(first: 1, query: "sku:'${safeSku}'") {
              nodes { id sku inventoryPolicy product { id } }
          } }
        `);
        const variant = lookupResult?.data?.productVariants?.nodes?.[0];
        if (!variant) {
          results.push({
            sku,
            status: "not_found"
          });
          continue;
        }
        if (variant.inventoryPolicy === policy) {
          // Shopify already correct — sync katana_stock_sync to match
          await supabase.from("katana_stock_sync").update({
            shopify_inventory_policy: policy,
            notes: `Synced: Shopify already ${policy} | ${auditReason}`
          }).eq("sku", sku);
          results.push({
            sku,
            status: "already_correct"
          });
          continue;
        }
        const previousPolicy = variant.inventoryPolicy;
        const updateResult = await shopifyGraphQL(shopifyToken, `mutation U($pid:ID!,$vid:ID!,$pol:ProductVariantInventoryPolicy!) {
            productVariantsBulkUpdate(productId:$pid, variants:[{id:$vid, inventoryPolicy:$pol}]) {
              productVariants { id inventoryPolicy }
              userErrors { field message }
            }
          }`, {
          pid: variant.product.id,
          vid: variant.id,
          pol: policy
        });
        const userErrors = updateResult?.data?.productVariantsBulkUpdate?.userErrors ?? [];
        if (userErrors.length > 0) {
          results.push({
            sku,
            status: "shopify_error",
            detail: JSON.stringify(userErrors)
          });
          continue;
        }
        const now = new Date().toISOString();
        // Get current stock data for audit
        const { data: syncRow } = await supabase.from("katana_stock_sync").select("katana_variant_id, quantity_in_stock, quantity_expected, effective_stock").eq("sku", sku).maybeSingle();
        // Update katana_stock_sync
        await supabase.from("katana_stock_sync").update({
          shopify_inventory_policy: policy,
          last_changed_at: now,
          notes: `Batch fix ${previousPolicy} \u2192 ${policy} | ${auditReason}`
        }).eq("sku", sku);
        // Audit trail
        await supabase.from("inventory_policy_audit").insert({
          sku,
          katana_variant_id: syncRow?.katana_variant_id ?? null,
          previous_policy: previousPolicy,
          new_policy: policy,
          reason: auditReason,
          source: "fix-batch-deny",
          quantity_in_stock: syncRow?.quantity_in_stock ?? null,
          quantity_expected: syncRow?.quantity_expected ?? null,
          effective_stock: syncRow?.effective_stock ?? null
        });
        results.push({
          sku,
          status: "changed",
          detail: `${previousPolicy} \u2192 ${policy}`
        });
        console.log(`\u2713 ${sku}: ${previousPolicy} \u2192 ${policy}`);
      } catch (err) {
        results.push({
          sku,
          status: "error",
          detail: err instanceof Error ? err.message : String(err)
        });
      }
    }
    const changed = results.filter((r)=>r.status === "changed").length;
    const already = results.filter((r)=>r.status === "already_correct").length;
    const errors = results.filter((r)=>r.status === "error" || r.status === "shopify_error").length;
    return new Response(JSON.stringify({
      status: "ok",
      changed,
      already_correct: already,
      errors,
      results
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err instanceof Error ? err.message : String(err)
    }), {
      status: 500
    });
  }
});
