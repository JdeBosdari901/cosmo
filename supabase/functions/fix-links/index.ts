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
  if (!resp.ok) throw new Error(`GraphQL error (${resp.status}): ${await resp.text()}`);
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
    const { operations } = await req.json();
    if (!operations || !Array.isArray(operations) || operations.length === 0) {
      return new Response(JSON.stringify({
        error: "operations array required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    const results = [];
    // Group operations by handle to avoid re-fetching
    const byHandle = new Map();
    for (const op of operations){
      if (!byHandle.has(op.handle)) byHandle.set(op.handle, []);
      byHandle.get(op.handle).push(op);
    }
    for (const [handle, ops] of byHandle){
      // Fetch collection with metafields
      const result = await gql(token, `{
        collectionByHandle(handle: "${handle}") {
          id
          descriptionHtml
          metafields(first: 20) {
            edges { node { id namespace key type value } }
          }
        }
      }`);
      const coll = result?.data?.collectionByHandle;
      if (!coll) {
        for (const op of ops)results.push({
          handle,
          find: op.find,
          replace: op.replace,
          status: "error",
          detail: "collection not found"
        });
        continue;
      }
      // Check descriptionHtml
      let descHtml = coll.descriptionHtml || "";
      let descChanged = false;
      for (const op of ops){
        if (descHtml.includes(op.find)) {
          descHtml = descHtml.split(op.find).join(op.replace);
          descChanged = true;
        }
      }
      if (descChanged) {
        const mut = await gql(token, `mutation($input: CollectionInput!) { collectionUpdate(input: $input) { collection { id } userErrors { field message } } }`, {
          input: {
            id: coll.id,
            descriptionHtml: descHtml
          }
        });
        const errs = mut?.data?.collectionUpdate?.userErrors;
        if (errs && errs.length > 0) {
          for (const op of ops)results.push({
            handle,
            find: op.find,
            replace: op.replace,
            status: "error",
            detail: JSON.stringify(errs)
          });
          continue;
        }
      }
      // Check all metafields
      const metafieldsToUpdate = [];
      for (const edge of coll.metafields.edges){
        const mf = edge.node;
        let val = mf.value || "";
        let changed = false;
        for (const op of ops){
          if (val.includes(op.find)) {
            val = val.split(op.find).join(op.replace);
            changed = true;
          }
        }
        if (changed) {
          metafieldsToUpdate.push({
            id: mf.id,
            namespace: mf.namespace,
            key: mf.key,
            type: mf.type,
            value: val
          });
        }
      }
      if (metafieldsToUpdate.length > 0) {
        const metafields = metafieldsToUpdate.map((mf)=>({
            ownerId: coll.id,
            namespace: mf.namespace,
            key: mf.key,
            value: mf.value,
            type: mf.type
          }));
        const setResult = await gql(token, `mutation($m: [MetafieldsSetInput!]!) { metafieldsSet(metafields: $m) { metafields { namespace key } userErrors { field message } } }`, {
          m: metafields
        });
        const setErrors = setResult?.data?.metafieldsSet?.userErrors;
        if (setErrors && setErrors.length > 0) {
          for (const op of ops)results.push({
            handle,
            find: op.find,
            replace: op.replace,
            status: "error",
            detail: JSON.stringify(setErrors)
          });
          continue;
        }
      }
      // Record results
      for (const op of ops){
        const foundInDesc = (coll.descriptionHtml || "").includes(op.find);
        const foundInMeta = coll.metafields.edges.some((e)=>(e.node.value || "").includes(op.find));
        if (foundInDesc || foundInMeta) {
          const locations = [];
          if (foundInDesc) locations.push("descriptionHtml");
          for (const e of coll.metafields.edges){
            if ((e.node.value || "").includes(op.find)) locations.push(`${e.node.namespace}.${e.node.key}`);
          }
          results.push({
            handle,
            find: op.find,
            replace: op.replace,
            status: "updated",
            detail: `Found in: ${locations.join(", ")}`
          });
        } else {
          results.push({
            handle,
            find: op.find,
            replace: op.replace,
            status: "not_found",
            detail: "substring not found in descriptionHtml or any metafield"
          });
        }
      }
    }
    return new Response(JSON.stringify({
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
      status: 500
    });
  }
});
