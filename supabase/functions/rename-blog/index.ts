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
    if (req.method !== "POST") {
      return new Response(JSON.stringify({
        error: "POST required"
      }), {
        status: 405
      });
    }
    const { current_handle, new_handle } = await req.json();
    if (!current_handle || !new_handle) {
      return new Response(JSON.stringify({
        error: "current_handle and new_handle are required"
      }), {
        status: 400
      });
    }
    const token = await getShopifyToken();
    // Step 1: Find the blog by current handle
    const findResult = await shopifyGraphQL(token, `query($q: String!) {
        blogs(first: 10, query: $q) {
          edges { node { id title handle } }
        }
      }`, {
      q: `handle:${current_handle}`
    });
    // Also fetch all blogs if handle search returns nothing
    const allBlogsResult = await shopifyGraphQL(token, `{ blogs(first: 20) { edges { node { id title handle } } } }`);
    const allBlogs = allBlogsResult?.data?.blogs?.edges?.map((e)=>e.node) ?? [];
    const targetBlog = allBlogs.find((b)=>b.handle === current_handle);
    if (!targetBlog) {
      return new Response(JSON.stringify({
        error: `Blog with handle '${current_handle}' not found`,
        available_blogs: allBlogs.map((b)=>({
            title: b.title,
            handle: b.handle
          }))
      }), {
        status: 404
      });
    }
    // Step 2: Update blog handle
    const updateResult = await shopifyGraphQL(token, `mutation($id: ID!, $blog: BlogUpdateInput!) {
        blogUpdate(id: $id, blog: $blog) {
          blog { id title handle }
          userErrors { field message }
        }
      }`, {
      id: targetBlog.id,
      blog: {
        handle: new_handle
      }
    });
    const userErrors = updateResult?.data?.blogUpdate?.userErrors;
    if (userErrors && userErrors.length > 0) {
      return new Response(JSON.stringify({
        error: "blogUpdate failed",
        userErrors
      }), {
        status: 422
      });
    }
    const updatedBlog = updateResult?.data?.blogUpdate?.blog;
    // Step 3: Update all shopify_slugs rows that reference the old blog_handle
    const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const { count } = await supabase.from("shopify_slugs").update({
      blog_handle: new_handle
    }).eq("blog_handle", current_handle).eq("resource_type", "article");
    return new Response(JSON.stringify({
      status: "renamed",
      blog_id: targetBlog.id,
      old_handle: current_handle,
      new_handle: updatedBlog?.handle,
      blog_title: updatedBlog?.title,
      shopify_slugs_updated: count ?? "unknown",
      note: "Shopify automatically creates redirects from old URLs to new ones."
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
