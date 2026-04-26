import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GQL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;
async function getToken() {
  const secret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!secret) throw new Error("SHOPIFY_CLIENT_KEY missing");
  const r = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded"
    },
    body: new URLSearchParams({
      grant_type: "client_credentials",
      client_id: SHOPIFY_CLIENT_ID,
      client_secret: secret
    }).toString()
  });
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
  return r.json();
}
Deno.serve(async (req)=>{
  try {
    const { product_gids, add_tags } = await req.json();
    if (!product_gids?.length || !add_tags?.length) {
      return new Response(JSON.stringify({
        error: "product_gids[] and add_tags[] required"
      }), {
        status: 400
      });
    }
    const token = await getToken();
    const results = [];
    for (const gid of product_gids){
      // First get current tags
      const getResult = await gql(token, `query($id: ID!) { product(id: $id) { id tags } }`, {
        id: gid
      });
      const current = getResult?.data?.product?.tags ?? [];
      const merged = Array.from(new Set([
        ...current,
        ...add_tags
      ]));
      // Update with merged tags
      const updateResult = await gql(token, `mutation($id: ID!, $tags: [String!]!) { productUpdate(input: { id: $id, tags: $tags }) { product { id tags } userErrors { field message } } }`, {
        id: gid,
        tags: merged
      });
      const errors = updateResult?.data?.productUpdate?.userErrors ?? [];
      results.push({
        gid,
        tags: merged,
        errors
      });
    }
    const failed = results.filter((r)=>r.errors.length > 0);
    return new Response(JSON.stringify({
      updated: results.length - failed.length,
      failed: failed.length,
      results
    }), {
      status: 200
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: String(e)
    }), {
      status: 500
    });
  }
});
