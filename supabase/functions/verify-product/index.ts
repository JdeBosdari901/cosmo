import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const KATANA_API = "https://api.katanamrp.com/v1";
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
async function shopifyGraphQL(token, query, variables) {
  const body = {
    query
  };
  if (variables) body.variables = variables;
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify(body)
  });
  if (!resp.ok) throw new Error(`Shopify GraphQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
async function katanaGet(path) {
  const resp = await fetch(`${KATANA_API}${path}`, {
    headers: {
      Authorization: `Bearer ${KATANA_TOKEN}`
    }
  });
  if (!resp.ok) throw new Error(`Katana API error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
/**
 * verify-product v1
 *
 * Post-creation verification step for the product creation process.
 * Checks Shopify and Katana state against the expected post-publish shape.
 *
 * Input:  { handle: string } or { sku: string }
 * Output: structured check report with human_verification_required flag.
 *
 * Checks performed:
 *   Shopify
 *     - product exists
 *     - status (ACTIVE / DRAFT / ARCHIVED)
 *     - if ACTIVE, onlineStoreUrl is set (published to Online Store)
 *     - featuredImage exists
 *     - for each variant: inventoryItem.tracked === true
 *     - for each variant: inventoryItem weight is set (non-zero)
 *   Katana
 *     - for each Shopify variant SKU: found in Katana
 *     - reports variant_id and product_id
 *
 * Output always includes human_verification_required: true and a reminder
 * block listing what must be checked manually. Automated checks are a
 * necessary but not sufficient condition for "product creation complete".
 */ Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
      }
    });
  }
  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({
        error: "POST required"
      }), {
        status: 405
      });
    }
    const { handle, sku } = await req.json();
    if (!handle && !sku) {
      return new Response(JSON.stringify({
        error: "Provide 'handle' or 'sku'",
        example_handle: {
          handle: "echinacea-white-swan-plants"
        },
        example_sku: {
          sku: "PEREECHPURWHSW-P9"
        }
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    // ──── Find product in Shopify ────
    const productFields = `
      id handle title status
      onlineStoreUrl
      featuredImage { url altText }
      variants(first: 20) {
        edges {
          node {
            id sku
            inventoryItem {
              id tracked
              measurement { weight { value unit } }
            }
          }
        }
      }
    `;
    let product = null;
    if (handle) {
      const res = await shopifyGraphQL(token, `query($q: String!) { products(first: 1, query: $q) { edges { node { ${productFields} } } } }`, {
        q: `handle:${handle}`
      });
      if (res.errors) {
        return new Response(JSON.stringify({
          error: "Shopify top-level GraphQL error",
          detail: res.errors
        }), {
          status: 502
        });
      }
      product = res?.data?.products?.edges?.[0]?.node ?? null;
    } else {
      const res = await shopifyGraphQL(token, `query($q: String!) { productVariants(first: 1, query: $q) { edges { node { product { ${productFields} } } } } }`, {
        q: `sku:${sku}`
      });
      if (res.errors) {
        return new Response(JSON.stringify({
          error: "Shopify top-level GraphQL error",
          detail: res.errors
        }), {
          status: 502
        });
      }
      product = res?.data?.productVariants?.edges?.[0]?.node?.product ?? null;
    }
    if (!product) {
      return new Response(JSON.stringify({
        shopify: {
          found: false
        },
        overall_status: "not_found",
        human_verification_required: false,
        message: `No Shopify product found for ${handle ? "handle" : "sku"}: ${handle || sku}`
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const variants = [];
    const edges = product.variants.edges;
    for (const e of edges){
      const v = e.node;
      variants.push({
        variant_gid: v.id,
        sku: v.sku,
        shopify_tracked: !!v.inventoryItem?.tracked,
        shopify_weight: v.inventoryItem?.measurement?.weight ?? null
      });
    }
    const all_tracked = variants.every((v)=>v.shopify_tracked);
    const any_weight_zero = variants.some((v)=>!v.shopify_weight || v.shopify_weight.value === 0);
    const has_image = !!product.featuredImage;
    const status = product.status;
    const onlineStoreUrl = product.onlineStoreUrl;
    const is_active = status === "ACTIVE";
    const is_published_live = is_active && !!onlineStoreUrl;
    // ──── Check each variant SKU in Katana ────
    const katana_results = [];
    for (const v of variants){
      if (!v.sku) {
        katana_results.push({
          sku: null,
          found: false,
          error: "variant has no sku"
        });
        continue;
      }
      try {
        const res = await katanaGet(`/variants?sku=${encodeURIComponent(v.sku)}`);
        const data = res.data ?? [];
        if (data.length === 0) {
          katana_results.push({
            sku: v.sku,
            found: false
          });
        } else {
          katana_results.push({
            sku: v.sku,
            found: true,
            variant_id: data[0].id,
            product_id: data[0].product_id
          });
        }
        await new Promise((r)=>setTimeout(r, 300));
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        katana_results.push({
          sku: v.sku,
          found: false,
          error: msg
        });
      }
    }
    const all_katana_present = katana_results.every((k)=>k.found);
    // ──── Issues list ────
    const issues = [];
    if (!has_image) issues.push("No featured image set on product");
    if (!all_tracked) {
      const untracked = variants.filter((v)=>!v.shopify_tracked).map((v)=>v.sku || v.variant_gid).join(", ");
      issues.push(`Inventory tracking OFF on variants: ${untracked}`);
    }
    if (any_weight_zero) {
      const no_weight = variants.filter((v)=>!v.shopify_weight || v.shopify_weight.value === 0).map((v)=>v.sku || v.variant_gid).join(", ");
      issues.push(`Variant weight is zero or unset on: ${no_weight}`);
    }
    if (!all_katana_present) {
      const missing = katana_results.filter((k)=>!k.found).map((k)=>k.sku || "(no sku)").join(", ");
      issues.push(`Not found in Katana: ${missing}`);
    }
    if (is_active && !onlineStoreUrl) {
      issues.push("Shopify status is ACTIVE but no onlineStoreUrl — product not reachable on Online Store");
    }
    const overall_status = issues.length === 0 ? "checks_passed" : "issues_found";
    // ──── Human verification reminder ────
    const admin_url = `https://admin.shopify.com/store/${SHOPIFY_SHOP}/products/${(product.id || "").replace("gid://shopify/Product/", "")}`;
    const reminder_lines = [
      "HUMAN VERIFICATION REQUIRED.",
      "Automated checks alone cannot confirm that a product is correctly set up. Before treating this product as complete, a human must:",
      `1. Open the product in Shopify admin and eyeball the settings: ${admin_url}`
    ];
    if (is_published_live && onlineStoreUrl) {
      reminder_lines.push(`2. Visit the live PDP in a browser and confirm it renders correctly: ${onlineStoreUrl}`);
      reminder_lines.push("3. On the live page, visually check: title, image, price, PDP body copy, FAQs, add-to-basket button, spec panel.");
    } else if (is_active && !onlineStoreUrl) {
      reminder_lines.push("2. Product is ACTIVE but has no onlineStoreUrl — check the Online Store channel publication status.");
    } else {
      reminder_lines.push(`2. Product status is ${status}. When you flip to ACTIVE, re-run verify-product to confirm the live rendering check.`);
    }
    reminder_lines.push("4. Confirm the Katana entry is correct if a purchase order is planned: https://app.katanamrp.com/products");
    reminder_lines.push("5. Confirm category assignment, collection membership, and any category-specific metadata (PDP schema, FAQ metaobjects, etc.).");
    return new Response(JSON.stringify({
      version: "v1",
      handle: product.handle,
      title: product.title,
      shopify: {
        found: true,
        gid: product.id,
        status,
        is_active,
        online_store_url: onlineStoreUrl,
        is_published_live,
        has_image,
        variants,
        all_tracked
      },
      katana: {
        all_present: all_katana_present,
        results: katana_results
      },
      overall_status,
      issues: issues.length > 0 ? issues : undefined,
      human_verification_required: true,
      human_verification_reminder: reminder_lines
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({
      error: message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
