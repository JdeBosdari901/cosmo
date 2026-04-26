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
 * get-product v9
 * Added: variant_gid in variant response (enables metaobject updates referencing specific variants)
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
    const { product_id, handle, set_status, set_handle, set_body, set_metafields, create_redirect } = await req.json();
    if (create_redirect && !product_id && !handle) {
      const token = await getShopifyToken();
      const result = await shopifyGraphQL(token, `mutation($r: UrlRedirectInput!) { urlRedirectCreate(urlRedirect: $r) { urlRedirect { id path target } userErrors { field message } } }`, {
        r: {
          path: create_redirect.from,
          target: create_redirect.to
        }
      });
      const userErrors = result?.data?.urlRedirectCreate?.userErrors;
      if (userErrors?.length > 0) return new Response(JSON.stringify({
        error: "Redirect creation failed",
        userErrors
      }), {
        status: 422
      });
      const redirect = result?.data?.urlRedirectCreate?.urlRedirect;
      return new Response(JSON.stringify({
        redirect_created: true,
        from: redirect?.path,
        to: redirect?.target
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    if (!product_id && !handle) return new Response(JSON.stringify({
      error: "Either product_id or handle is required"
    }), {
      status: 400
    });
    const token = await getShopifyToken();
    let productGid;
    let productData;
    const variantFields = `id title sku price inventoryPolicy inventoryQuantity selectedOptions { name value } metafields(first: 250) { edges { node { namespace key value type } } }`;
    if (product_id) {
      productGid = `gid://shopify/Product/${product_id}`;
      const result = await shopifyGraphQL(token, `query($id: ID!) { product(id: $id) { id handle title productType tags status descriptionHtml seo { title description } metafields(first: 10) { edges { node { namespace key value type } } } variants(first: 20) { edges { node { ${variantFields} } } } } }`, {
        id: productGid
      });
      productData = result?.data?.product;
    } else {
      const result = await shopifyGraphQL(token, `{ products(first: 1, query: "handle:${handle}") { edges { node { id handle title productType tags status descriptionHtml seo { title description } metafields(first: 10) { edges { node { namespace key value type } } } variants(first: 20) { edges { node { ${variantFields} } } } } } } }`);
      productData = result?.data?.products?.edges?.[0]?.node;
    }
    if (!productData) return new Response(JSON.stringify({
      error: "Product not found",
      lookup: product_id ? `id:${product_id}` : `handle:${handle}`
    }), {
      status: 404
    });
    productGid = productData.id;
    let productUpdateResult = null;
    if (set_status || set_handle || set_body !== undefined) {
      const productInput = {
        id: productGid
      };
      if (set_status) {
        const validStatuses = [
          'ACTIVE',
          'DRAFT',
          'ARCHIVED'
        ];
        const upperStatus = set_status.toUpperCase();
        if (!validStatuses.includes(upperStatus)) return new Response(JSON.stringify({
          error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
        }), {
          status: 400
        });
        productInput.status = upperStatus;
      }
      if (set_handle) productInput.handle = set_handle;
      if (set_body !== undefined) productInput.descriptionHtml = set_body;
      const updateResult = await shopifyGraphQL(token, `mutation($p: ProductInput!) { productUpdate(input: $p) { product { id handle status descriptionHtml } userErrors { field message } } }`, {
        p: productInput
      });
      const userErrors = updateResult?.data?.productUpdate?.userErrors;
      if (userErrors?.length > 0) {
        productUpdateResult = {
          error: "Product update failed",
          userErrors
        };
      } else {
        const updated = updateResult?.data?.productUpdate?.product;
        productUpdateResult = {
          success: true
        };
        if (set_status) productData.status = updated?.status;
        if (set_handle) productData.handle = updated?.handle;
        if (set_body !== undefined) {
          productData.descriptionHtml = updated?.descriptionHtml;
          productUpdateResult.body_updated = true;
          productUpdateResult.body_length = updated?.descriptionHtml?.length ?? 0;
        }
      }
    }
    let metafieldsResult = null;
    if (set_metafields && Array.isArray(set_metafields) && set_metafields.length > 0) {
      const metafields = set_metafields.map((mf)=>({
          ownerId: productGid,
          namespace: mf.namespace,
          key: mf.key,
          value: mf.value,
          type: mf.type
        }));
      const setResult = await shopifyGraphQL(token, `mutation($m: [MetafieldsSetInput!]!) { metafieldsSet(metafields: $m) { metafields { namespace key value } userErrors { field message } } }`, {
        m: metafields
      });
      const setErrors = setResult?.data?.metafieldsSet?.userErrors;
      if (setErrors?.length > 0) {
        metafieldsResult = {
          error: "Metafield update failed",
          userErrors: setErrors
        };
      } else {
        metafieldsResult = {
          success: true,
          updated: (setResult?.data?.metafieldsSet?.metafields ?? []).map((mf)=>`${mf.namespace}::${mf.key}`)
        };
      }
    }
    let redirectResult = null;
    if (create_redirect) {
      const rdResult = await shopifyGraphQL(token, `mutation($r: UrlRedirectInput!) { urlRedirectCreate(urlRedirect: $r) { urlRedirect { id path target } userErrors { field message } } }`, {
        r: {
          path: create_redirect.from,
          target: create_redirect.to
        }
      });
      const rdErrors = rdResult?.data?.urlRedirectCreate?.userErrors;
      if (rdErrors?.length > 0) {
        redirectResult = {
          error: "Redirect creation failed",
          userErrors: rdErrors
        };
      } else {
        const rd = rdResult?.data?.urlRedirectCreate?.urlRedirect;
        redirectResult = {
          success: true,
          from: rd?.path,
          to: rd?.target
        };
      }
    }
    const response = {
      shopify_gid: productData.id,
      handle: productData.handle,
      title: productData.title,
      product_type: productData.productType,
      tags: productData.tags,
      status: productData.status,
      seo: productData.seo,
      body_html_length: productData.descriptionHtml?.length ?? 0,
      variants: (productData.variants?.edges ?? []).map((e)=>{
        const node = e.node;
        const result = {
          variant_gid: node.id,
          title: node.title,
          sku: node.sku,
          price: node.price
        };
        const mfEdges = node.metafields?.edges ?? [];
        if (mfEdges.length > 0) result.metafields = mfEdges.map((me)=>({
            namespace: me.node.namespace,
            key: me.node.key,
            value: me.node.value,
            type: me.node.type
          }));
        return result;
      })
    };
    if (productUpdateResult) response.product_update = productUpdateResult;
    if (metafieldsResult) response.metafields_update = metafieldsResult;
    if (redirectResult) response.redirect = redirectResult;
    return new Response(JSON.stringify(response), {
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
