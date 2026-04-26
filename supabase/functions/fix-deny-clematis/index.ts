import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GQL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
// 10 clematis variants incorrectly on DENY after PO publication
const TARGET_SKUS = {
  "CLEMARM-3L": {
    variant_id: 36922677,
    expected_stock: 36
  },
  "CLEMARMAPPBL-3L": {
    variant_id: 36922666,
    expected_stock: 18
  },
  "CLEMBEEJUB-3L": {
    variant_id: 36922719,
    expected_stock: 6
  },
  "CLEMCAREARSE-3L": {
    variant_id: 36923041,
    expected_stock: 6
  },
  "CLEMDOCRUP-3L": {
    variant_id: 36923014,
    expected_stock: 24
  },
  "CLEMMISBAT-3L": {
    variant_id: 36923757,
    expected_stock: 12
  },
  "CLEMMONVER-3L": {
    variant_id: 36924358,
    expected_stock: 6
  },
  "CLEMMULBLU-3L": {
    variant_id: 36922333,
    expected_stock: 12
  },
  "CLEMNUB-3L": {
    variant_id: 36923830,
    expected_stock: 6
  },
  "CLEMPAR-3L": {
    variant_id: 36923878,
    expected_stock: 6
  }
};
async function getShopifyToken() {
  const secret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!secret) throw new Error("SHOPIFY_CLIENT_KEY not set");
  const r = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: secret
    }).toString()
  });
  if (!r.ok) throw new Error(`Shopify token: ${r.status} ${await r.text()}`);
  return (await r.json()).access_token;
}
async function gql(token, query, variables) {
  const r = await fetch(SHOPIFY_GQL, {
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
  if (!r.ok) throw new Error(`Shopify GQL: ${r.status} ${await r.text()}`);
  return r.json();
}
Deno.serve(async (req)=>{
  if (req.method !== "POST") return new Response(JSON.stringify({
    error: "POST required"
  }), {
    status: 405
  });
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const results = {};
  let changed = 0;
  try {
    const shopifyToken = await getShopifyToken();
    for (const [sku, info] of Object.entries(TARGET_SKUS)){
      try {
        const safeSku = sku.replace(/'/g, "\\'");
        const lookup = await gql(shopifyToken, `{ productVariants(first:1, query:"sku:'${safeSku}'") { nodes { id inventoryPolicy product { id } } } }`);
        const v = lookup?.data?.productVariants?.nodes?.[0];
        if (!v) {
          results[sku] = "not found in Shopify";
          continue;
        }
        if (v.inventoryPolicy === "CONTINUE") {
          results[sku] = "already CONTINUE";
          // Still update sync table to reflect reality
          await supabase.from("katana_stock_sync").upsert({
            sku,
            katana_variant_id: info.variant_id,
            effective_stock: info.expected_stock,
            shopify_inventory_policy: "CONTINUE",
            last_checked_at: new Date().toISOString(),
            notes: `Targeted fix: already CONTINUE (stock: ${info.expected_stock})`
          }, {
            onConflict: "sku"
          });
          continue;
        }
        const update = await gql(shopifyToken, `mutation U($pid:ID!,$vid:ID!,$pol:ProductVariantInventoryPolicy!) { productVariantsBulkUpdate(productId:$pid,variants:[{id:$vid,inventoryPolicy:$pol}]) { productVariants { id inventoryPolicy } userErrors { field message } } }`, {
          pid: v.product.id,
          vid: v.id,
          pol: "CONTINUE"
        });
        const errs = update?.data?.productVariantsBulkUpdate?.userErrors ?? [];
        if (errs.length) throw new Error(JSON.stringify(errs));
        const now = new Date().toISOString();
        await supabase.from("katana_stock_sync").upsert({
          sku,
          katana_variant_id: info.variant_id,
          effective_stock: info.expected_stock,
          shopify_inventory_policy: "CONTINUE",
          last_checked_at: now,
          last_changed_at: now,
          notes: `Targeted fix: DENY → CONTINUE | effective_stock: ${info.expected_stock} (from PO-4252 New Leaf)`
        }, {
          onConflict: "sku"
        });
        results[sku] = "DENY → CONTINUE";
        changed++;
        await new Promise((r)=>setTimeout(r, 1000));
      } catch (e) {
        results[sku] = `error: ${e instanceof Error ? e.message : String(e)}`;
      }
    }
    return new Response(JSON.stringify({
      status: "ok",
      changed,
      results
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: e instanceof Error ? e.message : String(e)
    }), {
      status: 500
    });
  }
});
