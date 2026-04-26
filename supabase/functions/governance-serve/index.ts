import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
Deno.serve(async (req)=>{
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET",
        "Access-Control-Allow-Headers": "*"
      }
    });
  }
  if (req.method !== "GET") {
    return new Response(JSON.stringify({
      error: "GET only"
    }), {
      status: 405
    });
  }
  const url = new URL(req.url);
  const filename = url.searchParams.get("file");
  if (!filename) {
    // List all files (metadata only, no content)
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await sb.from("governance_files").select("filename, content_type, size_bytes, updated_at, uploaded_by").order("filename");
    if (error) {
      return new Response(JSON.stringify({
        error: error.message
      }), {
        status: 500,
        headers: {
          "Content-Type": "application/json"
        }
      });
    }
    return new Response(JSON.stringify({
      files: data,
      count: data.length
    }), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-cache"
      }
    });
  }
  // Serve a specific file
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data, error } = await sb.from("governance_files").select("content, content_type, updated_at").eq("filename", filename).single();
  if (error || !data) {
    return new Response(JSON.stringify({
      error: "File not found: " + filename
    }), {
      status: 404,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  return new Response(data.content, {
    headers: {
      "Content-Type": data.content_type || "text/markdown",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-cache",
      "X-Updated-At": data.updated_at
    }
  });
});
