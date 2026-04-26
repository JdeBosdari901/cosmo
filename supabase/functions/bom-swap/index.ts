import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * bom-swap v3 — Three-system BOM component swap
 * v3: CORS headers on ALL responses per Supabase docs, not just OPTIONS.
 */ const KATANA_API = "https://api.katanamrp.com/v1";
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const API_DELAY = 1500;
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
};
function jsonResp(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}
function delay(ms) {
  return new Promise((r)=>setTimeout(r, ms));
}
function extractPrefix(sku) {
  const lastHyphen = sku.lastIndexOf("-");
  return lastHyphen > 0 ? sku.substring(0, lastHyphen) : sku;
}
async function katanaFetch(path, method = "GET", body) {
  for(let attempt = 1; attempt <= 3; attempt++){
    const opts = {
      method,
      headers: {
        Authorization: `Bearer ${KATANA_TOKEN}`,
        "Content-Type": "application/json"
      }
    };
    if (body) opts.body = JSON.stringify(body);
    const resp = await fetch(`${KATANA_API}${path}`, opts);
    if (resp.status === 429) {
      await delay(5000 * Math.pow(2, attempt - 1));
      continue;
    }
    if (resp.status === 204) return null;
    const text = await resp.text();
    if (!resp.ok) throw new Error(`Katana ${method} ${path}: ${resp.status} ${text.slice(0, 300)}`);
    return JSON.parse(text);
  }
  throw new Error(`Katana 429 after 3 retries: ${method} ${path}`);
}
async function callMetaobjects(payload) {
  const sbUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resp = await fetch(`${sbUrl}/functions/v1/get-metaobjects`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`get-metaobjects ${resp.status}: ${text.slice(0, 500)}`);
  }
  return resp.json();
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return jsonResp({
      error: "POST required"
    }, 405);
  }
  const body = await req.json();
  const { action } = body;
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  try {
    if (action === "lookup") return await handleLookup(supabase, body);
    else if (action === "swap") return await handleSwap(supabase, body);
    else return jsonResp({
      error: "action must be 'lookup' or 'swap'"
    }, 400);
  } catch (e) {
    return jsonResp({
      error: e instanceof Error ? e.message : String(e)
    }, 500);
  }
});
async function handleLookup(supabase, body) {
  const { pack_sku } = body;
  if (!pack_sku) return jsonResp({
    error: "pack_sku required"
  }, 400);
  const upperSku = pack_sku.toUpperCase();
  const { data: syncRow, error: syncErr } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", upperSku).maybeSingle();
  if (syncErr || !syncRow) return jsonResp({
    error: `Pack SKU '${upperSku}' not found in stock sync`
  }, 404);
  const packVariantId = syncRow.katana_variant_id;
  const bomResp = await katanaFetch(`/bom_rows?product_variant_id=${packVariantId}`);
  const bomRows = bomResp?.data ?? bomResp;
  if (!Array.isArray(bomRows) || bomRows.length === 0) return jsonResp({
    error: `No BOM rows found in Katana for variant ${packVariantId}`
  }, 404);
  const ingredientVids = bomRows.map((r)=>r.ingredient_variant_id);
  const { data: ingredientSyncs } = await supabase.from("katana_stock_sync").select("sku, katana_variant_id").in("katana_variant_id", ingredientVids);
  const vidToSku = new Map((ingredientSyncs ?? []).map((s)=>[
      s.katana_variant_id,
      s.sku
    ]));
  const { data: pbRows } = await supabase.from("product_bom").select("ingredient_sku, ingredient_katana_product_id, quantity").eq("variant_sku", upperSku);
  const productIds = [
    ...new Set((pbRows ?? []).map((r)=>r.ingredient_katana_product_id).filter(Boolean))
  ];
  let pidToName = new Map();
  if (productIds.length > 0) {
    const { data: kpRows } = await supabase.from("katana_products").select("katana_product_id, katana_name").in("katana_product_id", productIds);
    pidToName = new Map((kpRows ?? []).map((k)=>[
        k.katana_product_id,
        k.katana_name
      ]));
  }
  const skuToPb = new Map((pbRows ?? []).map((p)=>[
      p.ingredient_sku,
      p
    ]));
  const components = bomRows.map((row)=>{
    const vid = row.ingredient_variant_id;
    const sku = vidToSku.get(vid) ?? `variant_${vid}`;
    const pb = skuToPb.get(sku);
    const productName = pb ? pidToName.get(pb.ingredient_katana_product_id) ?? "" : "";
    return {
      bom_row_id: row.id,
      product_item_id: row.product_item_id,
      ingredient_variant_id: vid,
      ingredient_sku: sku,
      product_name: productName,
      quantity: row.quantity
    };
  });
  return jsonResp({
    pack_sku: upperSku,
    pack_variant_id: packVariantId,
    components
  });
}
async function handleSwap(supabase, body) {
  const { pack_sku, old_sku, new_sku } = body;
  if (!pack_sku || !old_sku || !new_sku) return jsonResp({
    error: "pack_sku, old_sku, new_sku required"
  }, 400);
  const upperPack = pack_sku.toUpperCase();
  const upperOld = old_sku.toUpperCase();
  const upperNew = new_sku.toUpperCase();
  const results = {};
  const errors = [];
  const { data: packSync } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", upperPack).maybeSingle();
  if (!packSync) return jsonResp({
    error: `Pack SKU '${upperPack}' not found`
  }, 404);
  const packVariantId = packSync.katana_variant_id;
  const bomResp = await katanaFetch(`/bom_rows?product_variant_id=${packVariantId}`);
  const bomRows = bomResp?.data ?? bomResp ?? [];
  const { data: oldSync } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", upperOld).maybeSingle();
  if (!oldSync) return jsonResp({
    error: `Old SKU '${upperOld}' not found in stock sync`
  }, 404);
  const oldRow = bomRows.find((r)=>r.ingredient_variant_id === oldSync.katana_variant_id);
  if (!oldRow) return jsonResp({
    error: `'${upperOld}' not in BOM for '${upperPack}'`
  }, 404);
  const quantity = oldRow.quantity;
  const productItemId = oldRow.product_item_id;
  const { data: newSync } = await supabase.from("katana_stock_sync").select("katana_variant_id").eq("sku", upperNew).maybeSingle();
  let newVariantId;
  if (newSync) {
    newVariantId = newSync.katana_variant_id;
  } else {
    await delay(API_DELAY);
    const varResp = await katanaFetch(`/variants?sku=${encodeURIComponent(upperNew)}`);
    const variants = varResp?.data ?? varResp;
    if (!Array.isArray(variants) || variants.length === 0) return jsonResp({
      error: `New SKU '${upperNew}' not found in Katana`
    }, 404);
    newVariantId = variants[0].id;
  }
  const newPrefix = extractPrefix(upperNew);
  const { data: kpRow } = await supabase.from("katana_products").select("katana_product_id, katana_name").eq("sku_prefix", newPrefix).maybeSingle();
  const newKatanaProductId = kpRow?.katana_product_id ?? null;
  const newProductName = kpRow?.katana_name ?? upperNew;
  try {
    await katanaFetch(`/bom_rows/${oldRow.id}`, "DELETE");
    results.katana_delete = {
      bom_row_id: oldRow.id,
      sku: upperOld,
      status: "deleted"
    };
  } catch (e) {
    return jsonResp({
      error: "Katana DELETE failed, swap aborted",
      detail: e.message
    }, 500);
  }
  await delay(API_DELAY);
  try {
    await katanaFetch("/bom_rows", "POST", {
      product_item_id: productItemId,
      product_variant_id: packVariantId,
      ingredient_variant_id: newVariantId,
      quantity
    });
    results.katana_create = {
      new_variant_id: newVariantId,
      sku: upperNew,
      quantity,
      status: "created"
    };
  } catch (e) {
    return jsonResp({
      error: "CRITICAL: Old BOM row deleted but new row failed. Manual fix required.",
      detail: e.message,
      deleted_row: {
        bom_row_id: oldRow.id,
        product_item_id: productItemId,
        ingredient_variant_id: oldSync.katana_variant_id,
        quantity
      },
      intended_new: {
        ingredient_variant_id: newVariantId,
        quantity
      }
    }, 500);
  }
  try {
    const packGql = await callMetaobjects({
      graphql: `{ productVariants(first: 1, query: "sku:'${upperPack}'") { edges { node { id sku metafield(namespace: \"custom\", key: \"bundle_items\") { value type } } } } }`
    });
    const edges = packGql?.data?.productVariants?.edges;
    const packVariant = edges?.[0]?.node;
    const metafieldValue = packVariant?.metafield?.value;
    if (!metafieldValue) {
      results.shopify = {
        skipped: true,
        reason: "No bundle_items metafield"
      };
    } else {
      const metaobjectGids = JSON.parse(metafieldValue);
      if (metaobjectGids.length === 0) {
        results.shopify = {
          skipped: true,
          reason: "Empty bundle_items"
        };
      } else {
        await delay(500);
        const moResp = await callMetaobjects({
          ids: metaobjectGids
        });
        const moData = moResp?.data;
        await delay(500);
        const oldGql = await callMetaobjects({
          graphql: `{ productVariants(first: 1, query: "sku:'${upperOld}'") { edges { node { id sku } } } }`
        });
        const oldEdges = oldGql?.data?.productVariants?.edges;
        const oldShopifyGid = oldEdges?.[0]?.node?.id;
        let matchedMoId = null;
        if (oldShopifyGid && moData) {
          for(let i = 0; i < metaobjectGids.length; i++){
            const mo = moData[`node${i}`];
            const fields = mo?.fields;
            if (fields) {
              const vf = fields.find((f)=>f.key === "variant");
              if (vf?.value === oldShopifyGid) {
                matchedMoId = mo.id;
                break;
              }
            }
          }
        }
        if (!matchedMoId) {
          results.shopify = {
            skipped: true,
            reason: "Could not match old ingredient to Metaobject"
          };
        } else {
          await delay(500);
          const newGql = await callMetaobjects({
            graphql: `{ productVariants(first: 1, query: "sku:'${upperNew}'") { edges { node { id sku title } } } }`
          });
          const newEdges = newGql?.data?.productVariants?.edges;
          const newShopifyGid = newEdges?.[0]?.node?.id;
          if (!newShopifyGid) {
            results.shopify = {
              skipped: true,
              reason: `New SKU '${upperNew}' not in Shopify`
            };
          } else {
            const grading = upperNew.includes("-") ? upperNew.split("-").pop() : "";
            const baseName = newProductName.replace(/ Hedge Plants$/i, "").replace(/ Plants$/i, "");
            const displayName = `${baseName} ${grading} x${quantity}`;
            await delay(500);
            const updateResp = await callMetaobjects({
              update_metaobject: {
                id: matchedMoId,
                fields: [
                  {
                    key: "name",
                    value: displayName
                  },
                  {
                    key: "qty",
                    value: String(quantity)
                  },
                  {
                    key: "variant",
                    value: newShopifyGid
                  }
                ]
              }
            });
            const ud = updateResp?.data?.metaobjectUpdate;
            const ue = ud?.userErrors;
            results.shopify = {
              updated: true,
              metaobject_id: matchedMoId,
              new_name: displayName,
              new_variant_gid: newShopifyGid,
              user_errors: ue?.length ? ue : undefined
            };
          }
        }
      }
    }
  } catch (e) {
    errors.push(`Shopify: ${e.message}`);
    results.shopify = {
      error: e.message
    };
  }
  try {
    const { data: updatedRows, error: updErr } = await supabase.from("product_bom").update({
      ingredient_sku: upperNew,
      ingredient_sku_prefix: newPrefix,
      ingredient_katana_product_id: newKatanaProductId,
      updated_at: new Date().toISOString()
    }).eq("variant_sku", upperPack).eq("ingredient_sku", upperOld).select("variant_sku, ingredient_sku, quantity");
    if (updErr) throw new Error(updErr.message);
    results.supabase = {
      updated: true,
      rows: updatedRows
    };
  } catch (e) {
    errors.push(`Supabase: ${e.message}`);
    results.supabase = {
      error: e.message
    };
  }
  try {
    await delay(API_DELAY);
    const vr = await katanaFetch(`/bom_rows?product_variant_id=${packVariantId}`);
    const vRows = vr?.data ?? vr ?? [];
    results.verification = {
      katana_bom_count: vRows.length,
      contains_new: vRows.some((r)=>r.ingredient_variant_id === newVariantId),
      does_not_contain_old: !vRows.some((r)=>r.ingredient_variant_id === oldSync.katana_variant_id)
    };
  } catch (e) {
    errors.push(`Verification: ${e.message}`);
  }
  return jsonResp({
    status: errors.length === 0 ? "complete" : "complete_with_errors",
    pack_sku: upperPack,
    old_sku: upperOld,
    new_sku: upperNew,
    quantity,
    new_product_name: newProductName,
    results,
    errors: errors.length > 0 ? errors : undefined
  });
}
