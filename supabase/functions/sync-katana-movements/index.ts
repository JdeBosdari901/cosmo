// sync-katana-movements — v2 (adds dry_run mode)
//
// Polls Katana inventory_movements since a stored bookmark, enriches affected
// variants with stock components, runs the policy decision tree (ported from
// sync-inventory-policy v15 including the v10 manual_override short-circuit),
// and pushes Shopify changes via fix-batch-deny.
//
// Runs in parallel with sync-inventory-policy (webhook) and reconcile-three-stage
// (4-hourly poll). Retirement of those two is a separate decision after this
// EF is observed working in production.
//
// Bookmark advancement: max(updated_at) + 1ms (endpoint is INCLUSIVE on
// updated_at_min, verified live 29 Apr 2026).
// Sort order: pages arrive DESCENDING; we sort ASCENDING after collection.
// Audit rows: written by fix-batch-deny only — this EF does NOT write its own.
// Soft cap: 100 unique variants per run; remainder picked up next tick.
// Dry-run: POST {"dry_run": true} skips the fix-batch-deny call and the
// bookmark advance — for testing without customer-facing side effects.
//
// Dependencies (verified 29 Apr 2026):
//   Tables: ef_state, katana_stock_sync, katana_products,
//           seasonal_selling_policy, workflow_health
//   EFs:    fix-batch-deny v8
//   Katana: GET /inventory_movements, /inventory, /variants/{id}

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// ── Configuration ──────────────────────────────────────────────────────────
const KATANA_TOKEN = "3bcf257c-4921-4108-bb6f-2a591c0976f0";
const GROVE_CROSS_LOCATION_ID = 162781;

const PAGE_SIZE = 250;
const MOVEMENTS_PAGE_DELAY_MS = 2500;
const ENRICHMENT_CALL_DELAY_MS = 1000;
const FIX_BATCH_DELAY_MS = 2000;
const FIX_BATCH_SIZE = 50;
const MAX_UNIQUE_VARIANTS_PER_RUN = 100;
const COLD_START_LOOKBACK_HOURS = 1;

const EF_SLUG = "sync-katana-movements";
const WORKFLOW_NAME = "Katana Movements Sync";
const EXPECTED_INTERVAL_MINUTES = 15;

// ── Types ──────────────────────────────────────────────────────────────────
type Movement = {
  id: number;
  variant_id: number;
  updated_at: string;
};

type SeasonRow = {
  start_month: number;
  end_month: number;
  presale_allowed: boolean;
  presale_start_month: number | null;
  presale_start_day: number | null;
};

type Decision = {
  sku: string;
  katana_variant_id: number;
  effectiveStock: number;
  inStock: number;
  expected: number;
  target: "CONTINUE" | "DENY";
  reason: string;
  knownPolicy: string | null;
  needsShopifyChange: boolean;
};

// ── Helpers ────────────────────────────────────────────────────────────────

/** Katana GET with 429 retry + exponential backoff. Mirrors reconcile-three-stage v9. */
async function katanaGet(url: string): Promise<Record<string, unknown>> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    const resp = await fetch(url, { headers: { Authorization: `Bearer ${KATANA_TOKEN}` } });
    if (resp.status === 429) {
      const wait = 5000 * Math.pow(2, attempt - 1);
      console.log(`429 attempt ${attempt}/3 — waiting ${wait}ms`);
      await new Promise((r) => setTimeout(r, wait));
      continue;
    }
    if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${await resp.text()}`);
    return await resp.json();
  }
  throw new Error(`429 after 3 retries: ${url}`);
}

function isInSellingWindow(startMonth: number, endMonth: number): boolean {
  const m = new Date().getMonth() + 1;
  if (startMonth <= endMonth) return m >= startMonth && m <= endMonth;
  return m >= startMonth || m <= endMonth;
}

function isPresaleOpen(presaleStartMonth: number, presaleStartDay: number): boolean {
  const today = new Date();
  const m = today.getMonth() + 1;
  const d = today.getDate();
  if (m > presaleStartMonth) return true;
  if (m === presaleStartMonth && d >= presaleStartDay) return true;
  return false;
}

/**
 * Policy decision tree — ported verbatim from sync-inventory-policy v15.
 * Includes the v10 manual_override short-circuit which prevents the see-saw
 * with reconcile-three-stage.
 */
function computePolicy(
  effectiveStock: number,
  expected: number,
  seasonPolicy: SeasonRow | null,
  manualOverride: string | null,
): { target: "CONTINUE" | "DENY"; reason: string } {
  let target: "CONTINUE" | "DENY";
  let reason: string;

  const stockBased: "CONTINUE" | "DENY" =
    (effectiveStock > 0 && expected > 0) ? "CONTINUE" : "DENY";

  if (seasonPolicy) {
    const inWindow = isInSellingWindow(seasonPolicy.start_month, seasonPolicy.end_month);
    if (inWindow) {
      target = stockBased;
      reason = `in_season | effective:${effectiveStock} expected:${expected}`;
    } else if (seasonPolicy.presale_start_month !== null) {
      const presaleDay = seasonPolicy.presale_start_day ?? 1;
      const presaleOpen = isPresaleOpen(seasonPolicy.presale_start_month, presaleDay);
      if (!presaleOpen) {
        target = "DENY";
        reason = `cooling_off | presale opens ${seasonPolicy.presale_start_month}/${presaleDay}`;
      } else {
        target = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
        reason = `presale_window | presale_allowed:${seasonPolicy.presale_allowed}`;
      }
    } else {
      target = seasonPolicy.presale_allowed ? "CONTINUE" : "DENY";
      reason = `presale_window_no_cooloff | presale_allowed:${seasonPolicy.presale_allowed}`;
    }
  } else {
    target = stockBased;
    reason = `no_seasonal_policy | effective:${effectiveStock} expected:${expected}`;
  }

  // v10: manual_override short-circuits the entire tree
  if (manualOverride === "CONTINUE" || manualOverride === "DENY") {
    const computed = target;
    const computedReason = reason;
    target = manualOverride;
    reason = `manual_override:${manualOverride} (computed would be ${computed}: ${computedReason})`;
  }

  return { target, reason };
}

// ── Main ───────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST required" }), { status: 405 });
  }

  // Parse optional dry_run flag from request body
  let dryRun = false;
  try {
    const body = await req.json();
    if (body && typeof body.dry_run === "boolean") dryRun = body.dry_run;
  } catch {
    // empty body or invalid JSON — fine, default false
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const log: string[] = [];
  const errors: string[] = [];
  const stats = {
    bookmark_from: "",
    bookmark_to: "",
    movements_pages: 0,
    movements_total: 0,
    unique_variants_seen: 0,
    unique_variants_processed: 0,
    enrichment_skipped: 0,
    policies_computed: 0,
    policies_changed: 0,
    fix_errors: 0,
    capped: false,
    dry_run: dryRun,
    would_have_changed: 0,
  };

  // ── 1. Read bookmark ─────────────────────────────────────────────────────
  const { data: stateRow } = await supabase
    .from("ef_state")
    .select("bookmark_value")
    .eq("ef_slug", EF_SLUG)
    .maybeSingle();

  const bookmark: string = stateRow?.bookmark_value
    ?? new Date(Date.now() - COLD_START_LOOKBACK_HOURS * 3600_000).toISOString();
  if (!stateRow?.bookmark_value) log.push(`Cold start — bookmark = ${bookmark}`);
  stats.bookmark_from = bookmark;

  // ── 2. Paginate inventory_movements ──────────────────────────────────────
  const movements: Movement[] = [];
  try {
    let page = 1;
    while (true) {
      const url = `https://api.katanamrp.com/v1/inventory_movements`
        + `?location_id=${GROVE_CROSS_LOCATION_ID}`
        + `&updated_at_min=${encodeURIComponent(bookmark)}`
        + `&limit=${PAGE_SIZE}&page=${page}`;
      const data = await katanaGet(url);
      const items = (data.data as Movement[]) ?? [];
      movements.push(...items);
      stats.movements_total += items.length;
      stats.movements_pages = page;
      if (items.length < PAGE_SIZE) break;
      page++;
      await new Promise((r) => setTimeout(r, MOVEMENTS_PAGE_DELAY_MS));
    }
    log.push(`Stage 1: ${stats.movements_pages} pages, ${stats.movements_total} movements`);
  } catch (e: unknown) {
    return await earlyExit(supabase, "failed", stats, log, errors,
      `Stage 1 (movements): ${e instanceof Error ? e.message : String(e)}`);
  }

  if (movements.length === 0) {
    return await earlyExit(supabase, "complete", stats, log, errors, "no_movements");
  }

  // ── 3. Sort ASC, dedup by variant_id, apply soft cap ─────────────────────
  movements.sort((a, b) => a.updated_at.localeCompare(b.updated_at));
  const maxUpdatedAtAll = movements[movements.length - 1].updated_at;

  // After sort, Map.set keeps the LAST entry per variant_id = most recent movement
  const variantToMovement = new Map<number, Movement>();
  for (const m of movements) variantToMovement.set(m.variant_id, m);
  let uniqueVariants = Array.from(variantToMovement.values());
  stats.unique_variants_seen = uniqueVariants.length;

  // Soft cap: if too many, take the OLDEST 100 so we make forward progress;
  // bookmark advances only to the cap boundary.
  let bookmarkAdvanceTo: string;
  if (uniqueVariants.length > MAX_UNIQUE_VARIANTS_PER_RUN) {
    uniqueVariants.sort((a, b) => a.updated_at.localeCompare(b.updated_at));
    uniqueVariants = uniqueVariants.slice(0, MAX_UNIQUE_VARIANTS_PER_RUN);
    bookmarkAdvanceTo = uniqueVariants[uniqueVariants.length - 1].updated_at;
    stats.capped = true;
    log.push(`Soft cap: processing ${MAX_UNIQUE_VARIANTS_PER_RUN} of ${stats.unique_variants_seen} unique variants`);
  } else {
    bookmarkAdvanceTo = maxUpdatedAtAll;
  }

  // ── 4. Enrich each unique variant ────────────────────────────────────────
  const decisions: Decision[] = [];

  for (const movement of uniqueVariants) {
    try {
      // 4a. Inventory lookup (Grove Cross row)
      const invData = await katanaGet(
        `https://api.katanamrp.com/v1/inventory?variant_id=${movement.variant_id}`
      );
      const groveRow = ((invData.data as Record<string, unknown>[]) ?? [])
        .find((r) => r.location_id === GROVE_CROSS_LOCATION_ID);
      if (!groveRow) {
        stats.enrichment_skipped++;
        await new Promise((r) => setTimeout(r, ENRICHMENT_CALL_DELAY_MS));
        continue;
      }
      const inStock   = parseFloat(String(groveRow.quantity_in_stock))  || 0;
      const committed = parseFloat(String(groveRow.quantity_committed)) || 0;
      const expected  = parseFloat(String(groveRow.quantity_expected))  || 0;
      const safety    = parseFloat(String(groveRow.safety_stock_level)) || 0;
      const effectiveStock = inStock + expected - committed - safety;

      await new Promise((r) => setTimeout(r, ENRICHMENT_CALL_DELAY_MS));

      // 4b. SKU lookup (in-line per brief §3 step 5 option a)
      const varData = await katanaGet(
        `https://api.katanamrp.com/v1/variants/${movement.variant_id}`
      );
      const sku: string | null = typeof varData.sku === "string" ? varData.sku : null;
      if (!sku || !sku.includes("-")) {
        stats.enrichment_skipped++;
        await new Promise((r) => setTimeout(r, ENRICHMENT_CALL_DELAY_MS));
        continue;
      }
      const skuPrefix = sku.split("-")[0];

      // 4c. Voucher exclusion
      const { data: kProduct } = await supabase
        .from("katana_products")
        .select("product_type")
        .eq("sku_prefix", skuPrefix)
        .maybeSingle();
      if (kProduct?.product_type === "voucher") {
        stats.enrichment_skipped++;
        await new Promise((r) => setTimeout(r, ENRICHMENT_CALL_DELAY_MS));
        continue;
      }

      // 4d. Seasonal policy + sync row
      const { data: seasonPolicy } = await supabase
        .from("seasonal_selling_policy")
        .select("start_month, end_month, presale_allowed, presale_start_month, presale_start_day")
        .eq("sku_prefix", skuPrefix)
        .maybeSingle();
      const { data: syncRow } = await supabase
        .from("katana_stock_sync")
        .select("shopify_inventory_policy, manual_override")
        .eq("sku", sku)
        .maybeSingle();

      const knownPolicy: string | null = syncRow?.shopify_inventory_policy ?? null;
      const manualOverride: string | null = syncRow?.manual_override ?? null;

      // 4e. Compute target policy
      const { target, reason } = computePolicy(
        effectiveStock, expected, seasonPolicy as SeasonRow | null, manualOverride
      );
      stats.policies_computed++;

      // 4f. Always upsert stock components (do NOT write shopify_inventory_policy here —
      // fix-batch-deny owns that column when it changes; otherwise we'd race)
      await supabase.from("katana_stock_sync").upsert({
        sku,
        katana_variant_id: movement.variant_id,
        effective_stock: effectiveStock,
        quantity_in_stock: inStock,
        quantity_expected: expected,
        last_checked_at: new Date().toISOString(),
      }, { onConflict: "sku" });

      decisions.push({
        sku, katana_variant_id: movement.variant_id,
        effectiveStock, inStock, expected,
        target, reason,
        knownPolicy,
        needsShopifyChange: knownPolicy !== target,
      });

      await new Promise((r) => setTimeout(r, ENRICHMENT_CALL_DELAY_MS));
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      errors.push(`enrichment variant_id=${movement.variant_id}: ${msg}`);
      // Continue with next variant — single-variant failure shouldn't kill the run
    }
  }
  stats.unique_variants_processed = decisions.length;

  // ── 5. Push Shopify changes via fix-batch-deny ───────────────────────────
  const toDeny = decisions.filter((d) => d.needsShopifyChange && d.target === "DENY").map((d) => d.sku);
  const toContinue = decisions.filter((d) => d.needsShopifyChange && d.target === "CONTINUE").map((d) => d.sku);
  stats.would_have_changed = toDeny.length + toContinue.length;
  const fixBatchUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/fix-batch-deny`;

  if (dryRun) {
    log.push(`DRY RUN: skipping fix-batch-deny — would have changed ${toDeny.length} DENY + ${toContinue.length} CONTINUE`);
  } else for (const [skus, policy] of [[toDeny, "DENY"], [toContinue, "CONTINUE"]] as [string[], string][]) {
    if (skus.length === 0) continue;
    for (let i = 0; i < skus.length; i += FIX_BATCH_SIZE) {
      const batch = skus.slice(i, i + FIX_BATCH_SIZE);
      try {
        const resp = await fetch(fixBatchUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          },
          body: JSON.stringify({
            skus: batch,
            target_policy: policy,
            reason: `${EF_SLUG}: ${stats.bookmark_from} → ${bookmarkAdvanceTo}`,
          }),
        });
        if (!resp.ok) throw new Error(`fix-batch-deny HTTP ${resp.status}: ${await resp.text()}`);
        const result = await resp.json();
        stats.policies_changed += result.changed ?? 0;
        stats.fix_errors += result.errors ?? 0;
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        errors.push(`fix-batch-deny ${policy} (batch from ${batch[0]}): ${msg}`);
        stats.fix_errors += batch.length;
      }
      if (batch.length >= FIX_BATCH_SIZE) {
        await new Promise((r) => setTimeout(r, FIX_BATCH_DELAY_MS));
      }
    }
  }
  log.push(`Stage 5: ${stats.policies_changed} changed, ${stats.fix_errors} errors`);

  // ── 6. Advance bookmark (+1ms; only on clean run) ────────────────────────
  const newBookmark = new Date(new Date(bookmarkAdvanceTo).getTime() + 1).toISOString();
  stats.bookmark_to = newBookmark;

  if (dryRun) {
    log.push(`DRY RUN: bookmark NOT advanced (would have advanced to ${newBookmark})`);
  } else if (errors.length === 0) {
    await supabase.from("ef_state").upsert({
      ef_slug: EF_SLUG,
      bookmark_value: newBookmark,
      bookmark_advanced_at: new Date().toISOString(),
      notes: `${stats.unique_variants_processed} processed, ${stats.policies_changed} changed`,
    }, { onConflict: "ef_slug" });
    log.push(`Bookmark advanced: ${stats.bookmark_from} → ${newBookmark}`);
  } else {
    log.push(`Bookmark NOT advanced — ${errors.length} errors. Stays at ${stats.bookmark_from}`);
  }

  // ── 7. Workflow health ───────────────────────────────────────────────────
  const now = new Date().toISOString();
  const healthRow = errors.length === 0
    ? { last_success_at: now }
    : { last_error_at: now, last_error_message: errors.slice(0, 3).join(" | ") };
  await supabase.from("workflow_health").upsert({
    workflow_id: EF_SLUG,
    workflow_name: WORKFLOW_NAME,
    expected_interval_minutes: EXPECTED_INTERVAL_MINUTES,
    ...healthRow,
  }, { onConflict: "workflow_id" });

  // ── 8. Return summary ────────────────────────────────────────────────────
  return new Response(JSON.stringify({
    status: errors.length === 0 ? "complete" : "complete_with_errors",
    stats,
    log,
    errors,
    more_pending: stats.capped,
    decisions: decisions.slice(0, 50),
  }), { headers: { "Content-Type": "application/json" } });
});

// ── Early-exit helper (used for no_movements and Stage 1 failure) ──────────
async function earlyExit(
  supabase: ReturnType<typeof createClient>,
  status: "complete" | "failed",
  stats: Record<string, unknown>,
  log: string[],
  errors: string[],
  reasonOrError: string,
): Promise<Response> {
  const now = new Date().toISOString();
  if (status === "complete") {
    log.push(`Exit: ${reasonOrError}`);
    await supabase.from("workflow_health").upsert({
      workflow_id: EF_SLUG,
      workflow_name: WORKFLOW_NAME,
      expected_interval_minutes: EXPECTED_INTERVAL_MINUTES,
      last_success_at: now,
    }, { onConflict: "workflow_id" });
  } else {
    errors.push(reasonOrError);
    await supabase.from("workflow_health").upsert({
      workflow_id: EF_SLUG,
      workflow_name: WORKFLOW_NAME,
      expected_interval_minutes: EXPECTED_INTERVAL_MINUTES,
      last_error_at: now,
      last_error_message: reasonOrError,
    }, { onConflict: "workflow_id" });
  }
  return new Response(
    JSON.stringify({ status, stats, log, errors }),
    { headers: { "Content-Type": "application/json" } }
  );
}
