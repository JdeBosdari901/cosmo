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
async function shopifyGQL(token, query, variables) {
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
  if (!resp.ok) throw new Error(`Shopify GQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}
const MUTATION = `
mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
  productVariantsBulkUpdate(productId: $productId, variants: $variants) {
    productVariants { id title taxable }
    userErrors { field message }
  }
}
`;
const sleep = (ms)=>new Promise((r)=>setTimeout(r, ms));
Deno.serve(async (req)=>{
  if (req.method !== "POST") return new Response(JSON.stringify({
    error: "POST required"
  }), {
    status: 405
  });
  try {
    const { updates } = await req.json();
    // updates: array of { productId: string, variants: [{ id: string, taxable: boolean }] }
    if (!updates || !Array.isArray(updates)) {
      return new Response(JSON.stringify({
        error: "Provide {updates: [{productId, variants: [{id, taxable}]}]}"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const results = [];
    let successCount = 0;
    let errorCount = 0;
    for (const update of updates){
      const variables = {
        productId: update.productId,
        variants: update.variants
      };
      const resp = await shopifyGQL(token, MUTATION, variables);
      const data = resp?.data?.productVariantsBulkUpdate;
      const userErrors = data?.userErrors || [];
      const updated = data?.productVariants || [];
      if (userErrors.length > 0) {
        results.push({
          productId: update.productId,
          errors: userErrors
        });
        errorCount += update.variants.length;
      } else if (resp?.errors) {
        results.push({
          productId: update.productId,
          graphqlErrors: resp.errors
        });
        errorCount += update.variants.length;
      } else {
        results.push({
          productId: update.productId,
          updated: updated.map((v)=>({
              id: v.id,
              title: v.title,
              taxable: v.taxable
            }))
        });
        successCount += updated.length;
      }
      await sleep(2000);
    }
    return new Response(JSON.stringify({
      success: successCount,
      errors: errorCount,
      results
    }, null, 2), {
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
