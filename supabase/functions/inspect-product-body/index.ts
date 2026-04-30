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
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: SHOPIFY_CLIENT_ID, client_secret: clientSecret }).toString(),
  });
  if (!resp.ok) throw new Error(`Token request failed: ${await resp.text()}`);
  return (await resp.json()).access_token;
}

Deno.serve(async (req: Request) => {
  try {
    const { handle, extract } = await req.json();
    const token = await getShopifyToken();
    const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": token },
      body: JSON.stringify({
        query: `{ productByHandle(handle: "${handle}") { id handle title descriptionHtml } }`,
      }),
    });
    const json = await resp.json();
    const p = json?.data?.productByHandle;
    if (!p) return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
    const html = p.descriptionHtml || "";
    
    if (extract === "pdp-specs") {
      // Extract the pdp-specs block plus 200 chars of context on each side
      const startMarker = '<ul class="pdp-specs"';
      const idx = html.indexOf(startMarker);
      if (idx === -1) return new Response(JSON.stringify({ handle: p.handle, found: false }), { headers: { "Content-Type": "application/json" } });
      const endIdx = html.indexOf("</ul>", idx);
      const block = html.substring(idx, endIdx + 5);
      const before = html.substring(Math.max(0, idx - 200), idx);
      const after = html.substring(endIdx + 5, Math.min(html.length, endIdx + 5 + 200));
      return new Response(JSON.stringify({
        handle: p.handle,
        found: true,
        block_offset: idx,
        block_length: block.length,
        context_before: before,
        block: block,
        context_after: after,
      }, null, 2), { headers: { "Content-Type": "application/json" } });
    }
    
    return new Response(JSON.stringify({
      handle: p.handle,
      length: html.length,
      full_html: html,
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
