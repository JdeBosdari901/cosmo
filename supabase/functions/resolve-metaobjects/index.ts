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
 * resolve-metaobjects v2
 * Added: update_metaobject — updates fields on a single metaobject by GID
 * Accepts: { ids: [...] } for read, or { update_metaobject: { id, fields: [{key, value}] } } for write
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
    if (req.method !== "POST") return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
    const body = await req.json();
    const token = await getShopifyToken();
    // UPDATE path
    if (body.update_metaobject) {
      const { id, fields } = body.update_metaobject;
      if (!id || !fields || !Array.isArray(fields)) return new Response(JSON.stringify({
        error: "update_metaobject requires id and fields array"
      }), {
        status: 400
      });
      const result = await shopifyGraphQL(token, `mutation($id: ID!, $metaobject: MetaobjectUpdateInput!) {
          metaobjectUpdate(id: $id, metaobject: $metaobject) {
            metaobject { id type fields { key value } }
            userErrors { field message code }
          }
        }`, {
        id,
        metaobject: {
          fields
        }
      });
      const userErrors = result?.data?.metaobjectUpdate?.userErrors;
      if (userErrors?.length > 0) return new Response(JSON.stringify({
        error: "Metaobject update failed",
        userErrors
      }), {
        status: 422
      });
      const updated = result?.data?.metaobjectUpdate?.metaobject;
      return new Response(JSON.stringify({
        success: true,
        id: updated?.id,
        type: updated?.type,
        fields: updated?.fields
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // READ path
    const { ids } = body;
    if (!ids || !Array.isArray(ids) || ids.length === 0) return new Response(JSON.stringify({
      error: "ids array required"
    }), {
      status: 400
    });
    const aliases = ids.map((gid, i)=>`obj${i}: metaobject(id: "${gid}") { id type fields { key value reference { ... on ProductVariant { id sku product { handle title } } } } }`).join("\n");
    const result = await shopifyGraphQL(token, `{ ${aliases} }`);
    if (result.errors) return new Response(JSON.stringify({
      error: "GraphQL errors",
      details: result.errors
    }), {
      status: 422
    });
    const objects = Object.values(result.data ?? {}).map((obj)=>{
      const o = obj;
      if (!o) return null;
      const fields = {};
      let sku = null;
      let productHandle = null;
      let productTitle = null;
      for (const f of o.fields ?? []){
        fields[f.key] = f.value;
        if (f.reference?.sku) sku = f.reference.sku;
        if (f.reference?.product?.handle) productHandle = f.reference.product.handle;
        if (f.reference?.product?.title) productTitle = f.reference.product.title;
      }
      return {
        id: o.id,
        type: o.type,
        sku,
        product_handle: productHandle,
        product_title: productTitle,
        fields
      };
    }).filter(Boolean);
    return new Response(JSON.stringify({
      objects
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
