import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const KATANA_API = "https://api.katanamrp.com/v1";
const VERIFY_PRODUCT_URL = "https://cuposlohqvhikyulhrsx.supabase.co/functions/v1/verify-product";
async function getShopifyToken() {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json"
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
/**
 * create-product v6
 *
 * STRICTLY ADDITIVE — creates new products only, never modifies existing ones.
 *
 * v1: Basic product creation via productSet.
 * v2: Auto-publish to all sales channels.
 * v3: Enable inventory tracking (inventoryItem.tracked = true).
 * v4: Create matching Katana product with SKU check.
 *     Katana creation skipped (not failed) if SKU already exists.
 * v5: Katana SKU check uses filtered search (?sku=VALUE) instead of
 *     fetching first page of all variants. Covers all 2,300+ variants.
 * v6: Chain verify-product on the happy path. After all creation/publication
 *     steps complete, call verify-product with the new handle and merge its
 *     structured check report + human verification reminder into the response.
 *
 *     Verify-chain is non-fatal: if verify-product fails to respond or errors,
 *     the create response still reports created:true, and the verification
 *     key carries {status: "verify_error", message}. The creation itself
 *     is not rolled back by a verify failure.
 *
 *     Can be skipped with {skip_verification: true} in the request body.
 *     Default is false (verify always runs).
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
    const { title, handle, product_type, sku, price, tags = [
      "Plants"
    ], status = "DRAFT", variant_form = "Potted", variant_size = "P9", inventory_policy = "DENY", subtitle, register_slug = true, publish_to_channels = true, create_in_katana = true, katana_category, skip_verification = false } = await req.json();
    const missing = [];
    if (!title) missing.push("title");
    if (!handle) missing.push("handle (Ahrefs-checked slug)");
    if (!product_type) missing.push("product_type");
    if (!sku) missing.push("sku");
    if (!price) missing.push("price");
    if (missing.length > 0) {
      return new Response(JSON.stringify({
        error: "Missing required fields",
        missing
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    // —— SHOPIFY: Check handle doesn't already exist ————————————————
    const existCheck = await shopifyGraphQL(token, `{ products(first: 1, query: "handle:${handle}") { edges { node { id handle } } } }`);
    if (existCheck?.data?.products?.edges?.length > 0) {
      return new Response(JSON.stringify({
        error: "Product with this handle already exists",
        existing_handle: existCheck.data.products.edges[0].node.handle,
        existing_gid: existCheck.data.products.edges[0].node.id
      }), {
        status: 409
      });
    }
    // —— SHOPIFY: Create product via productSet ———————————————
    const productSetInput = {
      title,
      handle,
      productType: product_type,
      tags,
      status: status.toUpperCase(),
      descriptionHtml: `<p>${title} — PDP pending.</p>`,
      productOptions: [
        {
          name: "Form",
          values: [
            {
              name: variant_form
            }
          ]
        },
        {
          name: "Size",
          values: [
            {
              name: variant_size
            }
          ]
        }
      ],
      variants: [
        {
          price,
          sku,
          inventoryPolicy: inventory_policy.toUpperCase(),
          inventoryItem: {
            tracked: true
          },
          optionValues: [
            {
              optionName: "Form",
              name: variant_form
            },
            {
              optionName: "Size",
              name: variant_size
            }
          ]
        }
      ]
    };
    const createResult = await shopifyGraphQL(token, `mutation($input: ProductSetInput!, $sync: Boolean!) {
        productSet(synchronous: $sync, input: $input) {
          product {
            id
            handle
            title
            status
            variants(first: 5) {
              edges {
                node { id sku price inventoryPolicy inventoryItem { tracked } }
              }
            }
          }
          userErrors { field message code }
        }
      }`, {
      input: productSetInput,
      sync: true
    });
    const userErrors = createResult?.data?.productSet?.userErrors;
    if (userErrors && userErrors.length > 0) {
      return new Response(JSON.stringify({
        error: "Shopify productSet failed",
        userErrors
      }), {
        status: 422
      });
    }
    const product = createResult?.data?.productSet?.product;
    if (!product) {
      return new Response(JSON.stringify({
        error: "Product creation returned no product",
        raw: createResult
      }), {
        status: 500
      });
    }
    const numericId = product.id.replace("gid://shopify/Product/", "");
    // —— SHOPIFY: Set subtitle metafield if provided —————————————
    let metafieldsSet = [];
    if (subtitle) {
      const mfResult = await shopifyGraphQL(token, `mutation($m: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $m) {
            metafields { namespace key value }
            userErrors { field message }
          }
        }`, {
        m: [
          {
            ownerId: product.id,
            namespace: "product_data",
            key: "subtitle",
            value: subtitle,
            type: "single_line_text_field"
          }
        ]
      });
      if (!mfResult?.data?.metafieldsSet?.userErrors?.length) {
        metafieldsSet.push("product_data::subtitle");
      }
    }
    // —— SUPABASE: Register slug —————————————————————————
    let slugRegistered = false;
    if (register_slug) {
      const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
      const { error: slugErr } = await supabase.from("shopify_slugs").upsert({
        slug: handle,
        resource_type: "product",
        shopify_resource_id: numericId,
        notes: `Created via create-product. ${new Date().toISOString().split('T')[0]}. Price £${price} — VERIFY.`
      }, {
        onConflict: "slug,resource_type"
      });
      slugRegistered = !slugErr;
    }
    // —— SHOPIFY: Publish to all sales channels ——————————————
    let channelsPublished = [];
    if (publish_to_channels) {
      try {
        const pubResult = await shopifyGraphQL(token, `{
          publications(first: 20) {
            edges { node { id name } }
          }
        }`);
        const publications = pubResult?.data?.publications?.edges?.map((e)=>e.node) || [];
        if (publications.length > 0) {
          const publishResult = await shopifyGraphQL(token, `mutation($id: ID!, $input: [PublicationInput!]!) {
              publishablePublish(id: $id, input: $input) {
                publishable { ... on Product { id } }
                userErrors { field message }
              }
            }`, {
            id: product.id,
            input: publications.map((p)=>({
                publicationId: p.id
              }))
          });
          const pubErrors = publishResult?.data?.publishablePublish?.userErrors || [];
          if (pubErrors.length === 0) {
            channelsPublished = publications.map((p)=>p.name);
          }
        }
      } catch (_) {
      // Non-fatal
      }
    }
    // —— KATANA: Create matching product (v5) ————————————————
    // STRICTLY ADDITIVE: check if SKU exists first, never modify existing products
    let katanaResult = {
      status: "skipped"
    };
    if (create_in_katana) {
      try {
        // Check if SKU already exists in Katana (v5: filtered search by exact SKU)
        const checkResp = await fetch(`${KATANA_API}/variants?per_page=1&sku=${encodeURIComponent(sku)}`, {
          headers: {
            Authorization: `Bearer ${KATANA_TOKEN}`
          }
        });
        const checkData = await checkResp.json();
        const existingVariant = (checkData.data ?? [])[0] ?? null;
        if (existingVariant) {
          // SKU already exists in Katana — DO NOT modify, just report
          katanaResult = {
            status: "skipped_existing",
            product_id: existingVariant.product_id,
            variant_id: existingVariant.id,
            message: `SKU ${sku} already exists in Katana — not modified`
          };
        } else {
          // Create new product in Katana
          const katanaResp = await fetch(`${KATANA_API}/products`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${KATANA_TOKEN}`,
              "Content-Type": "application/json"
            },
            body: JSON.stringify({
              name: title,
              category_name: katana_category || product_type,
              is_sellable: true,
              is_purchasable: true,
              is_producible: false,
              variants: [
                {
                  sku,
                  sales_price: parseFloat(price)
                }
              ]
            })
          });
          if (katanaResp.ok) {
            const katanaProduct = await katanaResp.json();
            katanaResult = {
              status: "created",
              product_id: katanaProduct.id,
              variant_id: katanaProduct.variants?.[0]?.id
            };
          } else {
            const errText = await katanaResp.text();
            katanaResult = {
              status: "failed",
              message: `Katana API error (${katanaResp.status}): ${errText.slice(0, 200)}`
            };
          }
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        katanaResult = {
          status: "failed",
          message: msg
        };
      }
    }
    // —— VERIFY-PRODUCT: Chain post-creation verification (v6) ——————————
    // Non-fatal wrapper. If verify-product throws, times out, or returns a
    // non-200, the creation is still reported as successful, with the
    // verification field carrying the error. The caller MUST surface the
    // human_verification_reminder block in full when present.
    let verification = {
      status: "skipped"
    };
    if (!skip_verification) {
      try {
        const verifyResp = await fetch(VERIFY_PRODUCT_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            handle: product.handle
          })
        });
        if (verifyResp.ok) {
          verification = await verifyResp.json();
        } else {
          const errText = await verifyResp.text();
          verification = {
            status: "verify_error",
            message: `verify-product returned ${verifyResp.status}: ${errText.slice(0, 300)}`
          };
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        verification = {
          status: "verify_error",
          message: msg
        };
      }
    }
    const variant = product.variants?.edges?.[0]?.node;
    return new Response(JSON.stringify({
      created: true,
      shopify_gid: product.id,
      shopify_product_id: numericId,
      handle: product.handle,
      title: product.title,
      status: product.status,
      variant: {
        sku: variant?.sku,
        price: variant?.price,
        inventory_policy: variant?.inventoryPolicy,
        inventory_tracked: variant?.inventoryItem?.tracked
      },
      slug_registered: slugRegistered,
      metafields_set: metafieldsSet,
      channels_published: channelsPublished,
      katana: katanaResult,
      verification,
      review_required: {
        price: `£${price} — VERIFY THIS IS CORRECT before setting product to ACTIVE`
      }
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
