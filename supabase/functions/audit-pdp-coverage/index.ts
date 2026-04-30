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
    // Product (top-level, no __parentId)
    if (obj.handle !== undefined && obj.title !== undefined) {
      products.set(obj.id, {
        id: obj.id,
        handle: obj.handle,
        title: obj.title,
        status: obj.status,
        productType: obj.productType,
        tags: obj.tags || [],
        bodyHtmlLength: (obj.descriptionHtml || "").length,
        hasFeaturedMedia: !!obj.featuredMedia,
        mediaCount: 0,
        metafieldCount: 0,
        metafieldKeys: [] as string[],
      });
    } else if (obj.namespace !== undefined && obj.key !== undefined && obj.__parentId) {
      const parent = products.get(obj.__parentId);
      if (parent) {
        parent.metafieldCount++;
        parent.metafieldKeys.push(`${obj.namespace}.${obj.key}`);
      }
    } else if (obj.__parentId) {
      const parent = products.get(obj.__parentId);
      if (parent) parent.mediaCount++;
    }
  }
  return Array.from(products.values());
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" } });
  }
  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* empty body OK */ }
    const token = await getShopifyToken();

    let operationId = body.op_id;
    if (!operationId) {
      const submitResult = await submitBulkOp(token);
      if (submitResult?.userErrors?.length) {
        return new Response(JSON.stringify({ stage: "submit", error: "userErrors", details: submitResult.userErrors }), { status: 500 });
      }
      if (!submitResult?.bulkOperation?.id) {
        return new Response(JSON.stringify({ stage: "submit", error: "no operation id returned", raw: submitResult }), { status: 500 });
      }
      operationId = submitResult.bulkOperation.id;
    }

    // Poll up to 75s
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
        stage: "poll",
        operation_id: operationId,
        status: opState?.status,
        objectCount: opState?.objectCount,
        rootObjectCount: opState?.rootObjectCount,
        message: "Operation not yet complete. Re-call this EF with body { op_id: '<the operation_id>' } in 30-60s.",
      }), { status: 202 });
    }

    if (!opState.url) {
      return new Response(JSON.stringify({ stage: "download", operation_id: operationId, status: "COMPLETED", message: "No data URL — query returned no rows." }), { status: 200 });
    }

    const jsonl = await downloadJSONL(opState.url);
    const products = parseAndAggregate(jsonl);
    products.sort((a, b) => a.metafieldCount - b.metafieldCount || a.mediaCount - b.mediaCount || a.bodyHtmlLength - b.bodyHtmlLength);

    // Distribution
    const buckets = { '<10': 0, '10-14': 0, '15-19': 0, '20-24': 0, '25+': 0 };
    for (const p of products) {
      const c = p.metafieldCount;
      if (c < 10) buckets['<10']++;
      else if (c < 15) buckets['10-14']++;
      else if (c < 20) buckets['15-19']++;
      else if (c < 25) buckets['20-24']++;
      else buckets['25+']++;
    }

    // By productType
    const byType: Record<string, any> = {};
    for (const p of products) {
      const t = p.productType || "(none)";
      if (!byType[t]) byType[t] = { count: 0, sumMeta: 0, sumMedia: 0, sumBody: 0 };
      byType[t].count++;
      byType[t].sumMeta += p.metafieldCount;
      byType[t].sumMedia += p.mediaCount;
      byType[t].sumBody += p.bodyHtmlLength;
    }
    const productTypeStats = Object.entries(byType).map(([type, s]: [string, any]) => ({
      productType: type,
      count: s.count,
      avgMetafields: Math.round((s.sumMeta / s.count) * 10) / 10,
      avgMedia: Math.round((s.sumMedia / s.count) * 10) / 10,
      avgBodyChars: Math.round(s.sumBody / s.count),
    })).sort((a, b) => b.count - a.count);

    // Strip metafieldKeys list from per-product output to keep response small;
    // include only on the bottom 50 (lowest-coverage) for closer inspection
    const slim = products.map((p, i) => {
      const { metafieldKeys, ...rest } = p;
      return i < 50 ? { ...rest, metafieldKeys } : rest;
    });

    return new Response(JSON.stringify({
      stage: "complete",
      operation_id: operationId,
      objectCount: opState.objectCount,
      rootObjectCount: opState.rootObjectCount,
      completedAt: opState.completedAt,
      total_products: products.length,
      metafield_distribution: buckets,
      by_product_type: productTypeStats,
      products: slim,
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
