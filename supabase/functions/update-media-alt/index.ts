import "jsr:@supabase/functions-js/edge-runtime.d.ts";
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
/**
 * update-media-alt v1
 * GET media:  POST { handle: "xxx" }
 * SET alt:    POST { handle: "xxx", updates: [{ media_id: "gid://...", alt: "new alt" }] }
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
    const { handle, product_id, updates } = await req.json();
    if (!handle && !product_id) {
      return new Response(JSON.stringify({
        error: "handle or product_id required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    let productData;
    if (product_id) {
      const gid = product_id.startsWith("gid://") ? product_id : `gid://shopify/Product/${product_id}`;
      const result = await shopifyGraphQL(token, `
        query($id: ID!) {
          product(id: $id) {
            id handle title
            media(first: 50) {
              edges {
                node {
                  ... on MediaImage {
                    id
                    alt
                    image { url width height }
                  }
                }
              }
            }
          }
        }
      `, {
        id: gid
      });
      productData = result?.data?.product;
    } else {
      const result = await shopifyGraphQL(token, `{
        products(first: 1, query: "handle:${handle}") {
          edges {
            node {
              id handle title
              media(first: 50) {
                edges {
                  node {
                    ... on MediaImage {
                      id
                      alt
                      image { url width height }
                    }
                  }
                }
              }
            }
          }
        }
      }`);
      productData = result?.data?.products?.edges?.[0]?.node;
    }
    if (!productData) {
      return new Response(JSON.stringify({
        error: "Product not found"
      }), {
        status: 404
      });
    }
    const images = (productData.media?.edges ?? []).filter((e)=>e.node.id).map((e)=>({
        media_id: e.node.id,
        alt: e.node.alt || "",
        url: e.node.image?.url || "",
        width: e.node.image?.width,
        height: e.node.image?.height
      }));
    let updateResult = null;
    if (updates && Array.isArray(updates) && updates.length > 0) {
      const mediaInput = updates.map((u)=>({
          id: u.media_id,
          alt: u.alt
        }));
      const mutResult = await shopifyGraphQL(token, `
        mutation($productId: ID!, $media: [UpdateMediaInput!]!) {
          productUpdateMedia(productId: $productId, media: $media) {
            media {
              ... on MediaImage {
                id
                alt
              }
            }
            mediaUserErrors {
              field
              message
            }
          }
        }
      `, {
        productId: productData.id,
        media: mediaInput
      });
      const errors = mutResult?.data?.productUpdateMedia?.mediaUserErrors;
      if (errors && errors.length > 0) {
        updateResult = {
          error: "Alt text update failed",
          userErrors: errors
        };
      } else {
        const updated = mutResult?.data?.productUpdateMedia?.media ?? [];
        updateResult = {
          success: true,
          updated_count: updated.length,
          updated: updated.map((m)=>({
              media_id: m.id,
              alt: m.alt
            }))
        };
      }
    }
    const response = {
      product_gid: productData.id,
      handle: productData.handle,
      title: productData.title,
      image_count: images.length,
      images
    };
    if (updateResult) response.update_result = updateResult;
    return new Response(JSON.stringify(response), {
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
