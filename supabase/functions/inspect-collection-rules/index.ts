import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;

async function getShopifyToken(): Promise<string> {
  const clientSecret = Deno.env.get("SHOPIFY_CLIENT_KEY");
  if (!clientSecret) throw new Error("SHOPIFY_CLIENT_KEY not configured");
  const resp = await fetch(SHOPIFY_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: SHOPIFY_CLIENT_ID, client_secret: clientSecret }).toString(),
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  return (await resp.json()).access_token;
}

async function gql(token: string, query: string) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": token },
    body: JSON.stringify({ query }),
  });
  if (!resp.ok) throw new Error(`GraphQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" } });
  }
  try {
    const { handle } = await req.json();
    if (!handle) return new Response(JSON.stringify({ error: "handle required" }), { status: 400 });
    const token = await getShopifyToken();
    const result = await gql(token, `{
      collectionByHandle(handle: "${handle}") {
        id
        handle
        title
        sortOrder
        templateSuffix
        ruleSet {
          appliedDisjunctively
          rules { column relation condition }
        }
        products(first: 250) {
          edges { node { id handle title productType tags } }
        }
      }
    }`);
    const coll = result?.data?.collectionByHandle;
    if (!coll) return new Response(JSON.stringify({ error: "not found", graphql: result }), { status: 404 });
    const products = (coll.products?.edges || []).map((e: any) => ({
      handle: e.node.handle,
      title: e.node.title,
      productType: e.node.productType,
      tags: e.node.tags,
    }));
    return new Response(JSON.stringify({
      id: coll.id,
      handle: coll.handle,
      title: coll.title,
      sortOrder: coll.sortOrder,
      templateSuffix: coll.templateSuffix,
      isSmartCollection: coll.ruleSet !== null,
      ruleSet: coll.ruleSet,
      productCount: products.length,
      products: products,
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
