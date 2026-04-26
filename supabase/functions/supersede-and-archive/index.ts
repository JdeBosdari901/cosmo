import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      success: false,
      error: "POST only"
    }), {
      status: 405,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  let body;
  try {
    body = await req.json();
  } catch  {
    return new Response(JSON.stringify({
      success: false,
      error: "Invalid JSON body"
    }), {
      status: 400,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const { base_pattern, new_filename } = body;
  if (typeof base_pattern !== "string" || typeof new_filename !== "string") {
    return new Response(JSON.stringify({
      success: false,
      error: "Required: base_pattern (string), new_filename (string)"
    }), {
      status: 400,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  // 1. Select candidate rows to archive
  const { data: rows, error: selectError } = await sb.from("governance_files").select("filename, content, content_type").like("filename", base_pattern).neq("filename", new_filename);
  if (selectError) {
    return new Response(JSON.stringify({
      success: false,
      stage: "select",
      error: selectError.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  const candidates = rows ?? [];
  const archived = [];
  const errors = [];
  // 2. Upload each row to governance-archive, with upsert=true so retries are safe
  for (const row of candidates){
    const bytes = new TextEncoder().encode(row.content);
    const { error: uploadError } = await sb.storage.from("governance-archive").upload(row.filename, bytes, {
      contentType: row.content_type,
      upsert: true
    });
    if (uploadError) {
      errors.push({
        filename: row.filename,
        stage: "upload",
        msg: uploadError.message
      });
    } else {
      archived.push(row.filename);
    }
  }
  // 3. Delete from governance_files only the successfully archived rows
  const deleted = [];
  if (archived.length > 0) {
    const { error: deleteError } = await sb.from("governance_files").delete().in("filename", archived);
    if (deleteError) {
      errors.push({
        filename: "(batch)",
        stage: "delete",
        msg: deleteError.message
      });
    } else {
      deleted.push(...archived);
    }
  }
  // 4. Update cosmo_docs if new_filename matches the versioned naming convention
  const cosmo_docs_updated = [];
  const match = new_filename.match(/^(.+)-v(\d+)_(\d+)\.(md|py|html|tsv|csv)$/);
  if (match) {
    const baseName = match[1];
    const version = `v${match[2]}.${match[3]}`;
    const { data: updated, error: updateError } = await sb.from("cosmo_docs").update({
      version,
      updated_at: new Date().toISOString()
    }).eq("name", baseName).select("name");
    if (updateError) {
      errors.push({
        filename: new_filename,
        stage: "cosmo_docs_update",
        msg: updateError.message
      });
    } else if (updated) {
      cosmo_docs_updated.push(...updated.map((r)=>r.name));
    }
  }
  const success = errors.length === 0;
  return new Response(JSON.stringify({
    success,
    archived,
    deleted,
    cosmo_docs_updated,
    errors,
    candidate_count: candidates.length
  }), {
    status: success ? 200 : 207,
    headers: {
      "Content-Type": "application/json"
    }
  });
});
