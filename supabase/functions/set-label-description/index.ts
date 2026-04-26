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
async function gql(token, query, variables) {
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
  if (!resp.ok) throw new Error(`GQL error (${resp.status}): ${await resp.text()}`);
  return resp.json();
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
    const { label_text, product_types, size_patterns, dry_run } = await req.json();
    if (!label_text || !product_types || !size_patterns) {
      return new Response(JSON.stringify({
        error: "label_text, product_types, size_patterns required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const matchingVariants = [];
    // Collect all matching variants across all product types
    for (const ptype of product_types){
      let cursor = null;
      let hasNext = true;
      while(hasNext){
        const afterClause = cursor ? `, after: "${cursor}"` : "";
        const result = await gql(token, `{
          products(first: 50${afterClause}, query: "product_type:'${ptype}'") {
            edges { node { id title variants(first: 30) { edges { node { id title sku } } } } }
            pageInfo { hasNextPage endCursor }
          }
        }`);
        const edges = result?.data?.products?.edges ?? [];
        for (const pe of edges){
          const productTitle = pe.node.title;
          for (const ve of pe.node.variants?.edges ?? []){
            const vTitle = (ve.node.title || "").toLowerCase();
            // Must be bareroot
            if (!vTitle.includes("bareroot")) continue;
            // Must match at least one size pattern
            const matches = size_patterns.some((p)=>vTitle.includes(p.toLowerCase()));
            if (matches) {
              matchingVariants.push({
                gid: ve.node.id,
                title: ve.node.title,
                sku: ve.node.sku,
                product: productTitle
              });
            }
          }
        }
        hasNext = result?.data?.products?.pageInfo?.hasNextPage ?? false;
        cursor = result?.data?.products?.pageInfo?.endCursor ?? null;
      }
    }
    if (dry_run) {
      return new Response(JSON.stringify({
        dry_run: true,
        total_matching: matchingVariants.length,
        variants: matchingVariants
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Write metafield in batches of 25
    let written = 0;
    let errors = [];
    for(let i = 0; i < matchingVariants.length; i += 25){
      const batch = matchingVariants.slice(i, i + 25);
      const metafields = batch.map((v)=>({
          ownerId: v.gid,
          namespace: "product_data",
          key: "label_description",
          value: label_text,
          type: "single_line_text_field"
        }));
      const result = await gql(token, `
        mutation($metafields: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $metafields) {
            metafields { id }
            userErrors { field message }
          }
        }
      `, {
        metafields
      });
      const ue = result?.data?.metafieldsSet?.userErrors ?? [];
      if (ue.length > 0) {
        errors.push(...ue.map((e)=>e.message));
      } else {
        written += batch.length;
      }
    }
    return new Response(JSON.stringify({
      total_matching: matchingVariants.length,
      written,
      errors: errors.length > 0 ? errors : undefined
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: err.message
    }), {
      status: 500
    });
  }
});
