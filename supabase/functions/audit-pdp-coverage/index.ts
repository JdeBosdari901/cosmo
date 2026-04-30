import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_GRAPHQL_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01/graphql.json`;
const SHOPIFY_TOKEN_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/oauth/access_token`;

const BULK_QUERY = `{
  products(query: "status:active OR status:draft") {
    edges {
      node {
        __typename
        id
        handle
        title
        status
        productType
        tags
        descriptionHtml
        featuredMedia { id }
        media(first: 100) {
          edges {
            node {
              __typename
              id
            }
          }
        }
        metafields(first: 100) {
          edges {
            node {
              __typename
              id
              namespace
              key
            }
          }
        }
      }
    }
  }
}`;

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

async function submitBulkOp(token: string) {
  const mutation = `mutation { bulkOperationRunQuery(query: ${JSON.stringify(BULK_QUERY)}) { bulkOperation { id status } userErrors { field message } } }`;
  const result = await gql(token, mutation);
  return result?.data?.bulkOperationRunQuery;
}

async function pollBulkOp(token: string, opId: string) {
  const query = `query { bulkOperation(id: "${opId}") { id status errorCode objectCount rootObjectCount url completedAt } }`;
  const result = await gql(token, query);
  return result?.data?.bulkOperation;
}

async function downloadJSONL(url: string): Promise<string> {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`Download failed (${resp.status})`);
  return resp.text();
}

function parseAndAggregate(jsonl: string) {
  const lines = jsonl.split("\n").filter((l) => l.trim());
  const products = new Map<string, any>();
  for (const line of lines) {
    let obj: any;
    try { obj = JSON.parse(line); } catch { continue; }
    if (obj.handle !== undefined && obj.title !== undefined) {
      const desc = obj.descriptionHtml || "";
      products.set(obj.id, {
        id: obj.id, handle: obj.handle, title: obj.title, status: obj.status,
        productType: obj.productType, tags: obj.tags || [],
        bodyHtmlLength: desc.length, descriptionHtml: desc,
        hasFeaturedMedia: !!obj.featuredMedia,
        mediaCount: 0, metafieldCount: 0, metafieldKeys: [] as string[],
      });
    } else if (obj.namespace !== undefined && obj.key !== undefined && obj.__parentId) {
      const parent = products.get(obj.__parentId);
      if (parent) { parent.metafieldCount++; parent.metafieldKeys.push(`${obj.namespace}.${obj.key}`); }
    } else if (obj.__parentId) {
      const parent = products.get(obj.__parentId);
      if (parent) parent.mediaCount++;
    }
  }
  return Array.from(products.values());
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });
  }
  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* empty body OK */ }
    const must_have_keys: string[] = Array.isArray(body.must_have_keys) ? body.must_have_keys : [];
    const must_have_body: string[] = Array.isArray(body.must_have_body) ? body.must_have_body : [];
    // OR-grouped requirements: each group is satisfied if ANY of its items is present.
    // Product is flagged if ANY group is unsatisfied (logical AND across groups).
    // groups[i] = { metafield_keys: string[], body_strings: string[], label?: string }
    const must_have_groups: Array<{ metafield_keys?: string[]; body_strings?: string[]; label?: string }> = Array.isArray(body.must_have_groups) ? body.must_have_groups : [];
    const exclude_product_types: string[] = Array.isArray(body.exclude_product_types) ? body.exclude_product_types : [];
    const min_media: number | null = typeof body.min_media === "number" ? body.min_media : null;
    const include_keys_in_output: boolean = body.include_keys_in_output === true;

    const token = await getShopifyToken();

    let operationId = body.op_id;
    if (!operationId) {
      const submitResult = await submitBulkOp(token);
      if (submitResult?.userErrors?.length) {
        return new Response(JSON.stringify({ stage: "submit", error: "userErrors", details: submitResult.userErrors }), { status: 500 });
      }
      if (!submitResult?.bulkOperation?.id) {
        return new Response(JSON.stringify({ stage: "submit", error: "no operation id", raw: submitResult }), { status: 500 });
      }
      operationId = submitResult.bulkOperation.id;
    }

    const pollMaxMs = 75_000;
    const pollStart = Date.now();
    let opState = await pollBulkOp(token, operationId);
    while (opState && !['COMPLETED', 'FAILED', 'CANCELED', 'CANCELING', 'EXPIRED'].includes(opState.status)) {
      if (Date.now() - pollStart >= pollMaxMs) break;
      await new Promise((r) => setTimeout(r, 5000));
      opState = await pollBulkOp(token, operationId);
    }

    if (!opState || opState.status !== "COMPLETED") {
      return new Response(JSON.stringify({
        stage: "poll", operation_id: operationId, status: opState?.status,
        objectCount: opState?.objectCount, rootObjectCount: opState?.rootObjectCount,
        message: "Re-call with { op_id: '<id>' } in 30-60s.",
      }), { status: 202 });
    }

    if (!opState.url) {
      return new Response(JSON.stringify({ stage: "download", operation_id: operationId, status: "COMPLETED", message: "No data URL." }), { status: 200 });
    }

    const jsonl = await downloadJSONL(opState.url);
    const allProducts = parseAndAggregate(jsonl);

    const hasAnyCriteria = must_have_keys.length > 0 || must_have_body.length > 0 || must_have_groups.length > 0 || min_media !== null;

    if (hasAnyCriteria) {
      const flagged: any[] = [];
      for (const p of allProducts) {
        if (exclude_product_types.includes(p.productType || "")) continue;
        const present = new Set<string>(p.metafieldKeys);
        const missing_keys = must_have_keys.filter((k) => !present.has(k));
        const missing_body = must_have_body.filter((s) => !p.descriptionHtml.includes(s));
        const lowMedia = min_media !== null && p.mediaCount < min_media;
        // OR-group check: product fails a group if ALL items in that group are missing
        const failed_groups: any[] = [];
        for (const grp of must_have_groups) {
          const keys = grp.metafield_keys || [];
          const strs = grp.body_strings || [];
          const hasAnyKey = keys.some((k) => present.has(k));
          const hasAnyStr = strs.some((s) => p.descriptionHtml.includes(s));
          if (!hasAnyKey && !hasAnyStr) {
            failed_groups.push({ label: grp.label || keys.concat(strs).join("|"), expected_any_of: { metafield_keys: keys, body_strings: strs } });
          }
        }
        const failed = missing_keys.length > 0 || missing_body.length > 0 || lowMedia || failed_groups.length > 0;
        if (failed) {
          const record: any = {
            handle: p.handle, title: p.title, status: p.status, productType: p.productType,
            metafieldCount: p.metafieldCount, mediaCount: p.mediaCount, bodyHtmlLength: p.bodyHtmlLength,
            missing_keys, missing_body, low_media: lowMedia, failed_groups,
          };
          if (include_keys_in_output) record.metafieldKeys = p.metafieldKeys;
          flagged.push(record);
        }
      }
      flagged.sort((a, b) =>
        (b.missing_keys.length + b.missing_body.length + b.failed_groups.length) -
        (a.missing_keys.length + a.missing_body.length + a.failed_groups.length) ||
        (a.status === "ACTIVE" ? -1 : 1) - (b.status === "ACTIVE" ? -1 : 1) ||
        a.metafieldCount - b.metafieldCount
      );

      const byType: Record<string, { active: number; draft: number; total_in_audit: number }> = {};
      for (const f of flagged) {
        const t = f.productType || "(none)";
        if (!byType[t]) byType[t] = { active: 0, draft: 0, total_in_audit: 0 };
        if (f.status === "ACTIVE") byType[t].active++;
        else if (f.status === "DRAFT") byType[t].draft++;
      }
      const allByType: Record<string, number> = {};
      for (const p of allProducts) {
        if (exclude_product_types.includes(p.productType || "")) continue;
        const t = p.productType || "(none)";
        allByType[t] = (allByType[t] || 0) + 1;
      }
      for (const t of Object.keys(byType)) byType[t].total_in_audit = allByType[t] || 0;
      for (const t of Object.keys(allByType)) {
        if (!byType[t]) byType[t] = { active: 0, draft: 0, total_in_audit: allByType[t] };
      }

      return new Response(JSON.stringify({
        stage: "complete", mode: "targeted", operation_id: operationId,
        objectCount: opState.objectCount, completedAt: opState.completedAt,
        total_products_audited: allProducts.length,
        criteria: { must_have_keys, must_have_body, must_have_groups, min_media, exclude_product_types },
        flagged_count: flagged.length,
        passed_count: allProducts.filter((p) => !exclude_product_types.includes(p.productType || "")).length - flagged.length,
        by_product_type: byType,
        flagged: flagged,
      }, null, 2), { headers: { "Content-Type": "application/json" } });
    }

    // ===== DEFAULT MODE =====
    allProducts.sort((a, b) => a.metafieldCount - b.metafieldCount || a.mediaCount - b.mediaCount || a.bodyHtmlLength - b.bodyHtmlLength);
    const buckets = { '<10': 0, '10-14': 0, '15-19': 0, '20-24': 0, '25+': 0 };
    for (const p of allProducts) {
      const c = p.metafieldCount;
      if (c < 10) buckets['<10']++;
      else if (c < 15) buckets['10-14']++;
      else if (c < 20) buckets['15-19']++;
      else if (c < 25) buckets['20-24']++;
      else buckets['25+']++;
    }
    const byType: Record<string, any> = {};
    for (const p of allProducts) {
      const t = p.productType || "(none)";
      if (!byType[t]) byType[t] = { count: 0, sumMeta: 0, sumMedia: 0, sumBody: 0 };
      byType[t].count++;
      byType[t].sumMeta += p.metafieldCount;
      byType[t].sumMedia += p.mediaCount;
      byType[t].sumBody += p.bodyHtmlLength;
    }
    const productTypeStats = Object.entries(byType).map(([type, s]: [string, any]) => ({
      productType: type, count: s.count,
      avgMetafields: Math.round((s.sumMeta / s.count) * 10) / 10,
      avgMedia: Math.round((s.sumMedia / s.count) * 10) / 10,
      avgBodyChars: Math.round(s.sumBody / s.count),
    })).sort((a, b) => b.count - a.count);
    const slim = allProducts.map((p, i) => {
      const { metafieldKeys, descriptionHtml, ...rest } = p;
      return i < 50 ? { ...rest, metafieldKeys } : rest;
    });
    return new Response(JSON.stringify({
      stage: "complete", mode: "distribution", operation_id: operationId,
      objectCount: opState.objectCount, rootObjectCount: opState.rootObjectCount, completedAt: opState.completedAt,
      total_products: allProducts.length,
      metafield_distribution: buckets,
      by_product_type: productTypeStats,
      products: slim,
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
