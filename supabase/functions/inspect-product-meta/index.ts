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
      productByHandle(handle: "${handle}") {
        id
        handle
        title
        status
        templateSuffix
        productType
        tags
        descriptionHtml
        onlineStoreUrl
        onlineStorePreviewUrl
        publishedAt
        availablePublicationsCount { count }
        resourcePublicationsCount { count }
        resourcePublications(first: 20) {
          edges {
            node {
              isPublished
              publishDate
              publication { id name }
            }
          }
        }
        featuredMedia { id mediaContentType alt }
        media(first: 50) {
          edges {
            node {
              id
              mediaContentType
              alt
            }
          }
        }
        metafields(first: 100) {
          edges {
            node {
              namespace
              key
              type
              value
            }
          }
        }
      }
    }`);
    const p = result?.data?.productByHandle;
    if (!p) return new Response(JSON.stringify({ error: "not found", graphql: result }), { status: 404 });
    const metafields = (p.metafields?.edges || []).map((e: any) => ({
      namespace: e.node.namespace,
      key: e.node.key,
      type: e.node.type,
      value_length: (e.node.value || "").length,
      value_preview: (e.node.value || "").substring(0, 200),
    }));
    const media = (p.media?.edges || []).map((e: any) => ({
      id: e.node.id,
      type: e.node.mediaContentType,
      alt: e.node.alt,
    }));
    const publications = (p.resourcePublications?.edges || []).map((e: any) => ({
      channel: e.node.publication?.name,
      isPublished: e.node.isPublished,
      publishDate: e.node.publishDate,
    }));
    return new Response(JSON.stringify({
      id: p.id,
      handle: p.handle,
      title: p.title,
      status: p.status,
      templateSuffix: p.templateSuffix,
      productType: p.productType,
      tags: p.tags,
      descriptionHtmlLength: (p.descriptionHtml || "").length,
      onlineStoreUrl: p.onlineStoreUrl,
      onlineStorePreviewUrl: p.onlineStorePreviewUrl,
      publishedAt: p.publishedAt,
      availablePublicationsCount: p.availablePublicationsCount?.count,
      resourcePublicationsCount: p.resourcePublicationsCount?.count,
      publications,
      featuredMedia: p.featuredMedia,
      mediaCount: media.length,
      media,
      metafieldCount: metafields.length,
      metafields,
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
