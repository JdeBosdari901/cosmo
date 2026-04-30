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
    headers: { "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json" },
    body: new URLSearchParams({ grant_type: "client_credentials", client_id: SHOPIFY_CLIENT_ID, client_secret: clientSecret }).toString(),
  });
  if (!resp.ok) throw new Error(`Token request failed (${resp.status}): ${await resp.text()}`);
  return (await resp.json()).access_token;
}

async function gql(token: string, query: string, variables?: any) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Shopify-Access-Token": token },
    body: JSON.stringify({ query, variables }),
  });
  const txt = await resp.text();
  if (!resp.ok) throw new Error(`HTTP ${resp.status}: ${txt}`);
  return JSON.parse(txt);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: { "Access-Control-Allow-Origin": "*" } });
  }
  try {
    let body: any = {};
    try { body = await req.json(); } catch { /* empty body OK */ }
    const token = await getShopifyToken();

    // DEBUG MODE: return everything we can see
    if (body.debug === true) {
      const allThemes = await gql(token, `{ themes(first: 20) { edges { node { id name role } } } }`);
      return new Response(JSON.stringify({ debug: true, all_themes: allThemes }, null, 2), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get MAIN theme
    const themesResult = await gql(token, `{ themes(first: 5) { edges { node { id name role } } } }`);
    const themes = (themesResult?.data?.themes?.edges || []).map((e: any) => e.node);
    const mainTheme = themes.find((t: any) => t.role === "MAIN") || themes[0];
    if (!mainTheme) {
      return new Response(JSON.stringify({ error: "No themes returned", raw: themesResult }), { status: 500 });
    }

    const filenames: string[] = Array.isArray(body.filenames) ? body.filenames : [];
    const search: string | null = typeof body.search === "string" && body.search.length > 0 ? body.search : null;
    const list_only: boolean = body.list_only === true;

    async function fetchFiles(names: string[]) {
      const chunks: string[][] = [];
      for (let i = 0; i < names.length; i += 50) chunks.push(names.slice(i, i + 50));
      const all: any[] = [];
      for (const chunk of chunks) {
        const r = await gql(token, `query($id: ID!, $names: [String!]) {
          theme(id: $id) {
            files(filenames: $names, first: 250) {
              edges { node { filename size body { ... on OnlineStoreThemeFileBodyText { content } } } }
            }
          }
        }`, { id: mainTheme.id, names: chunk });
        if (r?.errors) throw new Error(`GraphQL errors: ${JSON.stringify(r.errors)}`);
        const edges = r?.data?.theme?.files?.edges || [];
        for (const e of edges) all.push({ filename: e.node.filename, size: e.node.size, content: e.node.body?.content || null });
      }
      return all;
    }

    function grep(content: string, term: string, ctx = 3) {
      if (!content) return [];
      const lines = content.split("\n");
      const matches: any[] = [];
      const t = term.toLowerCase();
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().includes(t)) {
          matches.push({
            line_number: i + 1,
            line: lines[i],
            context_before: lines.slice(Math.max(0, i - ctx), i),
            context_after: lines.slice(i + 1, i + 1 + ctx),
          });
        }
      }
      return matches;
    }

    if (list_only) {
      const files = await fetchFiles(["*"]);
      return new Response(JSON.stringify({
        theme: mainTheme,
        all_themes: themes,
        file_count: files.length,
        files: files.map((f) => ({ filename: f.filename, size: f.size })),
      }, null, 2), { headers: { "Content-Type": "application/json" } });
    }

    if (search) {
      const scope: string[] = filenames.length > 0 ? filenames : ["sections/*", "snippets/*"];
      const files = await fetchFiles(scope);
      const results: any[] = [];
      let total = 0;
      for (const f of files) {
        if (!f.content) continue;
        const m = grep(f.content, search);
        if (m.length > 0) { results.push({ filename: f.filename, match_count: m.length, matches: m }); total += m.length; }
      }
      results.sort((a, b) => b.match_count - a.match_count);
      return new Response(JSON.stringify({
        theme: mainTheme,
        search_term: search,
        scope,
        files_searched: files.length,
        files_with_matches: results.length,
        total_matches: total,
        results,
      }, null, 2), { headers: { "Content-Type": "application/json" } });
    }

    if (filenames.length > 0) {
      const files = await fetchFiles(filenames);
      return new Response(JSON.stringify({
        theme: mainTheme,
        requested: filenames,
        file_count: files.length,
        files,
      }, null, 2), { headers: { "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({
      theme: mainTheme,
      all_themes: themes,
      usage: "Pass { list_only: true } to list filenames, { filenames: [...] } to fetch contents, or { search: 'term' } to grep across sections/snippets.",
    }, null, 2), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
