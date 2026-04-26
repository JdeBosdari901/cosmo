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
function isInSellingWindow(startMonth, endMonth) {
  const m = new Date().getMonth() + 1;
  if (startMonth <= endMonth) return m >= startMonth && m <= endMonth;
  return m >= startMonth || m <= endMonth;
}
function isPresaleOpen(presaleStartMonth, presaleStartDay) {
  const today = new Date();
  const m = today.getMonth() + 1;
  const d = today.getDate();
  if (m > presaleStartMonth) return true;
  if (m === presaleStartMonth && d >= presaleStartDay) return true;
  return false;
}
function determineTargetPolicy(effectiveStock, expected, seasonPolicy) {
  const stockPolicy = effectiveStock > 0 && expected > 0 ? "CONTINUE" : "DENY";
  const stockReason = `effective:${effectiveStock} expected:${expected}`;
  if (!seasonPolicy) return {
    policy: stockPolicy,
    reason: `no_seasonal_policy | ${stockReason}`
  };
  const inWindow = isInSellingWindow(seasonPolicy.start_month, seasonPolicy.end_month);
  if (inWindow) return {
    policy: stockPolicy,
    reason: `in_season | ${stockReason}`
  };
  if (seasonPolicy.presale_start_month !== null) {
    const presaleDay = seasonPolicy.presale_start_day ?? 1;
    if (!isPresaleOpen(seasonPolicy.presale_start_month, presaleDay)) return {
      policy: "DENY",
      reason: `cooling_off | presale opens month:${seasonPolicy.presale_start_month} day:${presaleDay}`
    };
    const policy = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
    return {
      policy,
      reason: `presale_window | presale_allowed:${seasonPolicy.presale_allowed}`
    };
  }
  const policy = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
  return {
    policy,
    reason: `presale_window_no_cooloff | presale_allowed:${seasonPolicy.presale_allowed}`
  };
}
/**
 * v7: Fixes step 5 variant selection to include DENY variants in active presale windows.
 * v6 bug: DENY variants with zero stock were always skipped, even when presale_allowed
 * meant they should be CONTINUE. This caused 55 bulb/orchid SKUs to stay on DENY
 * for days despite active presale windows.
 *
 * Also: manual_override support (from v6), 2s page delay.
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
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const stats = {
    variants_checked: 0,
    policy_changes: 0,
    skipped: 0,
    skipped_override: 0,
    errors: 0,
    inventory_pages: 0,
    changes: []
  };
  try {
    // 1. Paginate all Katana inventory
    const allInventory = [];
    let page = 1;
    let hasMore = true;
    while(hasMore){
      const resp = await fetch(`https://api.katanamrp.com/v1/inventory?limit=100&page=${page}`, {
        headers: {
          Authorization: `Bearer ${KATANA_TOKEN}`
        }
      });
      const data = await resp.json();
      const rows = data.data ?? [];
      allInventory.push(...rows);
      hasMore = rows.length === 100;
      page++;
      await new Promise((r)=>setTimeout(r, 2000));
    }
    stats.inventory_pages = page - 1;
    console.log(`Fetched ${allInventory.length} inventory rows across ${page - 1} pages`);
    // 2. Filter to Grove Cross
    const groveMap = {};
    for (const row of allInventory){
      if (row.location_id !== GROVE_CROSS_LOCATION_ID) continue;
      const inStock = parseFloat(String(row.quantity_in_stock)) || 0;
      const committed = parseFloat(String(row.quantity_committed)) || 0;
      const expected = parseFloat(String(row.quantity_expected)) || 0;
      const safety = parseFloat(String(row.safety_stock_level)) || 0;
      groveMap[row.variant_id] = {
        effective_stock: inStock + expected - committed - safety,
        quantity_expected: expected,
        quantity_in_stock: inStock
      };
    }
    console.log(`Grove Cross: ${Object.keys(groveMap).length} variants`);
    // 3. Fetch seasonal selling policy
    const { data: seasonRows } = await supabase.from("seasonal_selling_policy").select("sku_prefix, start_month, end_month, presale_allowed, presale_start_month, presale_start_day");
    const seasonMap = {};
    for (const row of seasonRows ?? []){
      if (row.sku_prefix) seasonMap[row.sku_prefix] = row;
    }
    console.log(`Loaded ${Object.keys(seasonMap).length} seasonal policies`);
    // 4. Fetch known policies, SKUs, AND manual overrides
    const { data: syncRows } = await supabase.from("katana_stock_sync").select("sku, katana_variant_id, shopify_inventory_policy, manual_override");
    const knownPolicies = {};
    const knownSkus = {};
    const manualOverrides = {};
    for (const row of syncRows ?? []){
      if (row.katana_variant_id && row.shopify_inventory_policy) knownPolicies[row.katana_variant_id] = row.shopify_inventory_policy;
      if (row.katana_variant_id && row.sku) knownSkus[row.katana_variant_id] = row.sku;
      if (row.sku && row.manual_override) manualOverrides[row.sku] = row.manual_override;
    }
    // 5. Identify variants needing attention
    //    v7 FIX: also include DENY variants in active presale windows
    const toProcess = [];
    for (const [vidStr, inv] of Object.entries(groveMap)){
      const variantId = parseInt(vidStr);
      const known = knownPolicies[variantId] ?? null;
      // Always process: unknown, CONTINUE, or has stock
      if (known === null || known === "CONTINUE" || inv.effective_stock > 0 && inv.quantity_expected > 0) {
        toProcess.push({
          variant_id: variantId,
          ...inv
        });
        continue;
      }
      // v7: also process DENY variants where presale window is open
      if (known === "DENY") {
        const sku = knownSkus[variantId];
        if (sku) {
          const prefix = sku.split("-")[0];
          const sp = seasonMap[prefix];
          if (sp && sp.presale_allowed && sp.presale_start_month !== null) {
            const inWindow = isInSellingWindow(sp.start_month, sp.end_month);
            const presaleOpen = isPresaleOpen(sp.presale_start_month, sp.presale_start_day ?? 1);
            if (!inWindow && presaleOpen) {
              toProcess.push({
                variant_id: variantId,
                ...inv
              });
            }
          }
        }
      }
    }
    console.log(`${toProcess.length} variants to check`);
    if (toProcess.length === 0) {
      return new Response(JSON.stringify({
        status: "ok",
        message: "No variants to check",
        stats
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // 6. Process each variant
    const shopifyToken = await getShopifyToken();
    for (const item of toProcess){
      stats.variants_checked++;
      try {
        let sku = knownSkus[item.variant_id] ?? null;
        if (!sku) {
          const varResp = await fetch(`https://api.katanamrp.com/v1/variants/${item.variant_id}`, {
            headers: {
              Authorization: `Bearer ${KATANA_TOKEN}`
            }
          });
          const varData = await varResp.json();
          sku = typeof varData.sku === "string" ? varData.sku : null;
        }
        if (!sku || !sku.includes("-")) {
          stats.skipped++;
          await supabase.from("katana_stock_sync").upsert({
            sku: sku ?? `katana_${item.variant_id}`,
            katana_variant_id: item.variant_id,
            effective_stock: item.effective_stock,
            last_checked_at: new Date().toISOString(),
            notes: "SKU not hyphenated \u2014 skipped"
          }, {
            onConflict: "sku"
          });
          continue;
        }
        // Manual override check
        if (manualOverrides[sku]) {
          stats.skipped_override++;
          await supabase.from("katana_stock_sync").upsert({
            sku,
            katana_variant_id: item.variant_id,
            effective_stock: item.effective_stock,
            quantity_in_stock: item.quantity_in_stock,
            quantity_expected: item.quantity_expected,
            last_checked_at: new Date().toISOString()
          }, {
            onConflict: "sku"
          });
          console.log(`\u23ED ${sku}: manual_override=${manualOverrides[sku]} \u2014 skipping`);
          continue;
        }
        const skuPrefix = sku.split("-")[0];
        const { data: kProduct } = await supabase.from("katana_products").select("product_type, katana_name").eq("sku_prefix", skuPrefix).maybeSingle();
        if (kProduct?.product_type === "voucher") {
          stats.skipped++;
          continue;
        }
        const seasonPolicy = seasonMap[skuPrefix] ?? null;
        const { policy: targetPolicy, reason: policyReason } = determineTargetPolicy(item.effective_stock, item.quantity_expected, seasonPolicy);
        await supabase.from("katana_stock_sync").upsert({
          sku,
          katana_variant_id: item.variant_id,
          effective_stock: item.effective_stock,
          quantity_in_stock: item.quantity_in_stock,
          quantity_expected: item.quantity_expected,
          last_checked_at: new Date().toISOString()
        }, {
          onConflict: "sku"
        });
        const safeSku = sku.replace(/'/g, "\\'");
        const lookupResult = await shopifyGraphQL(shopifyToken, `
          { productVariants(first: 1, query: "sku:'${safeSku}'") {
              nodes { id sku inventoryPolicy product { id } }
          } }
        `);
        const shopifyVariant = lookupResult?.data?.productVariants?.nodes?.[0] ?? null;
        if (!shopifyVariant) {
          stats.skipped++;
          await supabase.from("katana_stock_sync").upsert({
            sku,
            katana_variant_id: item.variant_id,
            notes: "Not found in Shopify",
            last_checked_at: new Date().toISOString()
          }, {
            onConflict: "sku"
          });
          continue;
        }
        const currentPolicy = shopifyVariant.inventoryPolicy;
        await supabase.from("katana_stock_sync").upsert({
          sku,
          katana_variant_id: item.variant_id,
          shopify_inventory_policy: currentPolicy,
          last_checked_at: new Date().toISOString()
        }, {
          onConflict: "sku"
        });
        if (currentPolicy === targetPolicy) continue;
        const updateResult = await shopifyGraphQL(shopifyToken, `mutation U($pid:ID!,$vid:ID!,$pol:ProductVariantInventoryPolicy!) {
            productVariantsBulkUpdate(productId:$pid, variants:[{id:$vid, inventoryPolicy:$pol}]) {
              productVariants { id inventoryPolicy }
              userErrors { field message }
            }
          }`, {
          pid: shopifyVariant.product.id,
          vid: shopifyVariant.id,
          pol: targetPolicy
        });
        const userErrors = updateResult?.data?.productVariantsBulkUpdate?.userErrors ?? [];
        if (userErrors.length > 0) throw new Error(`Shopify errors: ${JSON.stringify(userErrors)}`);
        const now = new Date().toISOString();
        await supabase.from("katana_stock_sync").upsert({
          sku,
          katana_variant_id: item.variant_id,
          effective_stock: item.effective_stock,
          quantity_in_stock: item.quantity_in_stock,
          quantity_expected: item.quantity_expected,
          shopify_inventory_policy: targetPolicy,
          last_checked_at: now,
          last_changed_at: now,
          notes: `Reconciled ${currentPolicy} \u2192 ${targetPolicy} | ${policyReason}`
        }, {
          onConflict: "sku"
        });
        stats.policy_changes++;
        stats.changes.push(`${sku}: ${currentPolicy} \u2192 ${targetPolicy} | ${policyReason}`);
        console.log(`\u2713 ${sku}: ${currentPolicy} \u2192 ${targetPolicy} | ${policyReason}`);
        await new Promise((r)=>setTimeout(r, 2000));
      } catch (varErr) {
        stats.errors++;
        console.error(`Error on variant ${item.variant_id}:`, varErr instanceof Error ? varErr.message : varErr);
      }
    }
    return new Response(JSON.stringify({
      status: "ok",
      stats
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({
      error: message,
      stats
    }), {
      status: 500
    });
  }
});
