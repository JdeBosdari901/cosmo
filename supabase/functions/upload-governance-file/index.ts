import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceKey);

  // ── Health check (no auth required) ────────────────────────────────────────
  if (url.searchParams.get('health') === 'true') {
    try {
      await supabase.from('cosmo_docs').select('id').limit(1);
      const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];
      const missing = required.filter(k => !Deno.env.get(k));
      if (missing.length > 0) {
        return new Response(
          JSON.stringify({ ok: false, healthStatus: 'fail', reason: `Missing env: ${missing.join(', ')}` }),
          { status: 503, headers: { 'Content-Type': 'application/json' } }
        );
      }
      return new Response(
        JSON.stringify({ ok: true, healthStatus: 'ok' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      );
    } catch (e) {
      return new Response(
        JSON.stringify({ ok: false, healthStatus: 'fail', reason: String(e) }),
        { status: 503, headers: { 'Content-Type': 'application/json' } }
      );
    }
  }
  // ───────────────────────────────────────────────────────────────────────────

  // GET /?filename=xxx — download from governance bucket + return size/sha256
  if (req.method === 'GET') {
    const filename = url.searchParams.get('filename');
    if (!filename) {
      return new Response(JSON.stringify({ error: 'Missing filename param' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }
    const { data, error } = await supabase.storage.from('governance').download(filename);
    if (error || !data) {
      return new Response(JSON.stringify({ error: error?.message || 'Not found' }), { status: 404, headers: { 'Content-Type': 'application/json' } });
    }
    const buf = new Uint8Array(await data.arrayBuffer());
    const hash = await crypto.subtle.digest('SHA-256', buf);
    const sha256 = Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('');
    return new Response(JSON.stringify({ size_bytes: buf.length, sha256 }), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  // POST — upload to governance bucket + insert governance_files row
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'GET or POST only' }), { status: 405, headers: { 'Content-Type': 'application/json' } });
  }

  try {
    const body = await req.json();
    const { filename, content, content_type = 'text/markdown; charset=utf-8', uploaded_by = 'claude' } = body;

    if (!filename || typeof content !== 'string') {
      return new Response(JSON.stringify({ error: 'Required: filename, content' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    const bytes = new TextEncoder().encode(content);

    const { data: storageData, error: storageError } = await supabase.storage
      .from('governance')
      .upload(filename, bytes, { contentType: content_type, upsert: true });

    if (storageError) {
      return new Response(JSON.stringify({ error: 'Storage upload failed: ' + storageError.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    const { error: dbError } = await supabase
      .from('governance_files')
      .upsert({ filename, content, content_type, uploaded_by }, { onConflict: 'filename' });

    if (dbError) {
      return new Response(JSON.stringify({ error: 'DB upsert failed: ' + dbError.message, storage_path: storageData.path }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    const { data: verifyStorage, error: verifyStorageErr } = await supabase.storage
      .from('governance')\
      .download(filename);

    if (verifyStorageErr || !verifyStorage) {
      return new Response(JSON.stringify({ error: 'Post-write storage verification failed: ' + verifyStorageErr?.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    const verifiedBytes = new Uint8Array(await verifyStorage.arrayBuffer());
    const storageSizeMatch = verifiedBytes.length === bytes.length;

    const { data: verifyRow, error: verifyRowErr } = await supabase
      .from('governance_files')
      .select('filename, size_bytes, updated_at')
      .eq('filename', filename)
      .single();

    if (verifyRowErr || !verifyRow) {
      return new Response(JSON.stringify({ error: 'Post-write DB verification failed: ' + verifyRowErr?.message }), { status: 500, headers: { 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({
      success: true,
      storage_path: storageData.path,
      size_bytes: bytes.length,
      storage_verified: storageSizeMatch,
      db_size_bytes: verifyRow.size_bytes,
      db_updated_at: verifyRow.updated_at
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
