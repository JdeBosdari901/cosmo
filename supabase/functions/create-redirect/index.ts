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
    if (req.method !== "POST") {
      return new Response(JSON.stringify({
        error: "POST required"
      }), {
        status: 405
      });
    }
    const { redirects } = await req.json();
    // redirects: array of { from: string, to: string }
    if (!redirects || !Array.isArray(redirects) || redirects.length === 0) {
      return new Response(JSON.stringify({
        error: "redirects array is required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const results = [];
    for (const r of redirects){
      try {
        const mutation = `mutation($redirect: UrlRedirectInput!) {
          urlRedirectCreate(urlRedirect: $redirect) {
            urlRedirect { id path target }
            userErrors { field message }
          }
        }`;
        const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Shopify-Access-Token": token
          },
          body: JSON.stringify({
            query: mutation,
            variables: {
              redirect: {
                path: r.from,
                target: r.to
              }
            }
          })
        });
        if (!resp.ok) {
          results.push({
            from: r.from,
            to: r.to,
            status: "error",
            error: `HTTP ${resp.status}`
          });
          continue;
        }
        const data = await resp.json();
        const userErrors = data?.data?.urlRedirectCreate?.userErrors;
        if (userErrors && userErrors.length > 0) {
          results.push({
            from: r.from,
            to: r.to,
            status: "error",
            error: userErrors.map((e)=>e.message).join("; ")
          });
        } else {
          results.push({
            from: r.from,
            to: r.to,
            status: "created"
          });
        }
      } catch (err) {
        results.push({
          from: r.from,
          to: r.to,
          status: "error",
          error: err.message
        });
      }
    }
    const created = results.filter((r)=>r.status === "created").length;
    const errors = results.filter((r)=>r.status === "error").length;
    return new Response(JSON.stringify({
      summary: {
        total: redirects.length,
        created,
        errors
      },
      results
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
