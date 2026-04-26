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
  if (!resp.ok) throw new Error(`Token failed (${resp.status})`);
  return (await resp.json()).access_token;
}
async function shopifyGQL(token, query, variables) {
  const resp = await fetch(SHOPIFY_GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Shopify-Access-Token": token
    },
    body: JSON.stringify({
      query,
      variables
    })
  });
  if (!resp.ok) throw new Error(`GQL error (${resp.status})`);
  return resp.json();
}
async function findBlog(token, handle) {
  let cursor = null;
  for(let i = 0; i < 10; i++){
    const vars = {
      first: 25
    };
    if (cursor) vars.after = cursor;
    const r = await shopifyGQL(token, `query($first:Int!,$after:String){blogs(first:$first,after:$after){edges{node{id handle}cursor}pageInfo{hasNextPage}}}`, vars);
    const edges = r?.data?.blogs?.edges ?? [];
    const found = edges.find((e)=>e.node.handle === handle);
    if (found) return found.node;
    if (!r?.data?.blogs?.pageInfo?.hasNextPage) break;
    cursor = edges[edges.length - 1]?.cursor;
  }
  return null;
}
async function findArticle(token, blogId, handle) {
  let cursor = null;
  for(let i = 0; i < 20; i++){
    const vars = {
      blogId,
      first: 25
    };
    if (cursor) vars.after = cursor;
    const r = await shopifyGQL(token, `query($blogId:ID!,$first:Int!,$after:String){blog(id:$blogId){articles(first:$first,after:$after){edges{node{id title handle body}cursor}pageInfo{hasNextPage}}}}`, vars);
    const edges = r?.data?.blog?.articles?.edges ?? [];
    const found = edges.find((e)=>e.node.handle === handle);
    if (found) return found.node;
    if (!r?.data?.blog?.articles?.pageInfo?.hasNextPage) break;
    cursor = edges[edges.length - 1]?.cursor;
  }
  return null;
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") return new Response(null, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
    }
  });
  try {
    const { slug, blog_handle, replacements } = await req.json();
    // slug: article handle, blog_handle: blog handle, replacements: [["old","new"],...]
    if (!slug || !blog_handle || !replacements?.length) return new Response(JSON.stringify({
      error: "slug, blog_handle, and replacements[] required"
    }), {
      status: 400
    });
    const token = await getShopifyToken();
    const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    // Look up article
    const { data: slugRow } = await supabase.from("shopify_slugs").select("shopify_resource_id").eq("slug", slug).eq("resource_type", "article").maybeSingle();
    let articleId;
    let currentBody;
    let title;
    if (slugRow?.shopify_resource_id) {
      articleId = `gid://shopify/Article/${slugRow.shopify_resource_id}`;
      const r = await shopifyGQL(token, `query($id:ID!){article(id:$id){id title body}}`, {
        id: articleId
      });
      currentBody = r?.data?.article?.body ?? "";
      title = r?.data?.article?.title ?? slug;
    } else {
      const blog = await findBlog(token, blog_handle);
      if (!blog) return new Response(JSON.stringify({
        error: `Blog not found: ${blog_handle}`
      }), {
        status: 404
      });
      const article = await findArticle(token, blog.id, slug);
      if (!article) return new Response(JSON.stringify({
        error: `Article not found: ${slug} in ${blog_handle}`
      }), {
        status: 404
      });
      articleId = article.id;
      currentBody = article.body;
      title = article.title;
      // Cache ID
      const numId = articleId.replace("gid://shopify/Article/", "");
      await supabase.from("shopify_slugs").update({
        shopify_resource_id: numId
      }).eq("slug", slug).eq("resource_type", "article");
    }
    // Apply replacements
    let newBody = currentBody;
    const applied = [];
    for (const [oldText, newText] of replacements){
      if (newBody.includes(oldText)) {
        newBody = newBody.split(oldText).join(newText);
        applied.push(`${oldText} → ${newText}`);
      }
    }
    if (applied.length === 0) {
      return new Response(JSON.stringify({
        status: "no_changes",
        slug,
        title,
        message: "No matching text found in article body"
      }), {
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    // Update
    const updateResult = await shopifyGQL(token, `mutation($id:ID!,$article:ArticleUpdateInput!){articleUpdate(id:$id,article:$article){article{id title handle}userErrors{field message}}}`, {
      id: articleId,
      article: {
        body: newBody
      }
    });
    const ue = updateResult?.data?.articleUpdate?.userErrors;
    if (ue?.length) return new Response(JSON.stringify({
      error: "Update failed",
      userErrors: ue
    }), {
      status: 422
    });
    return new Response(JSON.stringify({
      status: "updated",
      slug,
      title,
      replacements_applied: applied
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
