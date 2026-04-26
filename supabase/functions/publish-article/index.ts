import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
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
async function findBlogByHandle(token, targetHandle) {
  let cursor = null;
  for(let i = 0; i < 10; i++){
    const vars = {
      first: 25
    };
    if (cursor) vars.after = cursor;
    const result = await shopifyGraphQL(token, `query($first: Int!, $after: String) { blogs(first: $first, after: $after) { edges { node { id title handle } cursor } pageInfo { hasNextPage } } }`, vars);
    const edges = result?.data?.blogs?.edges ?? [];
    const found = edges.find((e)=>e.node.handle === targetHandle);
    if (found) return found.node;
    if (!result?.data?.blogs?.pageInfo?.hasNextPage) break;
    cursor = edges[edges.length - 1]?.cursor ?? null;
    if (!cursor) break;
  }
  return null;
}
async function findArticleByHandle(token, blogId, targetHandle) {
  let cursor = null;
  for(let i = 0; i < 20; i++){
    const vars = {
      blogId,
      first: 25
    };
    if (cursor) vars.after = cursor;
    const result = await shopifyGraphQL(token, `query($blogId: ID!, $first: Int!, $after: String) { blog(id: $blogId) { articles(first: $first, after: $after) { edges { node { id title handle body } cursor } pageInfo { hasNextPage } } } }`, vars);
    const edges = result?.data?.blog?.articles?.edges ?? [];
    const found = edges.find((e)=>e.node.handle === targetHandle);
    if (found) return found.node;
    if (!result?.data?.blog?.articles?.pageInfo?.hasNextPage) break;
    cursor = edges[edges.length - 1]?.cursor ?? null;
    if (!cursor) break;
  }
  return null;
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
    if (req.method !== "POST") return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
    const reqJson = await req.json();
    const { slug, seo_title, seo_description } = reqJson;
    let articleBody = reqJson.body ?? null;
    // Optional: faq_items — JSON array of {question, answer} objects.
    // When provided, sets both seo.faq_items and seo.aq_items metafields,
    // which are required for Shopify to render FAQPage JSON-LD schema.
    const faq_items = reqJson.faq_items ?? null;
    if (!slug) return new Response(JSON.stringify({
      error: "slug is required"
    }), {
      status: 400
    });
    // Validate faq_items if provided
    if (faq_items !== null) {
      if (!Array.isArray(faq_items)) {
        return new Response(JSON.stringify({
          error: "faq_items must be an array"
        }), {
          status: 400
        });
      }
      for (const item of faq_items){
        if (typeof item.question !== "string" || typeof item.answer !== "string") {
          return new Response(JSON.stringify({
            error: "Each faq_items entry must have string 'question' and 'answer' fields"
          }), {
            status: 400
          });
        }
      }
    }
    const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    // ── if no body provided inline, read from blog_articles ──
    if (!articleBody) {
      const { data: ba } = await supabase.from("blog_articles").select("body_html").or(`slug.eq.${slug},slug.eq./${slug}`).maybeSingle();
      if (ba?.body_html) {
        articleBody = ba.body_html;
      }
    }
    if (!articleBody) {
      const { data: slugRow2 } = await supabase.from("shopify_slugs").select("blog_handle").eq("slug", slug).eq("resource_type", "article").maybeSingle();
      if (slugRow2?.blog_handle) {
        const fullSlug = `/blogs/${slugRow2.blog_handle}/${slug}`;
        const { data: ba2 } = await supabase.from("blog_articles").select("body_html").eq("slug", fullSlug).maybeSingle();
        if (ba2?.body_html) articleBody = ba2.body_html;
      }
    }
    if (!articleBody && !seo_title && !seo_description && !faq_items) {
      return new Response(JSON.stringify({
        error: "No content to publish: provide body, seo fields, or faq_items"
      }), {
        status: 400
      });
    }
    const { data: slugRow, error: slugError } = await supabase.from("shopify_slugs").select("slug, resource_type, blog_handle, shopify_resource_id").eq("slug", slug).eq("resource_type", "article").maybeSingle();
    if (slugError) return new Response(JSON.stringify({
      error: "Slug lookup failed",
      detail: slugError.message
    }), {
      status: 500
    });
    if (!slugRow) return new Response(JSON.stringify({
      error: `Article slug not found: ${slug}`
    }), {
      status: 404
    });
    if (!slugRow.blog_handle) return new Response(JSON.stringify({
      error: `blog_handle missing for slug: ${slug}`
    }), {
      status: 422
    });
    const token = await getShopifyToken();
    let articleId;
    let currentBody = null;
    let currentTitle = null;
    if (slugRow.shopify_resource_id) {
      articleId = `gid://shopify/Article/${slugRow.shopify_resource_id}`;
      const r = await shopifyGraphQL(token, `query($id: ID!) { article(id: $id) { id title body } }`, {
        id: articleId
      });
      currentBody = r?.data?.article?.body ?? null;
      currentTitle = r?.data?.article?.title ?? null;
    } else {
      const blog = await findBlogByHandle(token, slugRow.blog_handle);
      if (!blog) return new Response(JSON.stringify({
        error: `Blog not found: '${slugRow.blog_handle}'`
      }), {
        status: 404
      });
      const article = await findArticleByHandle(token, blog.id, slug);
      if (!article) return new Response(JSON.stringify({
        error: `Article not found: handle '${slug}' in blog '${slugRow.blog_handle}'`
      }), {
        status: 404
      });
      articleId = article.id;
      currentBody = article.body ?? null;
      currentTitle = article.title ?? null;
      const numericId = articleId.replace("gid://shopify/Article/", "");
      await supabase.from("shopify_slugs").update({
        shopify_resource_id: numericId
      }).eq("slug", slug).eq("resource_type", "article");
    }
    if (currentBody) {
      const { data: ev } = await supabase.from("pdp_content").select("version").eq("slug", slug).eq("status", "backup").order("version", {
        ascending: false
      }).limit(1);
      const v = ev && ev.length > 0 ? ev[0].version + 1 : 1;
      await supabase.from("pdp_content").insert({
        slug,
        version: v,
        status: "backup",
        body_html: currentBody,
        notes: `Backup: ${currentTitle ?? slug} — ${new Date().toISOString()}`
      });
    }
    const articleInput = {};
    if (articleBody) articleInput.body = articleBody;
    const metafields = [];
    if (seo_title) metafields.push({
      namespace: "global",
      key: "title_tag",
      type: "single_line_text_field",
      value: seo_title
    });
    if (seo_description) metafields.push({
      namespace: "global",
      key: "description_tag",
      type: "single_line_text_field",
      value: seo_description
    });
    // FAQ schema metafields — seo.faq_items and seo.aq_items must both be set
    // with identical JSON for Shopify to render FAQPage JSON-LD (confirmed 26 Apr 2026)
    if (faq_items && faq_items.length > 0) {
      const faqJson = JSON.stringify(faq_items);
      metafields.push({
        namespace: "seo",
        key: "faq_items",
        type: "json",
        value: faqJson
      });
      metafields.push({
        namespace: "seo",
        key: "aq_items",
        type: "json",
        value: faqJson
      });
    }
    if (metafields.length > 0) articleInput.metafields = metafields;
    const updateResult = await shopifyGraphQL(token, `mutation($id: ID!, $article: ArticleUpdateInput!) { articleUpdate(id: $id, article: $article) { article { id title handle body } userErrors { field message } } }`, {
      id: articleId,
      article: articleInput
    });
    const userErrors = updateResult?.data?.articleUpdate?.userErrors;
    if (userErrors && userErrors.length > 0) return new Response(JSON.stringify({
      error: "articleUpdate failed",
      userErrors
    }), {
      status: 422
    });
    const updatedArticle = updateResult?.data?.articleUpdate?.article;
    const { data: pv } = await supabase.from("pdp_content").select("version").eq("slug", slug).eq("status", "published").order("version", {
      ascending: false
    }).limit(1);
    const pVer = pv && pv.length > 0 ? pv[0].version + 1 : 1;
    await supabase.from("pdp_content").insert({
      slug,
      version: pVer,
      status: "published",
      body_html: articleBody ?? null,
      seo_title: seo_title ?? null,
      seo_description: seo_description ?? null,
      published_at: new Date().toISOString(),
      notes: `Published: ${updatedArticle?.title ?? slug}${faq_items ? ` (FAQ metafields: ${faq_items.length} items)` : ""}`
    });
    await supabase.from("blog_articles").update({
      synced_at: new Date().toISOString()
    }).or(`slug.eq.${slug},slug.eq./blogs/${slugRow.blog_handle}/${slug}`);
    return new Response(JSON.stringify({
      status: "published",
      slug,
      shopify_article_id: articleId,
      blog_handle: slugRow.blog_handle,
      title: updatedArticle?.title,
      body_updated: !!articleBody,
      seo_updated: !!(seo_title || seo_description),
      faq_schema_set: !!(faq_items && faq_items.length > 0),
      faq_items_count: faq_items?.length ?? 0,
      backup_saved: !!currentBody
    }), {
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
