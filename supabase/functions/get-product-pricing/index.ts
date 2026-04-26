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
    const { handles } = await req.json();
    if (!handles || !Array.isArray(handles) || handles.length === 0) {
      return new Response(JSON.stringify({
        error: "handles array required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const results = [];
    for (const handle of handles){
      const query = `{ productByHandle(handle: "${handle}") { id title handle status variants(first: 20) { edges { node { id title sku price compareAtPrice inventoryPolicy inventoryQuantity selectedOptions { name value } } } } } }`;
      const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Shopify-Access-Token": token
        },
        body: JSON.stringify({
          query
        })
      });
      const raw = await resp.json();
      if (raw.errors) {
        results.push({
          handle,
          graphql_errors: raw.errors
        });
        continue;
      }
      const product = raw?.data?.productByHandle;
      if (product) {
        results.push({
          handle: product.handle,
          title: product.title,
          status: product.status,
          variants: product.variants.edges.map((ve)=>{
            const v = ve.node;
            return {
              title: v.title,
              sku: v.sku,
              price: v.price,
              compareAtPrice: v.compareAtPrice,
              inventoryPolicy: v.inventoryPolicy,
              inventoryQuantity: v.inventoryQuantity,
              options: v.selectedOptions
            };
          })
        });
      } else {
        results.push({
          handle,
          error: "not found"
        });
      }
    }
    return new Response(JSON.stringify({
      products: results
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
