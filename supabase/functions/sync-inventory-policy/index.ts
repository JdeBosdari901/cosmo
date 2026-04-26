import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const GROVE_CROSS_LOCATION_ID = 162781;
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
  if (!resp.ok) throw new Error(`Shopify token request failed (${resp.status}): ${await resp.text()}`);
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
function isInSellingWindow(startMonth, endMonth) {
  const m = new Date().getMonth() + 1;
  if (startMonth <= endMonth) {
    return m >= startMonth && m <= endMonth;
  } else {
    return m >= startMonth || m <= endMonth;
  }
}
function isPresaleOpen(presaleStartMonth, presaleStartDay) {
  const today = new Date();
  const m = today.getMonth() + 1;
  const d = today.getDate();
  if (m > presaleStartMonth) return true;
  if (m === presaleStartMonth && d >= presaleStartDay) return true;
  return false;
}
/**
 * v10: Respects manual_override.
 *
 * Root cause fixed: v9 computed targetPolicy purely from stock + seasonal
 * rules and ignored manual_override entirely. This caused a see-saw with
 * reconcile-three-stage for any SKU with an override set where the computed
 * policy disagreed — this webhook would flip Shopify back, the reconciler
 * would flip it forward, repeatedly.
 *
 * v10 change: if katana_stock_sync.manual_override IS NOT NULL, use it as
 * the target policy (short-circuits the decision tree). All other logic
 * (Shopify lookup, mutation, audit trail, sync row upsert) unchanged.
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
  let body;
  try {
    body = await req.json();
  } catch  {
    return new Response(JSON.stringify({
      error: "Invalid JSON"
    }), {
      status: 400
    });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  let variantId = null;
  const obj = body.object;
  if (typeof obj?.variant_id === "number") {
    variantId = obj.variant_id;
  } else if (typeof obj?.id === "number") {
    variantId = obj.id;
  } else if (typeof body.katana_variant_id === "number") {
    variantId = body.katana_variant_id;
  } else if (typeof body.variant_id === "number") {
    variantId = body.variant_id;
  }
  if (variantId === null) {
    console.error("payload_unrecognised:", JSON.stringify(body));
    return new Response(JSON.stringify({
      status: "payload_unrecognised",
      message: "Could not extract variant_id",
      received_top_keys: Object.keys(body),
      received_object_keys: obj ? Object.keys(obj) : null
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  try {
    const invResp = await fetch(`https://api.katanamrp.com/v1/inventory?variant_id=${variantId}`, {
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`
      }
    });
    const invData = await invResp.json();
    const groveRow = (invData.data ?? []).find((r)=>r.location_id === GROVE_CROSS_LOCATION_ID);
    if (!groveRow) {
      return new Response(JSON.stringify({
        status: "skipped",
        reason: "no_grove_cross_row",
        katana_variant_id: variantId
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const inStock = parseFloat(String(groveRow.quantity_in_stock)) || 0;
    const committed = parseFloat(String(groveRow.quantity_committed)) || 0;
    const expected = parseFloat(String(groveRow.quantity_expected)) || 0;
    const safety = parseFloat(String(groveRow.safety_stock_level)) || 0;
    const effectiveStock = inStock + expected - committed - safety;
    const varResp = await fetch(`https://api.katanamrp.com/v1/variants/${variantId}`, {
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`
      }
    });
    const varData = await varResp.json();
    const sku = typeof varData.sku === "string" ? varData.sku : null;
    if (!sku || !sku.includes("-")) {
      return new Response(JSON.stringify({
        status: "skipped",
        reason: "sku_not_hyphenated",
        sku,
        katana_variant_id: variantId
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const skuPrefix = sku.split("-")[0];
    const { data: kProduct } = await supabase.from("katana_products").select("product_type, katana_name").eq("sku_prefix", skuPrefix).maybeSingle();
    if (kProduct?.product_type === "voucher") {
      return new Response(JSON.stringify({
        status: "skipped",
        reason: "voucher_excluded",
        sku
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Look up seasonal selling policy
    const { data: seasonPolicy } = await supabase.from("seasonal_selling_policy").select("start_month, end_month, presale_allowed, presale_start_month, presale_start_day").eq("sku_prefix", skuPrefix).maybeSingle();
    // v10: Fetch manual_override alongside shopify policy (previously only policy)
    const { data: syncRow } = await supabase.from("katana_stock_sync").select("shopify_inventory_policy, manual_override").eq("sku", sku).maybeSingle();
    const knownPolicy = syncRow?.shopify_inventory_policy ?? null;
    const manualOverride = syncRow?.manual_override ?? null;
    // Determine target policy using decision tree
    let targetPolicy;
    let policyReason;
    let seasonalContext = null;
    const stockBasedPolicy = effectiveStock > 0 && expected > 0 ? "CONTINUE" : "DENY";
    if (seasonPolicy) {
      seasonalContext = `season ${seasonPolicy.start_month}-${seasonPolicy.end_month}`;
      if (seasonPolicy.presale_start_month) {
        seasonalContext += `, presale opens ${seasonPolicy.presale_start_month}/${seasonPolicy.presale_start_day ?? 1}`;
      }
      const inWindow = isInSellingWindow(seasonPolicy.start_month, seasonPolicy.end_month);
      if (inWindow) {
        targetPolicy = stockBasedPolicy;
        policyReason = `in_season | effective:${effectiveStock} expected:${expected}`;
      } else {
        if (seasonPolicy.presale_start_month !== null) {
          const presaleDay = seasonPolicy.presale_start_day ?? 1;
          const presaleOpen = isPresaleOpen(seasonPolicy.presale_start_month, presaleDay);
          if (!presaleOpen) {
            targetPolicy = "DENY";
            policyReason = `cooling_off | presale opens month:${seasonPolicy.presale_start_month} day:${presaleDay}`;
          } else {
            targetPolicy = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
            policyReason = `presale_window | presale_allowed:${seasonPolicy.presale_allowed}`;
          }
        } else {
          targetPolicy = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
          policyReason = `presale_window_no_cooloff | presale_allowed:${seasonPolicy.presale_allowed}`;
        }
      }
    } else {
      targetPolicy = stockBasedPolicy;
      policyReason = `no_seasonal_policy | effective:${effectiveStock} expected:${expected}`;
    }
    // v10: manual_override short-circuits the decision tree.
    // This prevents the see-saw with reconcile-three-stage.
    if (manualOverride === "CONTINUE" || manualOverride === "DENY") {
      const computedPolicy = targetPolicy;
      const computedReason = policyReason;
      targetPolicy = manualOverride;
      policyReason = `manual_override:${manualOverride} (computed would be ${computedPolicy}: ${computedReason})`;
    }
    // Always write stock components
    await supabase.from("katana_stock_sync").upsert({
      sku,
      katana_variant_id: variantId,
      effective_stock: effectiveStock,
      quantity_in_stock: inStock,
      quantity_expected: expected,
      last_checked_at: new Date().toISOString(),
      last_webhook_payload: body
    }, {
      onConflict: "sku"
    });
    if (knownPolicy === targetPolicy) {
      return new Response(JSON.stringify({
        status: "no_change",
        sku,
        policy: targetPolicy,
        effective_stock: effectiveStock,
        quantity_in_stock: inStock,
        quantity_expected: expected,
        reason: policyReason
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Policy needs to change — find variant in Shopify
    const shopifyToken = await getShopifyToken();
    const safeSku = sku.replace(/'/g, "\\'");
    const lookupResult = await shopifyGraphQL(shopifyToken, `
      {
        productVariants(first: 1, query: "sku:'${safeSku}'") {
          nodes { id sku inventoryPolicy product { id } }
        }
      }
    `);
    const shopifyVariant = lookupResult?.data?.productVariants?.nodes?.[0] ?? null;
    if (!shopifyVariant) {
      await supabase.from("katana_stock_sync").upsert({
        sku,
        katana_variant_id: variantId,
        notes: "SKU not found in Shopify",
        last_checked_at: new Date().toISOString()
      }, {
        onConflict: "sku"
      });
      return new Response(JSON.stringify({
        status: "skipped",
        reason: "not_found_in_shopify",
        sku
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const currentShopifyPolicy = shopifyVariant.inventoryPolicy;
    await supabase.from("katana_stock_sync").upsert({
      sku,
      katana_variant_id: variantId,
      shopify_inventory_policy: currentShopifyPolicy,
      last_checked_at: new Date().toISOString()
    }, {
      onConflict: "sku"
    });
    if (currentShopifyPolicy === targetPolicy) {
      return new Response(JSON.stringify({
        status: "already_correct",
        sku,
        policy: targetPolicy,
        effective_stock: effectiveStock,
        quantity_expected: expected,
        reason: policyReason
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Apply the change in Shopify
    const updateResult = await shopifyGraphQL(shopifyToken, `mutation UpdatePolicy($productId: ID!, $variantId: ID!, $policy: ProductVariantInventoryPolicy!) {
        productVariantsBulkUpdate(productId: $productId, variants: [{ id: $variantId, inventoryPolicy: $policy }]) {
          productVariants { id inventoryPolicy }
          userErrors { field message }
        }
      }`, {
      productId: shopifyVariant.product.id,
      variantId: shopifyVariant.id,
      policy: targetPolicy
    });
    const userErrors = updateResult?.data?.productVariantsBulkUpdate?.userErrors ?? [];
    if (userErrors.length > 0) {
      throw new Error(`Shopify update errors: ${JSON.stringify(userErrors)}`);
    }
    const now = new Date().toISOString();
    await supabase.from("katana_stock_sync").upsert({
      sku,
      katana_variant_id: variantId,
      effective_stock: effectiveStock,
      quantity_in_stock: inStock,
      quantity_expected: expected,
      shopify_inventory_policy: targetPolicy,
      last_checked_at: now,
      last_changed_at: now,
      notes: `Changed ${currentShopifyPolicy} \u2192 ${targetPolicy} | ${policyReason}`
    }, {
      onConflict: "sku"
    });
    // ── AUDIT TRAIL ──────────────────────────────────────────────────────────
    await supabase.from("inventory_policy_audit").insert({
      sku,
      katana_variant_id: variantId,
      previous_policy: currentShopifyPolicy,
      new_policy: targetPolicy,
      reason: policyReason,
      source: "sync-inventory-policy",
      quantity_in_stock: inStock,
      quantity_expected: expected,
      effective_stock: effectiveStock,
      seasonal_context: seasonalContext
    });
    console.log(`\u2713 ${sku}: ${currentShopifyPolicy} \u2192 ${targetPolicy} (${policyReason})`);
    return new Response(JSON.stringify({
      status: "updated",
      sku,
      product_name: kProduct?.katana_name ?? sku,
      effective_stock: effectiveStock,
      quantity_in_stock: inStock,
      quantity_expected: expected,
      previous_policy: currentShopifyPolicy,
      new_policy: targetPolicy,
      reason: policyReason
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`Error processing variant ${variantId}:`, message);
    return new Response(JSON.stringify({
      error: message,
      katana_variant_id: variantId
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
