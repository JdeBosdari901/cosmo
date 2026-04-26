import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GQL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
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
      variables
    })
  });
  const text = await r.text();
  return {
    status: r.status,
    body: text
  };
}
Deno.serve(async (req)=>{
  if (req.method !== "POST") return new Response(JSON.stringify({
    error: "POST required"
  }), {
    status: 405
  });
  try {
    const shopifyToken = await getShopifyToken();
    const results = {};
    // Test 1: Check app scopes
    const scopeResult = await gql(shopifyToken, `{ app { id apiKey handle } }`, {});
    results.app_query = JSON.parse(scopeResult.body);
    // Test 2: Try productCreate with OLD syntax (variants with options array)
    const oldSyntax = await gql(shopifyToken, `mutation { productCreate(input: {
        title: "DIAGNOSTIC TEST DELETE ME",
        status: DRAFT,
        vendor: "Ashridge",
        variants: [{ price: "8.99", sku: "DIAG-TEST-OLD", options: ["Seedling", "4 Jumbo Plugs"] }]
      }) {
        product { id handle }
        userErrors { field message code }
      }}`, {});
    results.old_syntax_raw = JSON.parse(oldSyntax.body);
    // Test 3: Try productCreate with NO variants (just product)
    const noVariants = await gql(shopifyToken, `mutation { productCreate(input: {
        title: "DIAGNOSTIC TEST 2 DELETE ME",
        status: DRAFT,
        vendor: "Ashridge"
      }) {
        product { id handle }
        userErrors { field message code }
      }}`, {});
    results.no_variants_raw = JSON.parse(noVariants.body);
    // If product 2 was created, delete it
    const p2 = results.no_variants_raw;
    const p2data = p2?.data;
    const p2create = p2data?.productCreate;
    const p2product = p2create?.product;
    if (p2product?.id) {
      await gql(shopifyToken, `mutation { productDelete(input: { id: "${p2product.id}" }) { deletedProductId userErrors { message } } }`, {});
      results.product2_deleted = p2product.id;
    }
    return new Response(JSON.stringify({
      status: "ok",
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
