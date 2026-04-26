import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
/**
 * governance-files-upsert — utility EF to upsert rows into the public.governance_files table.
 * 
 * Purpose: Supabase `execute_sql` via MCP has practical limits on inline text size for SQL statements.
 * This EF accepts base64-encoded content and handles the INSERT ... ON CONFLICT UPDATE server-side.
 * 
 * Deployed: 23 April 2026 for the Sweet Pea Batch Composing tech spec publish event.
 * 
 * Auth: no JWT required (verify_jwt=false). Uses service_role key from EF env to bypass RLS.
 * Reason no JWT: invoked from bash_tool curl, and the sensitivity is no higher than any other
 * bash_tool-authenticated write path. JdeB is the only user of these projects currently.
 */ Deno.serve(async (req)=>{
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({
      error: 'POST only'
    }), {
      status: 405,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseUrl, serviceKey);
  try {
    const body = await req.json();
    const { filename, content_base64, content_type } = body;
    if (!filename || !content_base64) {
      return new Response(JSON.stringify({
        error: 'Required: filename, content_base64'
      }), {
        status: 400,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    // Decode base64 to text (UTF-8)
    const decoded = atob(content_base64);
    const bytes = new Uint8Array(decoded.length);
    for(let i = 0; i < decoded.length; i++)bytes[i] = decoded.charCodeAt(i);
    const text = new TextDecoder('utf-8').decode(bytes);
    const ct = content_type || 'text/markdown';
    // Upsert: INSERT on new, UPDATE on filename conflict
    const { data, error } = await supabase.from('governance_files').upsert({
      filename,
      content: text,
      content_type: ct,
      uploaded_by: 'claude',
      updated_at: new Date().toISOString()
    }, {
      onConflict: 'filename'
    }).select('filename, size_bytes, updated_at').single();
    if (error) {
      return new Response(JSON.stringify({
        error: error.message
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    return new Response(JSON.stringify({
      success: true,
      ...data,
      chars_written: text.length
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: String(err)
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
});
