import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const SHOPIFY_CLIENT_ID = "377e2e7b97b9297be558b83d93ce2b41";
const SHOPIFY_SHOP = "ashridge-trees";
const SHOPIFY_REST_URL = `https://${SHOPIFY_SHOP}.myshopify.com/admin/api/2026-01`;
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
async function rest(token, method, path, body) {
  const opts = {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    }
  };
  if (body) opts.body = JSON.stringify(body);
  const resp = await fetch(`${SHOPIFY_REST_URL}${path}`, opts);
  const text = await resp.text();
  if (!resp.ok) throw new Error(`REST ${method} ${path} (${resp.status}): ${text}`);
  return JSON.parse(text);
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
    const { source_blog_handle, target_blog_handle, article_handle, delete_source } = await req.json();
    if (!source_blog_handle || !target_blog_handle || !article_handle) {
      return new Response(JSON.stringify({
        error: "source_blog_handle, target_blog_handle, article_handle required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    // Find source blog
    const sourceBlogs = await rest(token, "GET", `/blogs.json?handle=${source_blog_handle}`);
    const sourceBlog = sourceBlogs?.blogs?.[0];
    if (!sourceBlog) return new Response(JSON.stringify({
      error: `Source blog not found: ${source_blog_handle}`
    }), {
      status: 404
    });
    // Find target blog
    const targetBlogs = await rest(token, "GET", `/blogs.json?handle=${target_blog_handle}`);
    const targetBlog = targetBlogs?.blogs?.[0];
    if (!targetBlog) return new Response(JSON.stringify({
      error: `Target blog not found: ${target_blog_handle}`
    }), {
      status: 404
    });
    // Find article in source blog
    const articles = await rest(token, "GET", `/blogs/${sourceBlog.id}/articles.json?handle=${article_handle}`);
    const article = articles?.articles?.[0];
    if (!article) return new Response(JSON.stringify({
      error: `Article not found: ${article_handle} in ${source_blog_handle}`
    }), {
      status: 404
    });
    // Create article in target blog
    const newArticle = await rest(token, "POST", `/blogs/${targetBlog.id}/articles.json`, {
      article: {
        title: article.title,
        handle: article.handle,
        body_html: article.body_html,
        summary_html: article.summary_html,
        author: article.author,
        tags: article.tags,
        published: article.published,
        published_at: article.published_at,
        image: article.image,
        metafields_global_title_tag: article.metafields_global_title_tag || undefined,
        metafields_global_description_tag: article.metafields_global_description_tag || undefined
      }
    });
    const result = {
      status: "created_in_target",
      source_article_id: article.id,
      new_article_id: newArticle.article.id,
      old_path: `/blogs/${source_blog_handle}/${article_handle}`,
      new_path: `/blogs/${target_blog_handle}/${article_handle}`
    };
    // Optionally delete source
    if (delete_source) {
      await rest(token, "DELETE", `/articles/${article.id}.json`);
      result.source_deleted = true;
    } else {
      result.source_deleted = false;
      result.note = "Set delete_source=true to remove the original";
    }
    return new Response(JSON.stringify(result), {
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
