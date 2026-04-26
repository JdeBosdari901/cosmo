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
 * publish-to-channels v2
 * Publishes a product to all available Shopify sales channels.
 * Input: { product_id } or { handle }
 * Returns before/after publication status.
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
    if (req.method !== "POST") {
      return new Response(JSON.stringify({
        error: "POST required"
      }), {
        status: 405
      });
    }
    const { product_id, handle } = await req.json();
    if (!product_id && !handle) {
      return new Response(JSON.stringify({
        error: "Either product_id or handle required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    // Resolve product GID
    let productGid;
    if (product_id) {
      productGid = product_id.startsWith("gid://") ? product_id : `gid://shopify/Product/${product_id}`;
    } else {
      const lookup = await shopifyGraphQL(token, `{ products(first: 1, query: "handle:${handle}") { edges { node { id } } } }`);
      productGid = lookup?.data?.products?.edges?.[0]?.node?.id;
      if (!productGid) {
        return new Response(JSON.stringify({
          error: `Product not found: ${handle}`
        }), {
          status: 404
        });
      }
    }
    // Get all publications
    const pubResult = await shopifyGraphQL(token, `{
      publications(first: 20) {
        edges {
          node {
            id
            name
          }
        }
      }
    }`);
    const publications = pubResult?.data?.publications?.edges?.map((e)=>e.node) || [];
    if (publications.length === 0) {
      return new Response(JSON.stringify({
        error: "No publications found",
        raw: pubResult
      }), {
        status: 500
      });
    }
    // Check current publication status
    const beforeResult = await shopifyGraphQL(token, `{
      product(id: "${productGid}") {
        title
        resourcePublicationsV2(first: 20) {
          edges {
            node {
              publication { id name }
              isPublished
            }
          }
        }
      }
    }`);
    const beforePubs = beforeResult?.data?.product?.resourcePublicationsV2?.edges?.map((e)=>({
        name: e.node.publication.name,
        wasPublished: e.node.isPublished
      })) || [];
    // Publish to all channels
    const publishInput = publications.map((p)=>({
        publicationId: p.id
      }));
    const publishResult = await shopifyGraphQL(token, `mutation($id: ID!, $input: [PublicationInput!]!) {
        publishablePublish(id: $id, input: $input) {
          publishable { ... on Product { id title } }
          userErrors { field message }
        }
      }`, {
      id: productGid,
      input: publishInput
    });
    const userErrors = publishResult?.data?.publishablePublish?.userErrors || [];
    if (userErrors.length > 0) {
      return new Response(JSON.stringify({
        error: "Publish failed",
        userErrors,
        publications_targeted: publications.map((p)=>p.name)
      }), {
        status: 422
      });
    }
    // Verify after publish
    const afterResult = await shopifyGraphQL(token, `{
      product(id: "${productGid}") {
        title
        resourcePublicationsV2(first: 20) {
          edges {
            node {
              publication { id name }
              isPublished
            }
          }
        }
      }
    }`);
    const afterPubs = afterResult?.data?.product?.resourcePublicationsV2?.edges?.map((e)=>({
        name: e.node.publication.name,
        isPublished: e.node.isPublished
      })) || [];
    return new Response(JSON.stringify({
      product: productGid,
      title: afterResult?.data?.product?.title,
      before: beforePubs,
      after: afterPubs,
      success: true
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: String(err)
    }), {
      status: 500
    });
  }
});
