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
/**
 * get-metaobjects v4
 * Modes:
 *   { ids: [...] } — fetch Metaobject fields by GID
 *   { graphql: "query { ... }" } — run arbitrary read-only GraphQL
 *   { update_metaobject: { id, fields: [{key, value}] } } — update a Metaobject
 */ Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  try {
    const body = await req.json();
    const token = await getShopifyToken();
    let query;
    let variables;
    if (body.update_metaobject) {
      const { id, fields } = body.update_metaobject;
      query = `mutation($id: ID!, $metaobject: MetaobjectUpdateInput!) {
        metaobjectUpdate(id: $id, metaobject: $metaobject) {
          metaobject { id type displayName fields { key value } }
          userErrors { field message }
        }
      }`;
      variables = {
        id,
        metaobject: {
          fields
        }
      };
    } else if (body.graphql) {
      query = body.graphql;
      variables = body.variables;
    } else if (body.ids && Array.isArray(body.ids)) {
      const nodeQueries = body.ids.map((id, i)=>`node${i}: node(id: "${id}") { ... on Metaobject { id type displayName fields { key value type } } ... on ProductVariant { id title sku } ... on Product { id title handle } }`).join("\n");
      query = `query { ${nodeQueries} }`;
    } else {
      return new Response(JSON.stringify({
        error: "Provide ids, graphql, or update_metaobject"
      }), {
        status: 400
      });
    }
    const gqlBody = {
      query
    };
    if (variables) gqlBody.variables = variables;
    const res = await fetch(SHOPIFY_GRAPHQL_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Access-Token": token
      },
      body: JSON.stringify(gqlBody)
    });
    if (!res.ok) {
      return new Response(JSON.stringify({
        error: `Shopify API error (${res.status})`,
        detail: await res.text()
      }), {
        status: 502
      });
    }
    const data = await res.json();
    return new Response(JSON.stringify(data), {
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
