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
      "Accept": "application/json"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: clientSecret
    }).toString()
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  const data = await resp.json();
  return data.access_token;
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
Deno.serve(async (req)=>{
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
    const { slug, body_html, seo_title, seo_description, about_title, search_boost } = await req.json();
    if (!slug) {
      return new Response(JSON.stringify({
        error: "slug is required"
      }), {
        status: 400
      });
    }
    const hasProductUpdate = body_html || seo_title || seo_description;
    const hasMetafieldUpdate = about_title || search_boost;
    if (!hasProductUpdate && !hasMetafieldUpdate) {
      return new Response(JSON.stringify({
        error: "At least one of body_html, seo_title, seo_description, about_title, or search_boost is required"
      }), {
        status: 400
      });
    }
    const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const { data: slugRow, error: slugError } = await supabase.from("shopify_slugs").select("slug, resource_type").eq("slug", slug).eq("resource_type", "product").maybeSingle();
    if (slugError) {
      return new Response(JSON.stringify({
        error: "Slug lookup failed",
        detail: slugError.message
      }), {
        status: 500
      });
    }
    if (!slugRow) {
      return new Response(JSON.stringify({
        error: `Slug not found: ${slug}`
      }), {
        status: 404
      });
    }
    const token = await getShopifyToken();
    const findResult = await shopifyGraphQL(token, `{ products(first: 1, query: "handle:${slug}") { edges { node { id title handle } } } }`);
    const productEdges = findResult?.data?.products?.edges;
    if (!productEdges || productEdges.length === 0) {
      return new Response(JSON.stringify({
        error: `Product not found on Shopify for handle: ${slug}`
      }), {
        status: 404
      });
    }
    const product = productEdges[0].node;
    const productId = product.id;
    let updatedProduct = null;
    if (hasProductUpdate) {
      const updateMutation = `mutation($p: ProductUpdateInput!) {
        productUpdate(product: $p) {
          product { id title handle descriptionHtml seo { title description } }
          userErrors { field message }
        }
      }`;
      const productInput = {
        id: productId
      };
      if (body_html) productInput.descriptionHtml = body_html;
      if (seo_title || seo_description) {
        productInput.seo = {
          ...seo_title ? {
            title: seo_title
          } : {},
          ...seo_description ? {
            description: seo_description
          } : {}
        };
      }
      const updateResult = await shopifyGraphQL(token, updateMutation, {
        p: productInput
      });
      const userErrors = updateResult?.data?.productUpdate?.userErrors;
      if (userErrors && userErrors.length > 0) {
        return new Response(JSON.stringify({
          error: "Shopify productUpdate failed",
          userErrors
        }), {
          status: 422
        });
      }
      updatedProduct = updateResult?.data?.productUpdate?.product;
    }
    const metafieldsUpdated = [];
    if (hasMetafieldUpdate) {
      const metafields = [];
      if (about_title) {
        metafields.push({
          ownerId: productId,
          namespace: "custom",
          key: "about_title",
          value: about_title,
          type: "single_line_text_field"
        });
      }
      if (search_boost) {
        metafields.push({
          ownerId: productId,
          namespace: "shopify--discovery--product_search_boost",
          key: "queries",
          value: JSON.stringify([
            search_boost
          ]),
          type: "list.single_line_text_field"
        });
      }
      const setResult = await shopifyGraphQL(token, `mutation($m: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $m) {
            metafields { namespace key value }
            userErrors { field message }
          }
        }`, {
        m: metafields
      });
      const setErrors = setResult?.data?.metafieldsSet?.userErrors;
      if (setErrors && setErrors.length > 0) {
        return new Response(JSON.stringify({
          error: "Shopify metafieldsSet failed",
          userErrors: setErrors
        }), {
          status: 422
        });
      }
      for (const mf of setResult?.data?.metafieldsSet?.metafields ?? []){
        metafieldsUpdated.push(`${mf.namespace}::${mf.key}`);
      }
    }
    return new Response(JSON.stringify({
      status: "published",
      slug,
      shopify_product_id: productId,
      title: updatedProduct?.title ?? product.title,
      seo: updatedProduct?.seo ?? null,
      metafields_updated: metafieldsUpdated
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
