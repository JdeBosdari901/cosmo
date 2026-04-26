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
      Accept: "application/json"
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
const BATCH_SIZE = 25;
/**
 * update-variants v3
 *
 * Operations:
 *   set_metafield   — apply one metafield to N variants (unchanged)
 *   enable_tracking — enable inventory tracking on N variants (v3)
 *
 * v3 change (17 April 2026):
 *   Fixed mutation variable type: InventoryItemUpdateInput → InventoryItemInput.
 *   The 2026-01 Shopify API uses InventoryItemInput for inventoryItemUpdate.
 *   The v1 (and initial v2) type was wrong — mutations were failing with
 *   top-level GraphQL errors. v1 silently reported success. v2 caught the
 *   error via the top-level-errors gate. v3 uses the correct type.
 *
 *   4 success gates from v2 retained:
 *     1. No top-level GraphQL errors
 *     2. No userErrors
 *     3. Mutation-returned inventoryItem.tracked === true
 *     4. Independent post-mutation verify query returns tracked: true
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
    const payload = await req.json();
    const { operation, variants } = payload;
    if (!operation) {
      return new Response(JSON.stringify({
        error: "Missing 'operation' field",
        supported: [
          "set_metafield",
          "enable_tracking"
        ]
      }), {
        status: 400
      });
    }
    if (!Array.isArray(variants) || variants.length === 0) {
      return new Response(JSON.stringify({
        error: "'variants' must be a non-empty array of variant GIDs"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    if (operation === "set_metafield") {
      const { metafield } = payload;
      if (!metafield?.namespace || !metafield?.key || metafield?.value === undefined) {
        return new Response(JSON.stringify({
          error: "'metafield' must include namespace, key, and value"
        }), {
          status: 400
        });
      }
      const mfType = metafield.type || "single_line_text_field";
      let succeeded = 0;
      let failed = 0;
      const errors = [];
      for(let i = 0; i < variants.length; i += BATCH_SIZE){
        const batch = variants.slice(i, i + BATCH_SIZE);
        const metafields = batch.map((variantGid)=>({
            ownerId: variantGid,
            namespace: metafield.namespace,
            key: metafield.key,
            value: String(metafield.value),
            type: mfType
          }));
        const result = await shopifyGraphQL(token, `mutation($m: [MetafieldsSetInput!]!) {
            metafieldsSet(metafields: $m) {
              metafields { id namespace key }
              userErrors { field message }
            }
          }`, {
          m: metafields
        });
        const userErrors = result?.data?.metafieldsSet?.userErrors ?? [];
        if (userErrors.length > 0) {
          failed += batch.length;
          for (const ue of userErrors){
            errors.push({
              variant: ue.field?.join(".") ?? "unknown",
              message: ue.message
            });
          }
        } else {
          succeeded += batch.length;
        }
      }
      return new Response(JSON.stringify({
        operation: "set_metafield",
        metafield: `${metafield.namespace}::${metafield.key}`,
        value: metafield.value,
        total: variants.length,
        succeeded,
        failed,
        errors: errors.length > 0 ? errors : undefined
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    if (operation === "enable_tracking") {
      let succeeded = 0;
      let failed = 0;
      let already_tracked = 0;
      const errors = [];
      const results = [];
      const invItemByVariant = new Map();
      for(let i = 0; i < variants.length; i += BATCH_SIZE){
        const batch = variants.slice(i, i + BATCH_SIZE);
        const fragments = batch.map((gid, idx)=>`v${idx}: node(id: "${gid}") { ... on ProductVariant { id sku inventoryItem { id tracked } } }`).join("\n");
        const lookupResult = await shopifyGraphQL(token, `{ ${fragments} }`);
        if (lookupResult.errors && Array.isArray(lookupResult.errors) && lookupResult.errors.length > 0) {
          for (const variantGid of batch){
            failed++;
            errors.push({
              variant: variantGid,
              message: "Lookup top-level GraphQL error",
              detail: lookupResult.errors
            });
            results.push({
              variant: variantGid,
              sku: "unknown",
              status: "lookup_error"
            });
          }
          continue;
        }
        for(let idx = 0; idx < batch.length; idx++){
          const variantData = lookupResult?.data?.[`v${idx}`];
          const variantGid = batch[idx];
          if (!variantData) {
            failed++;
            errors.push({
              variant: variantGid,
              message: "Variant not found"
            });
            results.push({
              variant: variantGid,
              sku: "unknown",
              status: "not_found"
            });
            continue;
          }
          if (!variantData.inventoryItem?.id) {
            failed++;
            errors.push({
              variant: variantGid,
              message: "Variant has no inventoryItem"
            });
            results.push({
              variant: variantGid,
              sku: variantData.sku || "unknown",
              status: "no_inventory_item"
            });
            continue;
          }
          invItemByVariant.set(variantGid, {
            invItemId: variantData.inventoryItem.id,
            sku: variantData.sku || "unknown",
            tracked: !!variantData.inventoryItem.tracked
          });
        }
      }
      for (const [variantGid, info] of invItemByVariant.entries()){
        if (info.tracked) {
          already_tracked++;
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "already_tracked",
            tracked_after: true
          });
          continue;
        }
        const updateResult = await shopifyGraphQL(token, `mutation($id: ID!, $input: InventoryItemInput!) {
            inventoryItemUpdate(id: $id, input: $input) {
              inventoryItem { id tracked updatedAt }
              userErrors { field message }
            }
          }`, {
          id: info.invItemId,
          input: {
            tracked: true
          }
        });
        if (updateResult.errors && Array.isArray(updateResult.errors) && updateResult.errors.length > 0) {
          failed++;
          errors.push({
            variant: variantGid,
            sku: info.sku,
            message: "Top-level GraphQL error on mutation",
            detail: updateResult.errors
          });
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "top_level_error",
            tracked_after: null
          });
          continue;
        }
        const ue = updateResult?.data?.inventoryItemUpdate?.userErrors ?? [];
        if (ue.length > 0) {
          failed++;
          errors.push({
            variant: variantGid,
            sku: info.sku,
            message: ue[0].message,
            detail: ue
          });
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "user_error",
            tracked_after: null
          });
          continue;
        }
        const returnedItem = updateResult?.data?.inventoryItemUpdate?.inventoryItem;
        if (!returnedItem || returnedItem.tracked !== true) {
          failed++;
          errors.push({
            variant: variantGid,
            sku: info.sku,
            message: "Mutation returned no error but inventoryItem.tracked is not true",
            detail: returnedItem
          });
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "silent_no_op",
            tracked_after: returnedItem?.tracked ?? null
          });
          continue;
        }
        const verifyResult = await shopifyGraphQL(token, `query($id: ID!) { node(id: $id) { ... on InventoryItem { id tracked } } }`, {
          id: info.invItemId
        });
        if (verifyResult.errors && Array.isArray(verifyResult.errors) && verifyResult.errors.length > 0) {
          failed++;
          errors.push({
            variant: variantGid,
            sku: info.sku,
            message: "Verify query top-level error",
            detail: verifyResult.errors
          });
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "verify_error",
            tracked_after: null
          });
          continue;
        }
        const verifiedTracked = !!verifyResult?.data?.node?.tracked;
        if (!verifiedTracked) {
          failed++;
          errors.push({
            variant: variantGid,
            sku: info.sku,
            message: "Independent verify query says tracked is still false after mutation"
          });
          results.push({
            variant: variantGid,
            sku: info.sku,
            status: "verify_failed",
            tracked_after: false
          });
          continue;
        }
        succeeded++;
        results.push({
          variant: variantGid,
          sku: info.sku,
          status: "tracking_enabled",
          tracked_after: true
        });
      }
      return new Response(JSON.stringify({
        operation: "enable_tracking",
        version: "v3",
        total: variants.length,
        succeeded,
        already_tracked,
        failed,
        errors: errors.length > 0 ? errors : undefined,
        results
      }), {
        status: 200,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    return new Response(JSON.stringify({
      error: `Unknown operation: ${operation}`,
      supported: [
        "set_metafield",
        "enable_tracking"
      ]
    }), {
      status: 400
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({
      error: message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
});
