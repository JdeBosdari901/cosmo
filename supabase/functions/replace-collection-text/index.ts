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
  if (!resp.ok) throw new Error(`Token failed (${resp.status})`);
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
      variables
    })
  });
  if (!resp.ok) throw new Error(`GQL error (${resp.status})`);
  return resp.json();
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
    }
  });
  try {
    const { handle, replacements } = await req.json();
    if (!handle || !replacements?.length) return new Response(JSON.stringify({
      error: "handle and replacements[] required"
    }), {
      status: 400
    });
    const token = await getShopifyToken();
    // Find collection by handle
    const r = await shopifyGQL(token, `query($handle:String!){collectionByHandle(handle:$handle){id title descriptionHtml}}`, {
      handle
    });
    const col = r?.data?.collectionByHandle;
    if (!col) return new Response(JSON.stringify({
      error: `Collection not found: ${handle}`
    }), {
      status: 404
    });
    let newBody = col.descriptionHtml || "";
    const applied = [];
    for (const [oldText, newText] of replacements){
      if (newBody.includes(oldText)) {
        newBody = newBody.split(oldText).join(newText);
        applied.push(`${oldText} \u2192 ${newText}`);
      }
    }
    if (applied.length === 0) {
      return new Response(JSON.stringify({
        status: "no_changes",
        handle,
        title: col.title
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    const ur = await shopifyGQL(token, `mutation($input:CollectionInput!){collectionUpdate(input:$input){collection{id title handle}userErrors{field message}}}`, {
      input: {
        id: col.id,
        descriptionHtml: newBody
      }
    });
    const ue = ur?.data?.collectionUpdate?.userErrors;
    if (ue?.length) return new Response(JSON.stringify({
      error: "Update failed",
      userErrors: ue
    }), {
      status: 422
    });
    return new Response(JSON.stringify({
      status: "updated",
      handle,
      title: col.title,
      replacements_applied: applied
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
