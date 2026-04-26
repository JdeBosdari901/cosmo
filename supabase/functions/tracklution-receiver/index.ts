import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const supabase = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
// Parse UTM params and click IDs from a URL string
function parseFromUrl(rawUrl) {
  const result = {
    utm_source: null,
    utm_medium: null,
    utm_campaign: null,
    utm_content: null,
    utm_term: null,
    gclid: null,
    fbclid: null,
    msclkid: null,
    ttclid: null,
    epik: null,
    gbraid: null,
    wbraid: null,
    dclid: null,
    rdtCid: null,
    click_id: null,
    click_id_type: null
  };
  try {
    // URLs may be Shopify web-pixel sandbox URLs — extract the real URL path and query
    let targetUrl = rawUrl;
    const sandboxMatch = rawUrl.match(/\/sandbox\/(?:modern|legacy)\/(.+)$/);
    if (sandboxMatch) {
      targetUrl = 'https://x.com/' + sandboxMatch[1];
    }
    const u = new URL(targetUrl);
    const p = u.searchParams;
    result.utm_source = p.get('utm_source');
    result.utm_medium = p.get('utm_medium');
    result.utm_campaign = p.get('utm_campaign');
    result.utm_content = p.get('utm_content');
    result.utm_term = p.get('utm_term');
    result.gclid = p.get('gclid');
    result.fbclid = p.get('fbclid');
    result.msclkid = p.get('msclkid');
    result.ttclid = p.get('ttclid');
    result.epik = p.get('epik');
    result.gbraid = p.get('gbraid');
    result.wbraid = p.get('wbraid');
    result.dclid = p.get('dclid');
    result.rdtCid = p.get('rdtCid');
    // Infer google / organic from srsltid when no explicit UTM source is present
    if (!result.utm_source && p.get('srsltid')) {
      result.utm_source = 'google';
      result.utm_medium = 'organic';
    }
    // Primary click ID — priority: gclid > gbraid > wbraid > fbclid > msclkid > ttclid > epik > dclid > rdtCid
    if (result.gclid) {
      result.click_id = result.gclid;
      result.click_id_type = 'gclid';
    } else if (result.gbraid) {
      result.click_id = result.gbraid;
      result.click_id_type = 'gbraid';
    } else if (result.wbraid) {
      result.click_id = result.wbraid;
      result.click_id_type = 'wbraid';
    } else if (result.fbclid) {
      result.click_id = result.fbclid;
      result.click_id_type = 'fbclid';
    } else if (result.msclkid) {
      result.click_id = result.msclkid;
      result.click_id_type = 'msclkid';
    } else if (result.ttclid) {
      result.click_id = result.ttclid;
      result.click_id_type = 'ttclid';
    } else if (result.epik) {
      result.click_id = result.epik;
      result.click_id_type = 'epik';
    } else if (result.dclid) {
      result.click_id = result.dclid;
      result.click_id_type = 'dclid';
    } else if (result.rdtCid) {
      result.click_id = result.rdtCid;
      result.click_id_type = 'rdtCid';
    }
  } catch  {}
  return result;
}
Deno.serve(async (req)=>{
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
  };
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 200,
      headers: corsHeaders
    });
  }
  const ok = new Response(JSON.stringify({
    status: 'ok'
  }), {
    status: 200,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json'
    }
  });
  const url = new URL(req.url);
  const q = url.searchParams;
  let postBody = {};
  if (req.method === 'POST') {
    try {
      postBody = await req.json();
    } catch  {}
  }
  const isPost = Object.keys(postBody).length > 0;
  const hasQueryParams = q.toString().length > 0;
  if (!isPost && !hasQueryParams) return ok;
  const get = (key)=>{
    if (isPost) return postBody[key] ?? null;
    const v = q.get(key);
    return v === '' ? null : v;
  };
  const eventName = get('track') || get('event') || get('event_name') || get('eventName');
  const eventId = get('eventId') || get('event_id');
  const rawValue = get('value');
  const value = rawValue ? parseFloat(rawValue) : null;
  const currency = get('currency') || 'GBP';
  const externalId = get('externalId') || get('external_id');
  const email = get('email');
  let utmSource = get('utmSource') || get('utm_source');
  let utmMedium = get('utmMedium') || get('utm_medium');
  let utmCampaign = get('utmCampaign') || get('utm_campaign');
  let utmContent = get('utmContent') || get('utm_content');
  let utmTerm = get('utmTerm') || get('utm_term');
  // Direct click IDs — full set per Tracklution webhook parameter docs
  let clickId = get('gclid') || get('gbraid') || get('wbraid') || get('fbclid') || get('msclkid') || get('ttclid') || get('epik') || get('dclid') || get('rdtCid') || get('clickId') || get('click_id');
  let clickIdType = get('gclid') ? 'gclid' : get('gbraid') ? 'gbraid' : get('wbraid') ? 'wbraid' : get('fbclid') ? 'fbclid' : get('msclkid') ? 'msclkid' : get('ttclid') ? 'ttclid' : get('epik') ? 'epik' : get('dclid') ? 'dclid' : get('rdtCid') ? 'rdtCid' : null;
  const entryUrlRaw = get('entryUrl') || get('entry_url') || get('term');
  // Referrer source — populated once Tracklution support confirms they can send it.
  const referrerSource = get('referrerUrl') || get('referrer_url') || get('referrer') || null;
  // Fall back to parsing from entry URL if direct params are missing
  if (entryUrlRaw && !utmSource && !clickId) {
    const parsed = parseFromUrl(entryUrlRaw);
    utmSource = utmSource || parsed.utm_source;
    utmMedium = utmMedium || parsed.utm_medium;
    utmCampaign = utmCampaign || parsed.utm_campaign;
    utmContent = utmContent || parsed.utm_content;
    utmTerm = utmTerm || parsed.utm_term;
    clickId = clickId || parsed.click_id;
    clickIdType = clickIdType || parsed.click_id_type;
  }
  if (!eventName) return ok;
  const rawPayload = isPost ? postBody : Object.fromEntries(q.entries());
  const row = {
    event_name: eventName,
    event_id: eventId,
    value: value !== null && !isNaN(value) ? value : null,
    currency,
    session_id: get('sessionId') || get('session_id') || get('trls'),
    click_id: clickId,
    click_id_type: clickIdType,
    utm_source: utmSource,
    utm_medium: utmMedium,
    utm_campaign: utmCampaign,
    utm_content: utmContent,
    utm_term: utmTerm,
    email_hash: email,
    external_id: externalId,
    shopify_order_id: externalId,
    entry_url: entryUrlRaw,
    referrer_source: referrerSource,
    raw_payload: rawPayload
  };
  const cleaned = Object.fromEntries(Object.entries(row).filter(([, v])=>v !== null && v !== undefined && v !== ''));
  const { error } = await supabase.from('tracklution_events').insert(cleaned);
  if (error) {
    if (error.code === '23505') return ok;
    console.error('Insert error:', JSON.stringify(error));
    return new Response(JSON.stringify({
      error: error.message
    }), {
      status: 500,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json'
      }
    });
  }
  return ok;
});
