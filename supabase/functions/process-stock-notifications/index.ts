import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
/**
 * process-stock-notifications v2
 *
 * Changes in v2:
 * - bom_blocked report now shows actual stock shortages, not just DENY policy status
 * - Only reports packs where limiting component can build < 20 packs
 * - Only lists the constraining components with stock/need detail
 * - Header changed from "BOM-Blocked Assembled Products" to "BOM Stock Shortages"
 *
 * Handles all DB operations for the stock notification system:
 * - Fetches enabled notification routes due today
 * - Calls report RPCs (get_stock_digest_exceptions, etc.)
 * - Updates digest_exception_tracking (new, updated, resolved)
 * - Applies escalation thresholds per recipient
 * - Formats Slack messages
 * - Returns array of {recipientId, recipientLabel, reportType, messageText}
 *
 * The n8n workflow splits the array and sends each message via Slack.
 */ Deno.serve(async (req)=>{
  if (req.method !== "POST") {
    return new Response(JSON.stringify({
      error: "POST required"
    }), {
      status: 405
    });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const log = [];
  const errors = [];
  // 1. Determine day (London time)
  const now = new Date();
  const londonStr = now.toLocaleDateString('en-GB', {
    timeZone: 'Europe/London',
    weekday: 'long'
  }).toLowerCase();
  const londonDate = new Date(now.toLocaleString('en-US', {
    timeZone: 'Europe/London'
  }));
  const dayName = londonStr;
  const dayOfMonth = londonDate.getDate();
  const dayOfWeek = londonDate.getDay();
  const isWeekday = dayOfWeek >= 1 && dayOfWeek <= 5;
  const todayStr = londonDate.toISOString().slice(0, 10);
  // 2. Fetch enabled routes
  const { data: routes, error: routeErr } = await supabase.from('notification_routing').select('*').eq('enabled', true);
  if (routeErr) {
    return new Response(JSON.stringify({
      status: 'failed',
      reason: routeErr.message
    }), {
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
  log.push(`Routes: ${(routes ?? []).length} enabled`);
  // 3. Filter routes due today
  function isDue(freq) {
    if (freq === 'daily') return true;
    if (freq === 'weekday') return isWeekday;
    if (freq === dayName) return true;
    if (freq === 'weekly_' + dayName.slice(0, 3)) return true;
    if (freq === 'monthly_1st' && dayOfMonth === 1) return true;
    if (freq === 'monthly_last_weekday') {
      const lastDay = new Date(londonDate.getFullYear(), londonDate.getMonth() + 1, 0).getDate();
      const lastDate = new Date(londonDate.getFullYear(), londonDate.getMonth(), lastDay);
      let lastWeekday = lastDay;
      if (lastDate.getDay() === 0) lastWeekday = lastDay - 2;
      if (lastDate.getDay() === 6) lastWeekday = lastDay - 1;
      return dayOfMonth === lastWeekday;
    }
    return false;
  }
  const dueRoutes = (routes ?? []).filter((r)=>isDue(r.frequency));
  if (dueRoutes.length === 0) {
    return new Response(JSON.stringify({
      status: 'complete',
      reason: 'No routes due',
      messages: [],
      log
    }), {
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
  log.push(`Due today: ${dueRoutes.length} routes (${dayName})`);
  // 4. Unique report types
  const reportTypes = [
    ...new Set(dueRoutes.map((r)=>r.report_type))
  ];
  // 5. Fetch report data via RPCs
  const rpcMap = {
    stock_digest: 'get_stock_digest_exceptions',
    bom_blocked: 'get_bom_blocked_products',
    cannot_source: 'get_cannot_source_products'
  };
  const reportData = {};
  for (const rt of reportTypes){
    const fn = rpcMap[rt];
    if (fn) {
      try {
        const { data, error } = await supabase.rpc(fn);
        if (error) throw new Error(error.message);
        reportData[rt] = Array.isArray(data) ? data : [];
        log.push(`Report ${rt}: ${reportData[rt].length} items`);
      } catch (e) {
        errors.push(`Report ${rt}: ${e instanceof Error ? e.message : String(e)}`);
        reportData[rt] = [];
      }
    } else {
      reportData[rt] = [];
    }
  }
  // 6. Fetch active tracking exceptions
  const { data: activeExceptions } = await supabase.from('digest_exception_tracking').select('*').is('resolved_at', null);
  // 7. Exception key helpers
  function exceptionKey(reportType, item) {
    if (reportType === 'stock_digest') return item.sku;
    if (reportType === 'bom_blocked') return item.variant_sku;
    if (reportType === 'cannot_source') return item.handle;
    return JSON.stringify(item);
  }
  const trackingIndex = {};
  for (const ex of activeExceptions ?? []){
    trackingIndex[ex.report_type + '::' + ex.exception_key] = ex;
  }
  // 8. Update tracking
  const newInserts = [];
  const resolveIds = [];
  for (const rt of reportTypes){
    const data = reportData[rt] || [];
    const currentKeys = new Set();
    for (const item of data){
      const key = exceptionKey(rt, item);
      currentKeys.add(key);
      const lookupKey = rt + '::' + key;
      const existing = trackingIndex[lookupKey];
      if (existing) {
        const newDays = existing.consecutive_days + 1;
        await supabase.from('digest_exception_tracking').update({
          consecutive_days: newDays,
          last_seen_at: todayStr
        }).eq('id', existing.id);
        existing.consecutive_days = newDays;
        existing.last_seen_at = todayStr;
      } else {
        const newRow = {
          report_type: rt,
          exception_key: key,
          exception_detail: item,
          first_seen_at: todayStr,
          last_seen_at: todayStr,
          consecutive_days: 1
        };
        newInserts.push(newRow);
        trackingIndex[lookupKey] = newRow;
      }
    }
    for (const ex of activeExceptions ?? []){
      if (ex.report_type === rt && !currentKeys.has(ex.exception_key)) {
        resolveIds.push(ex.id);
      }
    }
  }
  try {
    if (newInserts.length > 0) {
      await supabase.from('digest_exception_tracking').insert(newInserts);
    }
    for (const rid of resolveIds){
      await supabase.from('digest_exception_tracking').update({
        resolved_at: todayStr
      }).eq('id', rid);
    }
    log.push(`Tracking: ${newInserts.length} new, ${resolveIds.length} resolved`);
  } catch (e) {
    errors.push(`Tracking update: ${e instanceof Error ? e.message : String(e)}`);
  }
  // 9. Format messages
  function formatReport(reportType, items, threshold) {
    const qualified = [];
    const newlyEscalated = [];
    for (const item of items){
      const key = exceptionKey(reportType, item);
      const tracking = trackingIndex[reportType + '::' + key];
      if (!tracking) continue;
      if (tracking.consecutive_days >= threshold) {
        qualified.push({
          item,
          tracking
        });
        if (threshold > 0 && tracking.consecutive_days === threshold) {
          newlyEscalated.push(key);
        }
      }
    }
    if (qualified.length === 0) return null;
    let msg = '';
    if (reportType === 'stock_digest') {
      msg += '*Stock Digest Exceptions*\n';
      for (const { item, tracking } of qualified){
        const flag = newlyEscalated.includes(item.sku) ? ' :new: NEW' : '';
        msg += `\u2022 \`${item.sku}\` \u2014 ${(item.exception_type || '').replace('_', ' ')} (day ${tracking.consecutive_days})${flag}\n`;
      }
    } else if (reportType === 'bom_blocked') {
      msg += '*BOM Stock Shortages*\n';
      for (const { item, tracking } of qualified){
        const flag = newlyEscalated.includes(item.variant_sku) ? ' :new: NEW' : '';
        const blocked = item.blocked_ingredients || [];
        const shortDetail = blocked.map((b)=>`${b.sku} (${b.effective_stock} avail, need ${b.quantity_per_pack})`).join(', ');
        msg += `\u2022 \`${item.variant_sku}\` \u2014 can build ${item.max_buildable} (day ${tracking.consecutive_days})${flag}\n`;
        if (shortDetail) msg += `  _Short: ${shortDetail}_\n`;
      }
    } else if (reportType === 'cannot_source') {
      msg += '*Cannot Source Products*\n';
      for (const item of items){
        msg += `\u2022 \`${item.sku_prefix || ''}\` (${item.handle || ''})`;
        if (item.cannot_source_notes) msg += ` \u2014 ${item.cannot_source_notes}`;
        msg += '\n';
      }
    }
    return msg;
  }
  // 10. Build output messages
  const messages = [];
  for (const route of dueRoutes){
    const data = reportData[route.report_type] || [];
    const msg = formatReport(route.report_type, data, route.escalation_threshold);
    if (msg === null && route.suppress_if_empty) continue;
    const finalMsg = msg || `_No exceptions to report for ${route.report_type.replace('_', ' ')}._`;
    messages.push({
      recipientId: route.recipient_id,
      recipientLabel: route.recipient_label,
      reportType: route.report_type,
      messageText: finalMsg
    });
  }
  // 11. Update last_sent_at
  for (const route of dueRoutes){
    if (route.id) {
      await supabase.from('notification_routing').update({
        last_sent_at: new Date().toISOString()
      }).eq('id', route.id);
    }
  }
  // 12. Mark escalations
  for (const rt of reportTypes){
    for (const item of reportData[rt] || []){
      const key = exceptionKey(rt, item);
      const tracking = trackingIndex[rt + '::' + key];
      if (tracking && tracking.consecutive_days >= 3 && !tracking.escalated_at && tracking.id) {
        await supabase.from('digest_exception_tracking').update({
          escalated_at: todayStr
        }).eq('id', tracking.id);
      }
    }
  }
  log.push(`Messages: ${messages.length} to send`);
  const status = errors.length === 0 ? 'complete' : 'complete_with_errors';
  return new Response(JSON.stringify({
    status,
    messages,
    log,
    errors
  }), {
    headers: {
      'Content-Type': 'application/json'
    }
  });
});
