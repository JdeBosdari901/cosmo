// upload-storage-object — generic Supabase Storage uploader.
//
// POST { bucket, path, content_base64, content_type, upsert? } → uploads to
// storage.objects using the service role key held in EF runtime env. Caller
// authenticates with an anon-key JWT (verify_jwt=true).
//
// Design goals:
//   - Drop-in generic: no bucket, filetype, or project-specific logic.
//   - Safe defaults: upsert defaults to false; path safety enforced (no .., no
//     leading /, no control chars); bucket existence is the access gate.
//   - Integrity: returns {md5, sha256, size_bytes} so the caller can verify
//     round-trip without a second GET.
//
// Not hardcoded: bucket, path, content_type, upsert — all come from caller.
// Not enforced here: bucket allowlists, content-type allowlists. Caller decides.
//
// Replaces (eventually): upload-governance-file. That EF is hardcoded to
// governance-archive and string-only. If this one proves out, governance
// writes can migrate and upload-governance-file can be deprecated.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
Deno.serve(async (req)=>{
  if (req.method !== 'POST') {
    return json({
      error: 'POST only'
    }, 405);
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) {
    return json({
      error: 'Server misconfigured: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY'
    }, 500);
  }
  let body;
  try {
    body = await req.json();
  } catch (_e) {
    return json({
      error: 'Invalid JSON body'
    }, 400);
  }
  const bucket = body.bucket;
  const path = body.path;
  const content_base64 = body.content_base64;
  const content_type = body.content_type;
  const upsert = body.upsert;
  // Required parameter validation
  if (typeof bucket !== 'string' || bucket.length === 0) {
    return json({
      error: 'Required: bucket (non-empty string)'
    }, 400);
  }
  if (typeof path !== 'string' || path.length === 0) {
    return json({
      error: 'Required: path (non-empty string)'
    }, 400);
  }
  if (typeof content_base64 !== 'string' || content_base64.length === 0) {
    return json({
      error: 'Required: content_base64 (non-empty string)'
    }, 400);
  }
  if (typeof content_type !== 'string' || content_type.length === 0) {
    return json({
      error: 'Required: content_type (non-empty string)'
    }, 400);
  }
  // Generic path safety — applies to any bucket, any filetype
  if (path.includes('..')) {
    return json({
      error: 'Path must not contain ".."'
    }, 400);
  }
  if (path.startsWith('/')) {
    return json({
      error: 'Path must not begin with "/"'
    }, 400);
  }
  // deno-lint-ignore no-control-regex
  if (/[\x00-\x1f\x7f]/.test(path)) {
    return json({
      error: 'Path must not contain control characters'
    }, 400);
  }
  // Decode base64 → bytes
  let bytes;
  try {
    const bin = atob(content_base64);
    bytes = new Uint8Array(bin.length);
    for(let i = 0; i < bin.length; i++)bytes[i] = bin.charCodeAt(i);
  } catch (_e) {
    return json({
      error: 'content_base64 is not valid base64'
    }, 400);
  }
  // Upload
  const supabase = createClient(supabaseUrl, serviceKey);
  const upsertFlag = upsert === true; // default false — do not silently overwrite
  const { data, error } = await supabase.storage.from(bucket).upload(path, bytes, {
    contentType: content_type,
    upsert: upsertFlag
  });
  if (error) {
    // Surface bucket + path in the error payload so callers get useful diagnostics
    return json({
      error: error.message,
      bucket,
      path
    }, 500);
  }
  // Integrity hashes for round-trip verification
  const sha256 = await sha256hex(bytes);
  const md5 = await md5hex(bytes);
  return json({
    success: true,
    bucket,
    path: data?.path ?? path,
    size_bytes: bytes.length,
    md5,
    sha256
  }, 200);
});
function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      'Content-Type': 'application/json'
    }
  });
}
async function sha256hex(input) {
  const hash = await crypto.subtle.digest('SHA-256', input);
  return Array.from(new Uint8Array(hash)).map((b)=>b.toString(16).padStart(2, '0')).join('');
}
// Minimal MD5 implementation (RFC 1321) — copied verbatim from upload-governance-file v6.
// Kept for parity with local md5sum and with the GET mode of upload-governance-file.
async function md5hex(input) {
  function rotl(x, n) {
    return x << n | x >>> 32 - n;
  }
  function add32(a, b) {
    return a + b & 0xFFFFFFFF;
  }
  const bitLen = input.length * 8;
  const padLen = input.length + 9 + 63 & ~63;
  const buf = new Uint8Array(padLen);
  buf.set(input);
  buf[input.length] = 0x80;
  const dv = new DataView(buf.buffer);
  dv.setUint32(padLen - 8, bitLen & 0xFFFFFFFF, true);
  dv.setUint32(padLen - 4, Math.floor(bitLen / 0x100000000), true);
  let a = 0x67452301, b = 0xefcdab89, c = 0x98badcfe, d = 0x10325476;
  const K = [
    0xd76aa478,
    0xe8c7b756,
    0x242070db,
    0xc1bdceee,
    0xf57c0faf,
    0x4787c62a,
    0xa8304613,
    0xfd469501,
    0x698098d8,
    0x8b44f7af,
    0xffff5bb1,
    0x895cd7be,
    0x6b901122,
    0xfd987193,
    0xa679438e,
    0x49b40821,
    0xf61e2562,
    0xc040b340,
    0x265e5a51,
    0xe9b6c7aa,
    0xd62f105d,
    0x02441453,
    0xd8a1e681,
    0xe7d3fbc8,
    0x21e1cde6,
    0xc33707d6,
    0xf4d50d87,
    0x455a14ed,
    0xa9e3e905,
    0xfcefa3f8,
    0x676f02d9,
    0x8d2a4c8a,
    0xfffa3942,
    0x8771f681,
    0x6d9d6122,
    0xfde5380c,
    0xa4beea44,
    0x4bdecfa9,
    0xf6bb4b60,
    0xbebfbc70,
    0x289b7ec6,
    0xeaa127fa,
    0xd4ef3085,
    0x04881d05,
    0xd9d4d039,
    0xe6db99e5,
    0x1fa27cf8,
    0xc4ac5665,
    0xf4292244,
    0x432aff97,
    0xab9423a7,
    0xfc93a039,
    0x655b59c3,
    0x8f0ccc92,
    0xffeff47d,
    0x85845dd1,
    0x6fa87e4f,
    0xfe2ce6e0,
    0xa3014314,
    0x4e0811a1,
    0xf7537e82,
    0xbd3af235,
    0x2ad7d2bb,
    0xeb86d391
  ];
  const S = [
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    7,
    12,
    17,
    22,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    5,
    9,
    14,
    20,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    4,
    11,
    16,
    23,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21,
    6,
    10,
    15,
    21
  ];
  for(let i = 0; i < buf.length; i += 64){
    const M = new Array(16);
    for(let j = 0; j < 16; j++)M[j] = dv.getUint32(i + j * 4, true);
    let A = a, B = b, C = c, D = d;
    for(let k = 0; k < 64; k++){
      let F, g;
      if (k < 16) {
        F = B & C | ~B & D;
        g = k;
      } else if (k < 32) {
        F = D & B | ~D & C;
        g = (5 * k + 1) % 16;
      } else if (k < 48) {
        F = B ^ C ^ D;
        g = (3 * k + 5) % 16;
      } else {
        F = C ^ (B | ~D);
        g = 7 * k % 16;
      }
      F = add32(F, add32(A, add32(K[k], M[g])));
      A = D;
      D = C;
      C = B;
      B = add32(B, rotl(F, S[k]));
    }
    a = add32(a, A);
    b = add32(b, B);
    c = add32(c, C);
    d = add32(d, D);
  }
  const out = new Uint8Array(16);
  const odv = new DataView(out.buffer);
  odv.setUint32(0, a, true);
  odv.setUint32(4, b, true);
  odv.setUint32(8, c, true);
  odv.setUint32(12, d, true);
  return Array.from(out).map((x)=>x.toString(16).padStart(2, '0')).join('');
}
