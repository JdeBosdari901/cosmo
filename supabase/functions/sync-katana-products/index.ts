import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const KATANA_TOKEN = '3bcf257c-4921-4108-bb6f-2a591c0976f0';
const PAGE_SIZE = 100;
const PAGE_DELAY_MS = 2000;
const CATEGORY_TYPE_MAP = {
  'Bundles': 'bundle',
  'Bundle': 'bundle',
  'Gifts': 'gift',
  'Gift': 'gift',
  'Gift Cards': 'gift',
  'Vouchers': 'voucher',
  'Voucher': 'voucher',
  'Sundries': 'sundry',
  'Sundry': 'sundry',
  'Packaging': 'sundry',
  'Accessories': 'sundry'
};
function mapProductType(categoryName) {
  if (!categoryName) return 'plant';
  return CATEGORY_TYPE_MAP[categoryName] ?? 'plant';
}
function deriveSkuPrefix(variants) {
  if (!variants || variants.length === 0) return null;
  const sku = variants[0].sku;
  if (!sku) return null;
  const parts = sku.split('-');
  return parts.length > 1 ? parts.slice(0, -1).join('-') : sku;
}
Deno.serve(async (req)=>{
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({
      error: 'POST required'
    }), {
      status: 405
    });
  }
  const supabase = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
  const log = [];
  const errors = [];
  let totalFetched = 0;
  let totalUpserted = 0;
  let totalArchived = 0;
  const now = new Date().toISOString();
  try {
    let page = 1;
    const seenIds = [];
    while(true){
      const resp = await fetch(`https://api.katanamrp.com/v1/products?limit=${PAGE_SIZE}&page=${page}`, {
        headers: {
          Authorization: `Bearer ${KATANA_TOKEN}`
        }
      });
      if (!resp.ok) throw new Error(`Katana API HTTP ${resp.status} on page ${page}`);
      const body = await resp.json();
      const products = body.data ?? [];
      totalFetched += products.length;
      const rows = products.map((p)=>{
        const variants = p.variants ?? [];
        const isActive = !p.archived_at && !p.deleted_at;
        if (isActive) seenIds.push(p.id);
        return {
          katana_product_id: p.id,
          katana_name: p.name,
          product_type: mapProductType(p.category_name),
          sku_prefix: deriveSkuPrefix(variants),
          variant_count: variants.length,
          katana_active: isActive,
          katana_last_seen: now
        };
      });
      if (rows.length > 0) {
        const { error: upsertErr } = await supabase.from('katana_products').upsert(rows, {
          onConflict: 'katana_product_id',
          ignoreDuplicates: false
        });
        if (upsertErr) throw new Error(`Upsert page ${page}: ${upsertErr.message}`);
        totalUpserted += rows.length;
      }
      if (products.length < PAGE_SIZE) break;
      page++;
      await new Promise((r)=>setTimeout(r, PAGE_DELAY_MS));
    }
    log.push(`Fetched ${totalFetched} products, upserted ${totalUpserted}`);
    // Mark products not seen in API as inactive
    if (seenIds.length > 0) {
      const { error: archiveErr } = await supabase.from('katana_products').update({
        katana_active: false
      }).eq('katana_active', true).not('katana_product_id', 'in', `(${seenIds.join(',')})`);
      if (archiveErr) {
        errors.push(`Archive stale: ${archiveErr.message}`);
      } else {
        log.push(`Marked stale products inactive`);
        totalArchived = 1; // approximate
      }
    }
    // Update workflow_health
    const { error: wfErr } = await supabase.from('workflow_health').upsert({
      workflow_id: 'sync-katana-products',
      workflow_name: 'Katana Product Sync',
      last_success_at: now,
      expected_interval_minutes: 1440
    }, {
      onConflict: 'workflow_id'
    });
    if (wfErr) errors.push(`workflow_health: ${wfErr.message}`);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    errors.push(msg);
    // Record error in workflow_health
    await supabase.from('workflow_health').upsert({
      workflow_id: 'sync-katana-products',
      workflow_name: 'Katana Product Sync',
      last_error_at: now,
      last_error_message: msg,
      expected_interval_minutes: 1440
    }, {
      onConflict: 'workflow_id'
    });
  }
  return new Response(JSON.stringify({
    status: errors.length === 0 ? 'ok' : 'error',
    totalFetched,
    totalUpserted,
    log,
    errors
  }), {
    headers: {
      'Content-Type': 'application/json'
    }
  });
});
