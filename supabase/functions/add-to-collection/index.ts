import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GQL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
async function getShopifyToken() {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: clientSecret
    }).toString()
  });
  if (!resp.ok) throw new Error(`Token failed: ${await resp.text()}`);
  return (await resp.json()).access_token;
}
async function gql(token, query, variables) {
  const resp = await fetch(SHOPIFY_GQL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query,
      variables
    })
  });
  return resp.json();
}
Deno.serve(async (req)=>{
  try {
    const { collection_gid, product_gids } = await req.json();
    if (!collection_gid || !Array.isArray(product_gids) || product_gids.length === 0) {
      return new Response(JSON.stringify({
        error: "collection_gid and product_gids[] required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const mutation = `
      mutation AddToCollection($collectionId: ID!, $productIds: [ID!]!) {
        collectionAddProducts(id: $collectionId, productIds: $productIds) {
          collection { id title productsCount { count } }
          userErrors { field message }
        }
      }`;
    const result = await gql(token, mutation, {
      collectionId: collection_gid,
      productIds: product_gids
    });
    const op = result?.data?.collectionAddProducts;
    const errors = op?.userErrors ?? [];
    return new Response(JSON.stringify({
      success: errors.length === 0,
      collection: op?.collection,
      userErrors: errors,
      added: product_gids.length
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: String(e)
    }), {
      status: 500
    });
  }
});
