


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "archive_sweetpea";


ALTER SCHEMA "archive_sweetpea" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."assemble_governance_file"("p_upload_id" "uuid", "p_filename" "text", "p_content_type" "text" DEFAULT 'text/markdown'::"text", "p_uploaded_by" "text" DEFAULT 'claude'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_content text;
  v_chunk_count integer;
  v_size integer;
BEGIN
  -- Count chunks
  SELECT count(*) INTO v_chunk_count
  FROM governance_upload_chunks
  WHERE upload_id = p_upload_id;

  IF v_chunk_count = 0 THEN
    RETURN jsonb_build_object('error', 'No chunks found for upload_id ' || p_upload_id);
  END IF;

  -- Concatenate chunks in order
  SELECT string_agg(chunk_content, '' ORDER BY chunk_index)
  INTO v_content
  FROM governance_upload_chunks
  WHERE upload_id = p_upload_id;

  v_size := octet_length(v_content);

  -- Upsert into governance_files
  INSERT INTO governance_files (filename, content, content_type, updated_at, uploaded_by)
  VALUES (p_filename, v_content, p_content_type, now(), p_uploaded_by)
  ON CONFLICT (filename) DO UPDATE SET
    content = EXCLUDED.content,
    content_type = EXCLUDED.content_type,
    updated_at = EXCLUDED.updated_at,
    uploaded_by = EXCLUDED.uploaded_by;

  -- Clean up chunks
  DELETE FROM governance_upload_chunks WHERE upload_id = p_upload_id;

  RETURN jsonb_build_object(
    'filename', p_filename,
    'size_bytes', v_size,
    'chunks_assembled', v_chunk_count,
    'status', 'ok'
  );
END;
$$;


ALTER FUNCTION "public"."assemble_governance_file"("p_upload_id" "uuid", "p_filename" "text", "p_content_type" "text", "p_uploaded_by" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."batch_update_shopify_total_price"("p_rows" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_count int;
BEGIN
  UPDATE shopify_orders so
  SET total_price = (r->>'total_price')::numeric,
      updated_at  = NOW()
  FROM jsonb_array_elements(p_rows) AS r
  WHERE so.shopify_order_id = (r->>'shopify_order_id')::bigint;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('updated', v_count);
END;
$$;


ALTER FUNCTION "public"."batch_update_shopify_total_price"("p_rows" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") RETURNS TABLE("upserted" integer, "updated_skus" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_upserted INTEGER := 0;
  v_deleted INTEGER := 0;
BEGIN
  -- Parse and deduplicate input by SKU (keep highest variant_id if duplicates exist)
  CREATE TEMP TABLE _input ON COMMIT DROP AS
  SELECT DISTINCT ON (sku)
    (item->>'vid')::INTEGER AS variant_id,
    item->>'sku' AS sku,
    (item->>'ins')::NUMERIC AS quantity_in_stock,
    (item->>'exp')::NUMERIC AS quantity_expected,
    (item->>'com')::NUMERIC AS committed,
    (item->>'saf')::NUMERIC AS safety,
    (item->>'ins')::NUMERIC + (item->>'exp')::NUMERIC - (item->>'com')::NUMERIC - (item->>'saf')::NUMERIC AS effective_stock
  FROM jsonb_array_elements(rows) AS item
  WHERE item->>'sku' IS NOT NULL AND item->>'sku' != ''
  ORDER BY sku, (item->>'vid')::INTEGER DESC;

  -- Delete stale rows where the variant_id has changed for an existing SKU
  DELETE FROM katana_stock_sync kss
  USING _input i
  WHERE kss.sku = i.sku
    AND kss.katana_variant_id IS DISTINCT FROM i.variant_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  -- Upsert inventory data keyed by variant_id
  WITH upserted AS (
    INSERT INTO katana_stock_sync (sku, katana_variant_id, quantity_in_stock, quantity_expected, effective_stock, last_checked_at, updated_at)
    SELECT i.sku, i.variant_id, i.quantity_in_stock, i.quantity_expected, i.effective_stock, now(), now()
    FROM _input i
    ON CONFLICT (katana_variant_id) DO UPDATE SET
      sku = EXCLUDED.sku,
      quantity_in_stock = EXCLUDED.quantity_in_stock,
      quantity_expected = EXCLUDED.quantity_expected,
      effective_stock = EXCLUDED.effective_stock,
      last_checked_at = EXCLUDED.last_checked_at,
      updated_at = EXCLUDED.updated_at
    RETURNING 1
  )
  SELECT count(*) INTO v_upserted FROM upserted;

  RETURN QUERY SELECT v_upserted, v_deleted;
END;
$$;


ALTER FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") IS 'Stage 1 of three-stage reconcile: bulk upserts Katana inventory data into katana_stock_sync. Called by n8n Katana refresh workflow.';



CREATE OR REPLACE FUNCTION "public"."get_attribution_ai_platforms"("p_from" "date", "p_to" "date") RETURNS json
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT json_agg(row_to_json(t) ORDER BY t.sessions DESC)
  FROM (
    SELECT ai_platform,
           sum(distinct_sessions)::int as sessions,
           sum(view_item_events)::int as views,
           sum(purchase_events)::int as purchases,
           sum(purchase_revenue)::numeric(10,2) as revenue
    FROM attribution_channel_daily
    WHERE date >= p_from AND date <= p_to
      AND ai_platform != ''
    GROUP BY ai_platform
  ) t;
$$;


ALTER FUNCTION "public"."get_attribution_ai_platforms"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_attribution_channels"("p_from" "date", "p_to" "date") RETURNS json
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT json_agg(row_data ORDER BY revenue DESC)
  FROM (
    SELECT 
      channel,
      SUM(distinct_sessions) as sessions,
      SUM(view_item_events) as views,
      SUM(purchase_events) as purchases,
      ROUND(SUM(purchase_revenue)::numeric, 2) as revenue,
      CASE WHEN SUM(distinct_sessions) > 0 
        THEN ROUND((SUM(purchase_events)::numeric / SUM(distinct_sessions)) * 100, 2) 
        ELSE 0 END as conv_rate
    FROM attribution_channel_daily
    WHERE date >= p_from AND date <= p_to
    GROUP BY channel
  ) row_data;
$$;


ALTER FUNCTION "public"."get_attribution_channels"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_attribution_daily_comparison"("p_from" "date", "p_to" "date") RETURNS json
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT json_agg(row_to_json(t) ORDER BY t.date)
  FROM (
    SELECT date, elevar_purchase_events, elevar_purchase_revenue,
           shopify_orders, shopify_revenue, ga4_transactions, ga4_revenue
    FROM attribution_daily_snapshot
    WHERE date >= p_from AND date <= p_to
  ) t;
$$;


ALTER FUNCTION "public"."get_attribution_daily_comparison"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_attribution_identity"("p_from" "date", "p_to" "date") RETURNS json
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT json_agg(row_to_json(t) ORDER BY t.date)
  FROM (
    SELECT d.date, d.distinct_sessions, d.sessions_with_email,
           d.sessions_with_shopify_customer, d.sessions_with_purchase,
           d.email_attach_rate_pct, d.customer_match_rate_pct,
           (SELECT CASE WHEN sum(d2.distinct_sessions) > 0
              THEN round(sum(d2.sessions_with_email)::numeric / sum(d2.distinct_sessions) * 100, 2)
              ELSE NULL END
            FROM identity_graph_daily d2
            WHERE d2.date > d.date - 30 AND d2.date <= d.date
           ) AS email_ma30_pct,
           (SELECT count(*) FROM identity_graph_daily d3
            WHERE d3.date > d.date - 30 AND d3.date <= d.date
           ) AS ma_days_used
    FROM identity_graph_daily d
    WHERE d.date >= p_from AND d.date <= p_to
  ) t;
$$;


ALTER FUNCTION "public"."get_attribution_identity"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_attribution_overview"("p_from" "date", "p_to" "date") RETURNS json
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT json_build_object(
    'total_revenue', COALESCE(SUM(purchase_revenue), 0),
    'total_purchases', COALESCE(SUM(purchase_events), 0),
    'total_sessions', COALESCE(SUM(distinct_sessions), 0),
    'total_views', COALESCE(SUM(view_item_events), 0),
    'avg_order_value', CASE WHEN SUM(purchase_events) > 0 
      THEN ROUND(SUM(purchase_revenue) / SUM(purchase_events), 2) ELSE 0 END,
    'date_from', p_from,
    'date_to', p_to
  )
  FROM attribution_channel_daily
  WHERE date >= p_from AND date <= p_to;
$$;


ALTER FUNCTION "public"."get_attribution_overview"("p_from" "date", "p_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_attribution_pipeline_health"() RETURNS json
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT json_build_object(
    -- Stage 1: aggregation pipeline freshness
    'aggregation_last_run', (SELECT max(refreshed_at) FROM attribution_channel_daily),
    'aggregation_age_minutes', ROUND(EXTRACT(EPOCH FROM (now() - (SELECT max(refreshed_at) FROM attribution_channel_daily))) / 60),
    'cron_active', (SELECT active FROM cron.job WHERE jobname = 'attribution_aggregate_hourly'),
    'cron_schedule', (SELECT schedule FROM cron.job WHERE jobname = 'attribution_aggregate_hourly'),

    -- Stage 2: is data flowing?
    'latest_data_date', (SELECT max(date) FROM attribution_channel_daily),
    'today_has_data', EXISTS(SELECT 1 FROM attribution_channel_daily WHERE date = current_date),
    'today_sessions', COALESCE((SELECT sum(distinct_sessions) FROM attribution_channel_daily WHERE date = current_date), 0),
    'today_purchases', COALESCE((SELECT sum(purchase_events) FROM attribution_channel_daily WHERE date = current_date), 0),
    'today_revenue', COALESCE((SELECT sum(purchase_revenue) FROM attribution_channel_daily WHERE date = current_date), 0),
    'today_channels', COALESCE((SELECT count(DISTINCT channel) FROM attribution_channel_daily WHERE date = current_date), 0),
    'today_ai_sessions', COALESCE((SELECT sum(distinct_sessions) FROM attribution_channel_daily WHERE date = current_date AND ai_platform != ''), 0),

    -- Stage 3: data quality — capture rate over last 3 days with data
    'capture_rate_pct', (
      SELECT CASE WHEN sum(shopify_orders) > 0
        THEN ROUND((sum(elevar_purchase_events)::numeric / sum(shopify_orders)) * 100, 1)
        ELSE NULL END
      FROM attribution_daily_snapshot
      WHERE date >= current_date - 3 AND elevar_purchase_events > 0
    ),
    'snapshot_latest_date', (SELECT max(date) FROM attribution_daily_snapshot WHERE elevar_purchase_events > 0)
  );
$$;


ALTER FUNCTION "public"."get_attribution_pipeline_health"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_bom_blocked_products"() RETURNS TABLE("variant_sku" "text", "blocked_ingredients" "jsonb", "total_ingredients" integer, "blocked_count" integer, "max_buildable" integer)
    LANGUAGE "sql" STABLE
    AS $$
  WITH ingredient_status AS (
    SELECT
      b.variant_sku,
      b.ingredient_sku,
      b.ingredient_sku_prefix,
      b.quantity,
      COALESCE(s.effective_stock::int, 0) AS effective_stock,
      CASE WHEN b.quantity > 0 
        THEN GREATEST(0, floor(COALESCE(s.effective_stock::int, 0)::numeric / b.quantity))::int
        ELSE 999999 
      END AS can_build
    FROM product_bom b
    LEFT JOIN katana_stock_sync s ON s.sku = b.ingredient_sku
    LEFT JOIN seasonal_selling_policy sp 
      ON sp.sku_prefix = split_part(b.variant_sku, '-', 1)
    WHERE b.active_on_site = true
      AND (
        sp.sku_prefix IS NULL
        OR CASE 
          WHEN sp.start_month <= sp.end_month THEN 
            EXTRACT(MONTH FROM CURRENT_DATE)::int >= sp.start_month 
            AND EXTRACT(MONTH FROM CURRENT_DATE)::int <= sp.end_month
          ELSE 
            EXTRACT(MONTH FROM CURRENT_DATE)::int >= sp.start_month 
            OR EXTRACT(MONTH FROM CURRENT_DATE)::int <= sp.end_month
        END
      )
  ),
  pack_buildable AS (
    SELECT
      i.variant_sku,
      min(i.can_build) AS max_buildable
    FROM ingredient_status i
    GROUP BY i.variant_sku
  ),
  constrained AS (
    SELECT
      i.variant_sku,
      jsonb_agg(
        jsonb_build_object(
          'sku', i.ingredient_sku,
          'prefix', i.ingredient_sku_prefix,
          'effective_stock', i.effective_stock,
          'quantity_per_pack', i.quantity,
          'can_build', i.can_build
        )
        ORDER BY i.can_build
      ) FILTER (WHERE i.can_build < 20) AS blocked_ingredients,
      count(*)::integer AS total_ingredients,
      count(*) FILTER (WHERE i.can_build < 20)::integer AS blocked_count,
      p.max_buildable
    FROM ingredient_status i
    JOIN pack_buildable p ON p.variant_sku = i.variant_sku
    WHERE p.max_buildable < 20
    GROUP BY i.variant_sku, p.max_buildable
  )
  SELECT c.variant_sku, c.blocked_ingredients, c.total_ingredients, c.blocked_count, c.max_buildable
  FROM constrained c
  WHERE c.blocked_count > 0
  ORDER BY c.max_buildable, c.variant_sku;
$$;


ALTER FUNCTION "public"."get_bom_blocked_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_cannot_source_products"() RETURNS TABLE("handle" "text", "sku_prefix" "text", "cannot_source_notes" "text", "start_month" integer, "end_month" integer)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT sp.handle, sp.sku_prefix, sp.cannot_source_notes, sp.start_month, sp.end_month
  FROM seasonal_selling_policy sp
  WHERE sp.cannot_source = true
$$;


ALTER FUNCTION "public"."get_cannot_source_products"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_cannot_source_products"() IS 'Returns products flagged as unsourceable by the buyer';



CREATE OR REPLACE FUNCTION "public"."get_channel_health"() RETURNS TABLE("channel_name" "text", "src" "text", "medium" "text", "last_event_at" timestamp with time zone, "age_minutes" numeric, "status" "text", "detail" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$

WITH
  active AS (
    SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE 'UTC')::int >= 6
       AND EXTRACT(HOUR FROM NOW() AT TIME ZONE 'UTC')::int < 21 AS is_active
  ),
  channel_latest AS (
    SELECT channel,
           max(date) AS latest_date,
           max(refreshed_at) AS latest_refresh,
           sum(distinct_sessions) FILTER (WHERE date >= current_date - 1) AS recent_sessions,
           sum(purchase_events) FILTER (WHERE date >= current_date - 1) AS recent_purchases
    FROM attribution_channel_daily
    WHERE date >= current_date - 7
    GROUP BY channel
  )

SELECT 'Google CPC'::text, 'google'::text, 'cpc'::text, g.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - g.latest_refresh)) / 60)::numeric,
  CASE WHEN g.latest_date IS NULL THEN 'red'
       WHEN NOT a.is_active AND g.latest_date >= current_date - 1 THEN 'green'
       WHEN g.latest_date >= current_date - 1 THEN 'green'
       WHEN g.latest_date >= current_date - 3 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN g.latest_date IS NULL THEN 'No Google CPC data in 7 days — campaigns may be paused'
       WHEN NOT a.is_active AND g.latest_date >= current_date - 1 THEN 'Outside active hours — last data: ' || g.latest_date
       WHEN g.latest_date >= current_date - 1 THEN 'Healthy — ' || COALESCE(g.recent_sessions, 0) || ' sessions, ' || COALESCE(g.recent_purchases, 0) || ' purchases'
       WHEN g.latest_date >= current_date - 3 THEN 'Last data: ' || g.latest_date || ' — gap developing, monitor'
       ELSE 'Last data: ' || g.latest_date || ' — campaigns may be paused or budget exhausted' END
FROM channel_latest g, active a
WHERE g.channel = 'Google CPC'

UNION ALL

SELECT 'Bing CPC'::text, 'bing'::text, 'cpc'::text, b.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - b.latest_refresh)) / 60)::numeric,
  CASE WHEN b.latest_date IS NULL THEN 'red'
       WHEN NOT a.is_active AND b.latest_date >= current_date - 1 THEN 'green'
       WHEN b.latest_date >= current_date - 1 THEN 'green'
       WHEN b.latest_date >= current_date - 3 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN b.latest_date IS NULL THEN 'No Bing CPC data in 7 days — campaigns may be paused'
       WHEN NOT a.is_active AND b.latest_date >= current_date - 1 THEN 'Outside active hours — last data: ' || b.latest_date
       WHEN b.latest_date >= current_date - 1 THEN 'Healthy — ' || COALESCE(b.recent_sessions, 0) || ' sessions, ' || COALESCE(b.recent_purchases, 0) || ' purchases'
       WHEN b.latest_date >= current_date - 3 THEN 'Last data: ' || b.latest_date || ' — gap developing, monitor'
       ELSE 'Last data: ' || b.latest_date || ' — campaigns may be paused or budget exhausted' END
FROM channel_latest b, active a
WHERE b.channel = 'Bing CPC'

UNION ALL

SELECT 'Email (Klaviyo)'::text, 'email'::text, 'campaign / flow'::text, k.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - k.latest_refresh)) / 60)::numeric,
  CASE WHEN k.latest_date IS NULL THEN 'amber'
       WHEN k.latest_date >= current_date - 2 THEN 'green'
       WHEN k.latest_date >= current_date - 4 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN k.latest_date IS NULL THEN 'No email events in 7 days — check Klaviyo schedule'
       WHEN k.latest_date >= current_date - 2 THEN 'Healthy — ' || COALESCE(k.recent_sessions, 0) || ' sessions, ' || COALESCE(k.recent_purchases, 0) || ' purchases'
       WHEN k.latest_date >= current_date - 4 THEN 'Last data: ' || k.latest_date || ' — quiet period or no recent campaigns'
       ELSE 'Last data: ' || k.latest_date || ' — check Klaviyo campaign schedule' END
FROM channel_latest k
WHERE k.channel = 'Email'

UNION ALL

SELECT 'AI Search'::text, 'ai'::text, 'referral'::text, ai.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - ai.latest_refresh)) / 60)::numeric,
  CASE WHEN ai.latest_date IS NULL THEN 'amber'
       WHEN ai.latest_date >= current_date - 2 THEN 'green'
       ELSE 'amber' END,
  CASE WHEN ai.latest_date IS NULL THEN 'No AI search traffic detected yet'
       WHEN ai.latest_date >= current_date - 2 THEN 'Active — ' || COALESCE(ai.recent_sessions, 0) || ' sessions (Elevar enrichment)'
       ELSE 'Last AI traffic: ' || ai.latest_date || ' — sporadic, expected for emerging channel' END
FROM channel_latest ai
WHERE ai.channel = 'AI Search';

$$;


ALTER FUNCTION "public"."get_channel_health"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_katana_products_summary"() RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT jsonb_build_object(
    'total',       COUNT(*),
    'active',      COUNT(*) FILTER (WHERE katana_active = true),
    'plants',      COUNT(*) FILTER (WHERE product_type = 'plant' AND katana_active = true),
    'bundles',     COUNT(*) FILTER (WHERE product_type = 'bundle' AND katana_active = true),
    'sundries',    COUNT(*) FILTER (WHERE product_type = 'sundry' AND katana_active = true),
    'gifts',       COUNT(*) FILTER (WHERE product_type = 'gift' AND katana_active = true),
    'vouchers',    COUNT(*) FILTER (WHERE product_type = 'voucher' AND katana_active = true),
    'with_species',COUNT(*) FILTER (WHERE species_ref_id IS NOT NULL AND katana_active = true),
    'last_seen',   MAX(katana_last_seen)
  )
  FROM katana_products;
$$;


ALTER FUNCTION "public"."get_katana_products_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_manual_override_detail"("p_category" "text" DEFAULT NULL::"text") RETURNS TABLE("sku" "text", "manual_override" "text", "effective_stock" numeric, "quantity_expected" numeric, "shopify_inventory_policy" "text", "product_name" "text", "notes" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
  RETURN QUERY
  SELECT
    k.sku,
    k.manual_override,
    k.effective_stock,
    k.quantity_expected,
    k.shopify_inventory_policy,
    kp.katana_name AS product_name,
    k.notes
  FROM katana_stock_sync k
  LEFT JOIN katana_products kp
    ON kp.sku_prefix = regexp_replace(k.sku, '-[^-]+$', '')
  WHERE k.manual_override IS NOT NULL
    AND (p_category IS NULL OR COALESCE(kp.product_type, 'unknown') = p_category)
  ORDER BY k.sku;
END;
$_$;


ALTER FUNCTION "public"."get_manual_override_detail"("p_category" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_manual_override_summary"() RETURNS TABLE("category" "text", "override_count" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(kp.product_type, 'unknown') AS category,
    count(*) AS override_count
  FROM katana_stock_sync k
  LEFT JOIN katana_products kp
    ON kp.sku_prefix = regexp_replace(k.sku, '-[^-]+$', '')
  WHERE k.manual_override IS NOT NULL
  GROUP BY COALESCE(kp.product_type, 'unknown')
  ORDER BY COALESCE(kp.product_type, 'unknown');
END;
$_$;


ALTER FUNCTION "public"."get_manual_override_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_next_queue_articles"("n" integer) RETURNS TABLE("title" "text", "slug" "text", "primary_keyword" "text", "grade" "text", "status" "text", "notes" "text")
    LANGUAGE "sql" STABLE
    AS $$
  SELECT title, slug, primary_keyword, grade, status, notes
  FROM content_ecosystem
  WHERE slug IS NOT NULL
    AND status NOT IN ('published', 'ai_published')
    AND grade IN ('C', 'B')
  ORDER BY
    CASE grade WHEN 'C' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,
    title
  LIMIT n;
$$;


ALTER FUNCTION "public"."get_next_queue_articles"("n" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_policy_mismatches"() RETURNS TABLE("sku" "text", "katana_variant_id" integer, "current_policy" "text", "target_policy" "text", "exception_type" "text", "reason" "text", "effective_stock" numeric, "quantity_in_stock" numeric, "quantity_expected" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  current_month int := EXTRACT(MONTH FROM now());
  current_day int := EXTRACT(DAY FROM now());
BEGIN
  RETURN QUERY

  -- Type A: DENY but has stock (stock formula says sell)
  SELECT
    k.sku, k.katana_variant_id,
    k.shopify_inventory_policy AS current_policy,
    'CONTINUE'::text AS target_policy,
    'blocking_sales'::text AS exception_type,
    'stock available: effective=' || COALESCE(k.effective_stock, 0) || ' expected=' || COALESCE(k.quantity_expected, 0) AS reason,
    k.effective_stock, k.quantity_in_stock, k.quantity_expected
  FROM katana_stock_sync k
  WHERE k.sku NOT LIKE 'katana_%'
    AND k.sku LIKE '%-%'
    AND k.shopify_inventory_policy = 'DENY'
    AND k.manual_override IS NULL
    AND COALESCE(k.effective_stock, 0) > 0
    AND COALESCE(k.quantity_expected, 0) > 0

  UNION ALL

  -- Type A2: DENY but presale window is open and presale_allowed
  SELECT
    k.sku, k.katana_variant_id,
    k.shopify_inventory_policy AS current_policy,
    'CONTINUE'::text AS target_policy,
    'blocking_presale'::text AS exception_type,
    'presale window open: season ' || sp.start_month || '-' || sp.end_month AS reason,
    k.effective_stock, k.quantity_in_stock, k.quantity_expected
  FROM katana_stock_sync k
  JOIN seasonal_selling_policy sp
    ON sp.sku_prefix = regexp_replace(k.sku, '-[^-]+$', '')
  WHERE k.sku NOT LIKE 'katana_%'
    AND k.sku LIKE '%-%'
    AND k.shopify_inventory_policy = 'DENY'
    AND k.manual_override IS NULL
    AND sp.presale_allowed = true
    AND NOT (
      CASE WHEN sp.start_month <= sp.end_month
        THEN current_month >= sp.start_month AND current_month <= sp.end_month
        ELSE current_month >= sp.start_month OR current_month <= sp.end_month
      END
    )
    AND sp.presale_start_month IS NOT NULL
    AND (
      current_month > sp.presale_start_month
      OR (current_month = sp.presale_start_month AND current_day >= COALESCE(sp.presale_start_day, 1))
    )
    AND NOT (COALESCE(k.effective_stock, 0) > 0 AND COALESCE(k.quantity_expected, 0) > 0)

  UNION ALL

  -- Type B: CONTINUE but nothing justifies it (overselling)
  SELECT
    k.sku, k.katana_variant_id,
    k.shopify_inventory_policy AS current_policy,
    'DENY'::text AS target_policy,
    'overselling'::text AS exception_type,
    'no justification: effective=' || COALESCE(k.effective_stock, 0) || ' expected=' || COALESCE(k.quantity_expected, 0) AS reason,
    k.effective_stock, k.quantity_in_stock, k.quantity_expected
  FROM katana_stock_sync k
  LEFT JOIN seasonal_selling_policy sp
    ON sp.sku_prefix = regexp_replace(k.sku, '-[^-]+$', '')
  WHERE k.sku NOT LIKE 'katana_%'
    AND k.sku LIKE '%-%'
    AND k.shopify_inventory_policy = 'CONTINUE'
    AND k.manual_override IS NULL
    AND COALESCE(k.effective_stock, 0) <= 0
    AND NOT (
      sp.sku_prefix IS NOT NULL
      AND CASE WHEN sp.start_month <= sp.end_month
        THEN current_month >= sp.start_month AND current_month <= sp.end_month
        ELSE current_month >= sp.start_month OR current_month <= sp.end_month
      END
    )
    AND NOT (
      sp.sku_prefix IS NOT NULL
      AND sp.presale_allowed = true
      AND sp.presale_start_month IS NOT NULL
      AND (
        current_month > sp.presale_start_month
        OR (current_month = sp.presale_start_month AND current_day >= COALESCE(sp.presale_start_day, 1))
      )
    )

  UNION ALL

  -- Type C: Manual override set but Shopify policy doesn't match — push the override
  SELECT
    k.sku, k.katana_variant_id,
    k.shopify_inventory_policy AS current_policy,
    k.manual_override AS target_policy,
    'manual_override'::text AS exception_type,
    'manual override: ' || k.manual_override || ', notes: ' || COALESCE(k.notes, '') AS reason,
    k.effective_stock, k.quantity_in_stock, k.quantity_expected
  FROM katana_stock_sync k
  WHERE k.manual_override IS NOT NULL
    AND k.shopify_inventory_policy != k.manual_override

  ORDER BY sku;
END;
$_$;


ALTER FUNCTION "public"."get_policy_mismatches"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_shopify_daily_stats"("p_date_from" "date", "p_date_to" "date") RETURNS TABLE("date" "date", "shopify_orders" bigint, "shopify_revenue" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    DATE(order_date AT TIME ZONE 'UTC') AS date,
    COUNT(*)::bigint                     AS shopify_orders,
    SUM(total_price)                     AS shopify_revenue
  FROM shopify_orders
  WHERE order_date >= p_date_from::timestamptz
    AND order_date <  (p_date_to + INTERVAL '1 day')::timestamptz
    AND cancelled_at IS NULL
  GROUP BY DATE(order_date AT TIME ZONE 'UTC')
  ORDER BY date;
$$;


ALTER FUNCTION "public"."get_shopify_daily_stats"("p_date_from" "date", "p_date_to" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_stock_digest_exceptions"() RETURNS TABLE("exception_type" "text", "sku" "text", "effective_stock" numeric, "quantity_expected" numeric, "quantity_in_stock" numeric, "shopify_inventory_policy" "text", "notes" "text", "last_changed_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $_$
  WITH current_time_parts AS (
    SELECT
      EXTRACT(MONTH FROM now())::int AS m,
      EXTRACT(DAY FROM now())::int AS d
  )
  -- Genuine overselling risk: CONTINUE with negative stock, no expected,
  -- AND not justified by seasonal window, presale window, or manual override
  SELECT 'overselling_risk'::TEXT, s.sku, s.effective_stock, s.quantity_expected,
    s.quantity_in_stock, s.shopify_inventory_policy, s.notes, s.last_changed_at
  FROM katana_stock_sync s
  LEFT JOIN seasonal_selling_policy sp
    ON sp.sku_prefix = regexp_replace(s.sku, '-[^-]+$', '')
  CROSS JOIN current_time_parts ct
  WHERE s.shopify_inventory_policy = 'CONTINUE'
    AND COALESCE(s.quantity_expected, 0) = 0
    AND COALESCE(s.effective_stock, 0) < 0
    AND s.manual_override IS NULL
    -- Not in selling window
    AND NOT (
      sp.sku_prefix IS NOT NULL
      AND CASE WHEN sp.start_month <= sp.end_month
        THEN ct.m >= sp.start_month AND ct.m <= sp.end_month
        ELSE ct.m >= sp.start_month OR ct.m <= sp.end_month
      END
    )
    -- Not in presale window
    AND NOT (
      sp.sku_prefix IS NOT NULL
      AND sp.presale_allowed = true
      AND sp.presale_start_month IS NOT NULL
      AND (
        ct.m > sp.presale_start_month
        OR (ct.m = sp.presale_start_month AND ct.d >= COALESCE(sp.presale_start_day, 1))
      )
    )

  UNION ALL

  -- Failed corrections — exclude BOM component SKUs (e.g. LATHODO*-SINGLE)
  -- which exist in Katana for manufacturing but deliberately have no Shopify counterpart
  SELECT 'failed_correction'::TEXT, s.sku, s.effective_stock, s.quantity_expected,
    s.quantity_in_stock, s.shopify_inventory_policy, s.notes, s.last_changed_at
  FROM katana_stock_sync s
  WHERE (s.notes ILIKE '%error%' OR s.notes ILIKE '%not found in shopify%')
    AND s.updated_at > now() - INTERVAL '25 hours'
    AND s.sku NOT LIKE '%-SINGLE'
$_$;


ALTER FUNCTION "public"."get_stock_digest_exceptions"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_stock_digest_exceptions"() IS 'Returns overselling risk and failed correction exceptions for the stock digest';



CREATE OR REPLACE FUNCTION "public"."get_table_size_warnings"() RETURNS TABLE("table_name" "text", "row_count" bigint, "warn_at" integer, "alert_at" integer, "status" "text")
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  WITH counts AS (
    SELECT 'reference_sources'              AS tbl, COUNT(*) AS n, 600 AS warn_at, 800 AS alert_at FROM reference_sources              UNION ALL
    SELECT 'content_ecosystem',                     COUNT(*),     600, 800 FROM content_ecosystem              UNION ALL
    SELECT 'content_crosslinks',                    COUNT(*),     600, 800 FROM content_crosslinks              UNION ALL
    SELECT 'content_performance_snapshots',          COUNT(*),     600, 800 FROM content_performance_snapshots  UNION ALL
    SELECT 'content_improvements',                  COUNT(*),     600, 800 FROM content_improvements            UNION ALL
    SELECT 'cosmo_docs',                            COUNT(*),     600, 800 FROM cosmo_docs                      UNION ALL
    SELECT 'wpt_results',                           COUNT(*),     600, 800 FROM wpt_results                     UNION ALL
    SELECT 'garden_locations',                      COUNT(*),     600, 800 FROM garden_locations
  )
  SELECT tbl, n, warn_at, alert_at,
    CASE WHEN n >= alert_at THEN 'red' WHEN n >= warn_at THEN 'amber' ELSE 'green' END
  FROM counts
  ORDER BY n DESC;
$$;


ALTER FUNCTION "public"."get_table_size_warnings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tracklution_campaigns"("p_from" timestamp with time zone, "p_to" timestamp with time zone) RETURNS TABLE("campaign" "text", "source" "text", "events" bigint, "purchases" bigint, "revenue" numeric, "viewed_val" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    utm_campaign                           AS campaign,
    utm_source                             AS source,
    COUNT(*)                               AS events,
    COUNT(*) FILTER (WHERE event_name = 'Purchase')     AS purchases,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'Purchase'), 0)     AS revenue,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'ViewContent'), 0)  AS viewed_val
  FROM tracklution_events
  WHERE received_at >= p_from AND received_at <= p_to
    AND utm_campaign IS NOT NULL
  GROUP BY utm_campaign, utm_source
  ORDER BY events DESC
  LIMIT 20;
$$;


ALTER FUNCTION "public"."get_tracklution_campaigns"("p_from" timestamp with time zone, "p_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tracklution_channel_detail"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_source" "text") RETURNS TABLE("campaign" "text", "events" bigint, "purchases" bigint, "revenue" numeric, "viewed_val" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    COALESCE(utm_campaign, '(no campaign)')  AS campaign,
    COUNT(*)                                 AS events,
    COUNT(*) FILTER (WHERE event_name = 'Purchase')     AS purchases,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'Purchase'), 0)     AS revenue,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'ViewContent'), 0)  AS viewed_val
  FROM tracklution_events
  WHERE received_at >= p_from AND received_at <= p_to
    AND COALESCE(utm_source, '(unattributed)') = p_source
  GROUP BY COALESCE(utm_campaign, '(no campaign)')
  ORDER BY events DESC;
$$;


ALTER FUNCTION "public"."get_tracklution_channel_detail"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tracklution_channels"("p_from" timestamp with time zone, "p_to" timestamp with time zone) RETURNS TABLE("source" "text", "events" bigint, "purchases" bigint, "revenue" numeric, "viewed_val" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    COALESCE(utm_source, '(unattributed)') AS source,
    COUNT(*)                               AS events,
    COUNT(*) FILTER (WHERE event_name = 'Purchase')     AS purchases,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'Purchase'), 0)     AS revenue,
    COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'ViewContent'), 0)  AS viewed_val
  FROM tracklution_events
  WHERE received_at >= p_from AND received_at <= p_to
  GROUP BY COALESCE(utm_source, '(unattributed)')
  ORDER BY events DESC;
$$;


ALTER FUNCTION "public"."get_tracklution_channels"("p_from" timestamp with time zone, "p_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_tracklution_overview"("p_from" timestamp with time zone, "p_to" timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT jsonb_build_object(
    'total',          COUNT(*),
    'purchases',      COUNT(*) FILTER (WHERE event_name = 'Purchase'),
    'views',          COUNT(*) FILTER (WHERE event_name = 'ViewContent'),
    'revenue',        COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'Purchase'), 0),
    'viewedVal',      COALESCE(SUM(value::numeric) FILTER (WHERE event_name = 'ViewContent'), 0),
    'attributed',     COUNT(*) FILTER (WHERE utm_source IS NOT NULL),
    'avgProduct',     COALESCE(AVG(value::numeric) FILTER (WHERE event_name = 'ViewContent'), 0)
  )
  FROM tracklution_events
  WHERE received_at >= p_from AND received_at <= p_to;
$$;


ALTER FUNCTION "public"."get_tracklution_overview"("p_from" timestamp with time zone, "p_to" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer DEFAULT 90) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "statement_timeout" TO '30s'
    AS $$
DECLARE
  v_service_role_key text;
  v_obj record;
  v_request_id bigint;
  v_fired int := 0;
  v_fired_names text[] := ARRAY[]::text[];
  v_cutoff timestamptz := now() - make_interval(days => p_older_than_days);
BEGIN
  -- Read service-role key from Vault
  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'service_role_key not found in vault.secrets',
      'hint', 'Insert via vault.create_secret(key, ''service_role_key'', description)'
    );
  END IF;

  -- Iterate aged, bare-path objects; safety cap 50 per run
  FOR v_obj IN
    SELECT name
    FROM storage.objects
    WHERE bucket_id = 'governance-archive'
      AND name NOT LIKE 'live/%'
      AND created_at < v_cutoff
    ORDER BY created_at
    LIMIT 50
  LOOP
    -- Fire Storage API DELETE (pg_net handles async delivery)
    SELECT net.http_delete(
      url := 'https://cuposlohqvhikyulhrsx.supabase.co/storage/v1/object/governance-archive/'
             || v_obj.name,
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_service_role_key
      ),
      timeout_milliseconds := 10000
    ) INTO v_request_id;

    v_fired := v_fired + 1;
    v_fired_names := v_fired_names || v_obj.name;
  END LOOP;

  RETURN jsonb_build_object(
    'cutoff', v_cutoff,
    'fired_count', v_fired,
    'fired_names', v_fired_names,
    'older_than_days', p_older_than_days,
    'note', 'pg_net deletes processed asynchronously; confirm via net._http_response'
  );
END;
$$;


ALTER FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer) IS 'Nightly prune of governance-archive bucket. Deletes bare-path entries older than p_older_than_days (default 90). Preserves live/ prefix (current-version mirrors). Uses Storage API via pg_net; direct DELETE on storage.objects is blocked. Safety cap: LIMIT 50 per run. Filenames are assumed URL-safe per naming convention; non-ASCII names would need encoding.';



CREATE OR REPLACE FUNCTION "public"."match_order_items_to_species"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_matched int;
BEGIN
  WITH best_match AS (
    -- For each unmatched order item with a SKU, find the katana product
    -- with the longest matching sku_prefix (most specific match)
    SELECT DISTINCT ON (soi.id)
      soi.id as order_item_id,
      kp.id as katana_id,
      kp.species_ref_id,
      kp.cultivar_ref_id
    FROM shopify_order_items soi
    JOIN katana_products kp 
      ON soi.sku LIKE kp.sku_prefix || '%'
      AND kp.species_ref_id IS NOT NULL
    WHERE soi.species_ref_id IS NULL
      AND soi.sku IS NOT NULL 
      AND soi.sku != ''
    ORDER BY soi.id, length(kp.sku_prefix) DESC
  )
  UPDATE shopify_order_items soi
  SET 
    species_ref_id = bm.species_ref_id,
    cultivar_ref_id = bm.cultivar_ref_id,
    katana_product_id = bm.katana_id,
    match_method = 'katana_sku_prefix'
  FROM best_match bm
  WHERE soi.id = bm.order_item_id;

  GET DIAGNOSTICS v_matched = ROW_COUNT;

  RETURN jsonb_build_object(
    'matched', v_matched,
    'method', 'katana_sku_prefix',
    'timestamp', now()
  );
END;
$$;


ALTER FUNCTION "public"."match_order_items_to_species"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_order_items_to_species"("p_since" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_matched int;
BEGIN
  WITH best_match AS (
    SELECT DISTINCT ON (soi.id)
      soi.id as order_item_id,
      kp.id as katana_id,
      kp.species_ref_id,
      kp.cultivar_ref_id
    FROM shopify_order_items soi
    JOIN katana_products kp
      ON soi.sku LIKE kp.sku_prefix || '%'
      AND kp.species_ref_id IS NOT NULL
    WHERE soi.species_ref_id IS NULL
      AND soi.sku IS NOT NULL
      AND soi.sku != ''
      AND (p_since IS NULL OR soi.created_at >= p_since)
    ORDER BY soi.id, length(kp.sku_prefix) DESC
  )
  UPDATE shopify_order_items soi
  SET
    species_ref_id = bm.species_ref_id,
    cultivar_ref_id = bm.cultivar_ref_id,
    katana_product_id = bm.katana_id,
    match_method = 'katana_sku_prefix'
  FROM best_match bm
  WHERE soi.id = bm.order_item_id;

  GET DIAGNOSTICS v_matched = ROW_COUNT;

  RETURN jsonb_build_object(
    'matched', v_matched,
    'method', 'katana_sku_prefix',
    'scope', CASE WHEN p_since IS NULL THEN 'all' ELSE 'since ' || p_since::text END,
    'timestamp', now()
  );
END;
$$;


ALTER FUNCTION "public"."match_order_items_to_species"("p_since" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."report_workflow_health"("p_workflow_id" "text", "p_status" "text" DEFAULT 'success'::"text", "p_error_message" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE workflow_health SET
    last_success_at = CASE WHEN p_status = 'success' THEN now() ELSE last_success_at END,
    last_error_at = CASE WHEN p_status = 'error' THEN now() ELSE last_error_at END,
    last_error_message = CASE WHEN p_status = 'error' THEN p_error_message ELSE last_error_message END,
    updated_at = now()
  WHERE workflow_id = p_workflow_id;
END;
$$;


ALTER FUNCTION "public"."report_workflow_health"("p_workflow_id" "text", "p_status" "text", "p_error_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_placeholder_skus"("mappings" "jsonb") RETURNS TABLE("resolved" integer, "deleted" integer, "remaining" integer)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_resolved INTEGER := 0;
  v_deleted INTEGER := 0;
  v_remaining INTEGER;
BEGIN
  -- Create temp table from JSONB input
  CREATE TEMP TABLE IF NOT EXISTS _sku_map (variant_id INTEGER, real_sku TEXT) ON COMMIT DROP;
  TRUNCATE _sku_map;
  
  INSERT INTO _sku_map (variant_id, real_sku)
  SELECT (item->>'vid')::INTEGER, item->>'sku'
  FROM jsonb_array_elements(mappings) AS item;
  
  -- Delete placeholders where the real SKU already has a row
  DELETE FROM katana_stock_sync
  WHERE sku LIKE 'katana_%'
    AND katana_variant_id IN (
      SELECT katana_variant_id FROM katana_stock_sync WHERE sku NOT LIKE 'katana_%'
    );
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  
  -- Update remaining placeholders
  UPDATE katana_stock_sync k
  SET sku = m.real_sku
  FROM _sku_map m
  WHERE k.katana_variant_id = m.variant_id
    AND k.sku LIKE 'katana_%'
    AND NOT EXISTS (SELECT 1 FROM katana_stock_sync WHERE sku = m.real_sku AND sku != k.sku);
  GET DIAGNOSTICS v_resolved = ROW_COUNT;
  
  SELECT count(*) INTO v_remaining FROM katana_stock_sync WHERE sku LIKE 'katana_%';
  
  RETURN QUERY SELECT v_resolved, v_deleted, v_remaining;
END;
$$;


ALTER FUNCTION "public"."resolve_placeholder_skus"("mappings" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_status_code int;
  v_content text;
  v_error_msg text;
  v_parsed jsonb;
BEGIN
  SELECT status_code, content, error_msg
    INTO v_status_code, v_content, v_error_msg
    FROM net._http_response
    WHERE id = p_request_id;

  IF v_status_code IS NULL AND v_error_msg IS NULL THEN
    RETURN jsonb_build_object('pending', true, 'request_id', p_request_id);
  END IF;

  IF v_error_msg IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', v_error_msg,
      'request_id', p_request_id
    );
  END IF;

  IF v_status_code < 200 OR v_status_code >= 300 THEN
    BEGIN
      v_parsed := v_content::jsonb;
    EXCEPTION WHEN OTHERS THEN
      v_parsed := to_jsonb(v_content);
    END;
    RETURN jsonb_build_object(
      'error', 'non-success HTTP status',
      'status_code', v_status_code,
      'response', v_parsed,
      'request_id', p_request_id
    );
  END IF;

  BEGIN
    v_parsed := v_content::jsonb;
  EXCEPTION WHEN OTHERS THEN
    v_parsed := to_jsonb(v_content);
  END;

  RETURN jsonb_build_object(
    'status_code', v_status_code,
    'response', v_parsed,
    'request_id', p_request_id
  );
END;
$$;


ALTER FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) IS 'Phase 2 of the two-phase supersession pattern. Reads pg_net response for a prior fire() call. Returns {pending: true} if response not yet committed, {error, status_code?, response?, request_id} on failure, or {status_code, response, request_id} on success. The response field is the EF''s parsed JSON body.';



CREATE OR REPLACE FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "statement_timeout" TO '15s'
    AS $$
DECLARE
  v_service_role_key text;
  v_request_id bigint;
BEGIN
  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key'
  LIMIT 1;

  IF v_service_role_key IS NULL THEN
    RETURN jsonb_build_object(
      'error', 'service_role_key not found in vault.secrets',
      'hint', 'Insert via vault.create_secret(key, ''service_role_key'', description)'
    );
  END IF;

  SELECT net.http_post(
    url := 'https://cuposlohqvhikyulhrsx.supabase.co/functions/v1/supersede-and-archive',
    body := jsonb_build_object(
      'base_pattern', p_base_pattern,
      'new_filename', p_new_filename
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
    ),
    timeout_milliseconds := 30000
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'request_id', v_request_id,
    'fired_at', now(),
    'base_pattern', p_base_pattern,
    'new_filename', p_new_filename
  );
END;
$$;


ALTER FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") IS 'Phase 1 of the two-phase supersession pattern. Invokes the supersede-and-archive Edge Function via pg_net with the service-role JWT from vault.secrets. Returns the pg_net request_id. The caller then calls supersede_and_archive_check(request_id) after ~2-5s to retrieve the EF response. See SYS-mcp-primary-paths-v1_2.md (or successor).';



CREATE OR REPLACE FUNCTION "public"."sync_shopify_orders"("p_orders" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_order jsonb;
  v_item jsonb;
  v_customer_uuid uuid;
  v_order_uuid uuid;
  v_customers_upserted int := 0;
  v_orders_upserted int := 0;
  v_items_upserted int := 0;
  v_customer_obj jsonb;
  v_address_obj jsonb;
  v_match_result jsonb;
  v_sync_start timestamptz := now();
BEGIN
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_customer_obj := v_order->'customer';
    v_address_obj := v_customer_obj->'default_address';

    IF v_customer_obj IS NULL OR v_customer_obj->>'id' IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO shopify_customers (
      shopify_customer_id, email, first_name, last_name,
      postcode, city, county, country_code, updated_at
    )
    VALUES (
      (v_customer_obj->>'id')::bigint,
      COALESCE(v_customer_obj->>'email', ''),
      v_customer_obj->>'first_name',
      v_customer_obj->>'last_name',
      v_address_obj->>'zip',
      v_address_obj->>'city',
      v_address_obj->>'province',
      COALESCE(v_address_obj->>'country_code', 'GB'),
      now()
    )
    ON CONFLICT (shopify_customer_id) DO UPDATE SET
      email = COALESCE(EXCLUDED.email, shopify_customers.email),
      first_name = COALESCE(EXCLUDED.first_name, shopify_customers.first_name),
      last_name = COALESCE(EXCLUDED.last_name, shopify_customers.last_name),
      postcode = COALESCE(EXCLUDED.postcode, shopify_customers.postcode),
      city = COALESCE(EXCLUDED.city, shopify_customers.city),
      county = COALESCE(EXCLUDED.county, shopify_customers.county),
      country_code = COALESCE(EXCLUDED.country_code, shopify_customers.country_code),
      updated_at = now()
    RETURNING id INTO v_customer_uuid;
    v_customers_upserted := v_customers_upserted + 1;

    INSERT INTO shopify_orders (
      shopify_order_id, order_number, customer_id, order_date,
      fulfillment_status, financial_status, cancelled_at,
      total_price, updated_at
    )
    VALUES (
      (v_order->>'id')::bigint,
      COALESCE(v_order->>'order_number', v_order->>'name', ''),
      v_customer_uuid,
      (v_order->>'created_at')::timestamptz,
      v_order->>'fulfillment_status',
      v_order->>'financial_status',
      NULLIF(v_order->>'cancelled_at', '')::timestamptz,
      -- current_total_price is Shopify's post-refund order total
      NULLIF(v_order->>'current_total_price', '')::numeric,
      now()
    )
    ON CONFLICT (shopify_order_id) DO UPDATE SET
      fulfillment_status = EXCLUDED.fulfillment_status,
      financial_status   = EXCLUDED.financial_status,
      cancelled_at       = EXCLUDED.cancelled_at,
      total_price        = EXCLUDED.total_price,
      updated_at         = now()
    RETURNING id INTO v_order_uuid;
    v_orders_upserted := v_orders_upserted + 1;

    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_order->'line_items', '[]'::jsonb)) LOOP
      INSERT INTO shopify_order_items (
        shopify_line_item_id, order_id, product_title, variant_title,
        sku, quantity, unit_price, shopify_product_id
      )
      VALUES (
        (v_item->>'id')::bigint,
        v_order_uuid,
        COALESCE(v_item->>'title', ''),
        v_item->>'variant_title',
        v_item->>'sku',
        COALESCE((v_item->>'quantity')::int, 1),
        (v_item->>'price')::numeric,
        NULLIF(v_item->>'product_id', '')::bigint
      )
      ON CONFLICT (shopify_line_item_id) DO UPDATE SET
        product_title = EXCLUDED.product_title,
        variant_title = EXCLUDED.variant_title,
        sku           = EXCLUDED.sku,
        quantity      = EXCLUDED.quantity,
        unit_price    = EXCLUDED.unit_price;
      v_items_upserted := v_items_upserted + 1;
    END LOOP;
  END LOOP;

  -- Bounded matcher: only match items from this sync window
  SELECT match_order_items_to_species(v_sync_start - interval '5 minutes') INTO v_match_result;

  RETURN jsonb_build_object(
    'customers_upserted', v_customers_upserted,
    'orders_upserted',    v_orders_upserted,
    'items_upserted',     v_items_upserted,
    'species_matched',    COALESCE((v_match_result->>'matched')::int, 0)
  );
END;
$$;


ALTER FUNCTION "public"."sync_shopify_orders"("p_orders" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_katana_stock_sync_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_katana_stock_sync_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_collection_segments" (
    "id" bigint NOT NULL,
    "collection_sku" "text" NOT NULL,
    "segment_name" "text" NOT NULL,
    "segment_order" integer NOT NULL,
    "pack_size" integer NOT NULL,
    "qty_per_pack_fixed" integer,
    "singles_floor" integer DEFAULT 50 NOT NULL,
    "emptiness_tolerance" integer DEFAULT 3 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sweetpea_collection_segments_qty_per_pack_fixed_check" CHECK ((("qty_per_pack_fixed" IS NULL) OR ("qty_per_pack_fixed" > 0)))
);


ALTER TABLE "archive_sweetpea"."sweetpea_collection_segments" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_collection_segments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_collection_segments_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_collection_segments_id_seq" OWNED BY "archive_sweetpea"."sweetpea_collection_segments"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_colour_map" (
    "variety_stub" "text" NOT NULL,
    "variety_name" "text" NOT NULL,
    "single_sku" "text" NOT NULL,
    "colour_category" "text" NOT NULL,
    "in_cottage_pool" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "assigned_by" "text",
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "valid_colour_category" CHECK (("colour_category" = ANY (ARRAY['red_scarlet'::"text", 'salmon_coral'::"text", 'cream_ivory'::"text", 'pink'::"text", 'maroon_claret_near_black'::"text", 'purple_violet'::"text", 'light_blue'::"text", 'dark_blue'::"text", 'other'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_colour_map" OWNER TO "postgres";


COMMENT ON TABLE "archive_sweetpea"."sweetpea_colour_map" IS 'Colour-wheel category for each sweet pea variety. Used by Phase 4 Cottage Garden Mix pool selection to ensure colour spread. Categories mirror the Ashridge 7-segment sweet pea colour wheel. in_cottage_pool=false excludes a variety from pool selection (e.g. Turquoise Lagoon). A new LATHODO* variety must have a row in this table before it can be added to any BOM collection recipe — see GOV-product-creation-process.';



COMMENT ON COLUMN "archive_sweetpea"."sweetpea_colour_map"."variety_stub" IS 'LATHODO prefix without suffix, e.g. LATHODOALMBL. The natural variety identity across all SKU forms (SINGLE, Pack of 4, etc.).';



COMMENT ON COLUMN "archive_sweetpea"."sweetpea_colour_map"."single_sku" IS 'The -SINGLE SKU for convenient JOIN against bom_collection_components.component_sku.';



COMMENT ON COLUMN "archive_sweetpea"."sweetpea_colour_map"."colour_category" IS 'One of the 7 Ashridge colour-wheel segments, or "other" for varieties outside the wheel (paired with in_cottage_pool=false).';



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_error_state" (
    "id" bigint NOT NULL,
    "detected_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "text" NOT NULL,
    "subcategory" "text",
    "severity" "text" NOT NULL,
    "detector" "text" NOT NULL,
    "affected_sku" "text",
    "affected_mo_id" bigint,
    "detail" "jsonb" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "acknowledged_at" timestamp with time zone,
    "acknowledged_by" "text",
    "resolved_at" timestamp with time zone,
    "resolved_by" "text",
    "resolution_notes" "text",
    CONSTRAINT "sweetpea_error_state_severity_check" CHECK (("severity" = ANY (ARRAY['critical'::"text", 'warning'::"text", 'info'::"text"]))),
    CONSTRAINT "sweetpea_error_state_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'acknowledged'::"text", 'auto_resolved'::"text", 'resolved'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_error_state" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_error_state_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_error_state_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_error_state_id_seq" OWNED BY "archive_sweetpea"."sweetpea_error_state"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_forecast_update_queue" (
    "id" bigint NOT NULL,
    "sku" "text" NOT NULL,
    "enqueued_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "triggered_by" "text" NOT NULL,
    "processed_at" timestamp with time zone
);


ALTER TABLE "archive_sweetpea"."sweetpea_forecast_update_queue" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq" OWNED BY "archive_sweetpea"."sweetpea_forecast_update_queue"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_katana_mo_status_cache" (
    "mo_id" bigint NOT NULL,
    "katana_status" "text" NOT NULL,
    "fetched_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "archive_sweetpea"."sweetpea_katana_mo_status_cache" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_actual_composition" (
    "id" bigint NOT NULL,
    "mo_id" bigint NOT NULL,
    "pack_number" integer NOT NULL,
    "single_sku" "text" NOT NULL,
    "qty_in_pack" integer NOT NULL,
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "recorded_by" "text" NOT NULL,
    "substitution_reason" "text",
    CONSTRAINT "sweetpea_mo_actual_composition_qty_in_pack_check" CHECK (("qty_in_pack" > 0))
);


ALTER TABLE "archive_sweetpea"."sweetpea_mo_actual_composition" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq" OWNED BY "archive_sweetpea"."sweetpea_mo_actual_composition"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_recipe_audit" (
    "id" bigint NOT NULL,
    "mo_id" bigint NOT NULL,
    "recipe_row_id" bigint,
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "changed_by" "text" NOT NULL,
    "action" "text" NOT NULL,
    "old_single_sku" "text",
    "new_single_sku" "text",
    "old_qty_per_pack" integer,
    "new_qty_per_pack" integer,
    "old_segment_name" "text",
    "new_segment_name" "text",
    "reason" "text",
    CONSTRAINT "sweetpea_mo_recipe_audit_action_check" CHECK (("action" = ANY (ARRAY['insert'::"text", 'update'::"text", 'delete'::"text", 'lock'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_mo_recipe_audit" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq" OWNED BY "archive_sweetpea"."sweetpea_mo_recipe_audit"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_recipes" (
    "id" bigint NOT NULL,
    "mo_id" bigint NOT NULL,
    "single_sku" "text" NOT NULL,
    "qty_per_pack" integer NOT NULL,
    "segment_name" "text",
    "locked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sweetpea_mo_recipes_qty_per_pack_check" CHECK (("qty_per_pack" > 0))
);


ALTER TABLE "archive_sweetpea"."sweetpea_mo_recipes" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_mo_recipes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_recipes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_mo_recipes_id_seq" OWNED BY "archive_sweetpea"."sweetpea_mo_recipes"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_pending_mos" (
    "sku" "text" NOT NULL,
    "katana_mo_id" integer,
    "katana_variant_id" integer NOT NULL,
    "planned_quantity" integer NOT NULL,
    "cg_recipe" "jsonb",
    "opened_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" bigint NOT NULL,
    "status" "text" DEFAULT 'pending_katana_create'::"text" NOT NULL,
    "flavour" "text" DEFAULT 'reservation'::"text" NOT NULL,
    "promoted_to_executable_at" timestamp with time zone,
    "forecast_snapshot" "jsonb",
    CONSTRAINT "sweetpea_pending_mos_flavour_check" CHECK (("flavour" = ANY (ARRAY['reservation'::"text", 'executable'::"text"]))),
    CONSTRAINT "sweetpea_pending_mos_planned_quantity_check" CHECK (("planned_quantity" >= 0)),
    CONSTRAINT "sweetpea_pending_mos_status_check" CHECK (("status" = ANY (ARRAY['pending_katana_create'::"text", 'NOT_STARTED'::"text", 'IN_PROGRESS'::"text", 'completed'::"text", 'cancelled'::"text", 'mo_error'::"text", 'blocked_on_supply'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_pending_mos" OWNER TO "postgres";


COMMENT ON TABLE "archive_sweetpea"."sweetpea_pending_mos" IS 'One row per sweet pea pack/collection SKU with a currently-open append-target Katana MO. Populated by sweetpea-order-mo Edge Function.';



COMMENT ON COLUMN "archive_sweetpea"."sweetpea_pending_mos"."cg_recipe" IS 'Cottage Garden only: JSON array recording the 8 pool members chosen for this MO, used for line-replacement logic. NULL for fixed-recipe SKUs.';



CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_pending_mos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_pending_mos_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_pending_mos_id_seq" OWNED BY "archive_sweetpea"."sweetpea_pending_mos"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_safety_stock_audit" (
    "id" bigint NOT NULL,
    "sku" "text" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "changed_by" "text" NOT NULL,
    "field" "text" NOT NULL,
    "old_value" "text",
    "new_value" "text",
    "reason" "text",
    CONSTRAINT "sweetpea_safety_stock_audit_field_check" CHECK (("field" = ANY (ARRAY['singles_safety_stock'::"text", 'expected_supply'::"text", 'expected_supply_confidence'::"text", 'forecast_notes'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_safety_stock_audit" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq" OWNED BY "archive_sweetpea"."sweetpea_safety_stock_audit"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_stock_movement_log" (
    "id" bigint NOT NULL,
    "sku" "text" NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "delta" integer NOT NULL,
    "source" "text" NOT NULL,
    "source_id" "text",
    "notes" "text"
);


ALTER TABLE "archive_sweetpea"."sweetpea_stock_movement_log" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "archive_sweetpea"."sweetpea_stock_movement_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "archive_sweetpea"."sweetpea_stock_movement_log_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "archive_sweetpea"."sweetpea_stock_movement_log_id_seq" OWNED BY "archive_sweetpea"."sweetpea_stock_movement_log"."id";



CREATE TABLE IF NOT EXISTS "archive_sweetpea"."sweetpea_webhook_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shopify_order_id" bigint NOT NULL,
    "shopify_order_number" "text",
    "event_type" "text" NOT NULL,
    "sku" "text",
    "quantity" integer,
    "processed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "mo_id" integer,
    "action" "text",
    "notes" "text",
    "raw_payload" "jsonb",
    "alerted_at" timestamp with time zone,
    CONSTRAINT "sweetpea_webhook_log_event_type_check" CHECK (("event_type" = ANY (ARRAY['create'::"text", 'cancel'::"text"])))
);


ALTER TABLE "archive_sweetpea"."sweetpea_webhook_log" OWNER TO "postgres";


COMMENT ON TABLE "archive_sweetpea"."sweetpea_webhook_log" IS 'Append-only log of every Shopify webhook processed by sweetpea-order-mo Edge Function. Acts as idempotency check (unique on order+sku+event) and audit trail.';



COMMENT ON COLUMN "archive_sweetpea"."sweetpea_webhook_log"."alerted_at" IS 'Set by monitor-bom-stock when a mo_held_low_singles row is included in a Slack post. NULL means not yet alerted.';



CREATE TABLE IF NOT EXISTS "public"."ai_search_daily" (
    "date" "date" NOT NULL,
    "ai_platform" "text" NOT NULL,
    "landing_page_path" "text" NOT NULL,
    "distinct_sessions" integer,
    "view_item_events" integer,
    "purchase_events" integer,
    "purchase_revenue" numeric(10,2),
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ai_search_daily" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."alert_schedule" (
    "id" integer NOT NULL,
    "alert_type" "text" DEFAULT 'stock_report'::"text" NOT NULL,
    "day_of_week" smallint NOT NULL,
    "report_time" time without time zone NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "recipient_label" "text",
    "webhook_secret_name" "text" DEFAULT 'SLACK_WEBHOOK_URL_JAIMIE'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "alert_schedule_day_of_week_check" CHECK ((("day_of_week" >= 0) AND ("day_of_week" <= 6)))
);


ALTER TABLE "public"."alert_schedule" OWNER TO "postgres";


COMMENT ON TABLE "public"."alert_schedule" IS 'Controls when batch Slack alerts fire. day_of_week: 0=Sunday, 6=Saturday. report_time in Europe/London.';



COMMENT ON COLUMN "public"."alert_schedule"."webhook_secret_name" IS 'Name of the Supabase secret holding the Slack incoming webhook URL';



CREATE SEQUENCE IF NOT EXISTS "public"."alert_schedule_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."alert_schedule_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."alert_schedule_id_seq" OWNED BY "public"."alert_schedule"."id";



CREATE TABLE IF NOT EXISTS "public"."attribution_channel_daily" (
    "date" "date" NOT NULL,
    "channel" "text" NOT NULL,
    "ai_platform" "text" DEFAULT ''::"text" NOT NULL,
    "purchase_events" integer,
    "purchase_revenue" numeric(10,2),
    "view_item_events" integer,
    "distinct_sessions" integer,
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."attribution_channel_daily" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attribution_daily_snapshot" (
    "date" "date" NOT NULL,
    "elevar_purchase_events" integer,
    "elevar_purchase_revenue" numeric(10,2),
    "shopify_orders" integer,
    "shopify_revenue" numeric(10,2),
    "ga4_transactions" integer,
    "ga4_revenue" numeric(10,2),
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."attribution_daily_snapshot" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."backfill_state" (
    "id" "text" NOT NULL,
    "operation_id" "text",
    "status" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."backfill_state" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."blog_articles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shopify_article_id" "text",
    "blog_handle" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text",
    "body_html" "text",
    "body_html_clean" "text",
    "seo_title" "text",
    "seo_description" "text",
    "author" "text",
    "tags" "text"[],
    "shopify_status" "text",
    "published_at" timestamp with time zone,
    "shopify_created_at" timestamp with time zone,
    "shopify_updated_at" timestamp with time zone,
    "synced_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."blog_articles" OWNER TO "postgres";


COMMENT ON TABLE "public"."blog_articles" IS 'Canonical store for all Ashridge blog article content. Source of truth for content auditing and AI citability work. Synced from Shopify via n8n workflow. Created 16 Apr 2026.';



CREATE TABLE IF NOT EXISTS "public"."bom_collection_components" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pack_variant_id" integer NOT NULL,
    "component_variant_id" integer NOT NULL,
    "component_sku" "text" NOT NULL,
    "quantity" integer DEFAULT 1 NOT NULL,
    "is_pool_member" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."bom_collection_components" OWNER TO "postgres";


COMMENT ON TABLE "public"."bom_collection_components" IS 'Component recipes for collections (fixed recipes) and pool members for variable collections (pool picks). Pool collections pick N from a larger pool based on stock availability.';



COMMENT ON COLUMN "public"."bom_collection_components"."is_pool_member" IS 'true = pool pick (monitoring selects based on availability), false = fixed recipe component with exact quantity.';



CREATE TABLE IF NOT EXISTS "public"."bom_monitoring_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "pack_variant_id" integer NOT NULL,
    "pack_sku" "text" NOT NULL,
    "pack_product_name" "text",
    "component_variant_id" integer,
    "component_sku" "text",
    "bom_multiplier" integer DEFAULT 4 NOT NULL,
    "collection_type" "text",
    "safety_stock" integer DEFAULT 50 NOT NULL,
    "target_stock" integer DEFAULT 70 NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "last_checked_at" timestamp with time zone,
    "last_mo_order_no" "text",
    "last_mo_created_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "bom_monitoring_config_collection_type_check" CHECK (("collection_type" = ANY (ARRAY['fixed'::"text", 'pool'::"text"]))),
    CONSTRAINT "bom_monitoring_config_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'sell_through'::"text", 'exhausted'::"text"])))
);


ALTER TABLE "public"."bom_monitoring_config" OWNER TO "postgres";


COMMENT ON TABLE "public"."bom_monitoring_config" IS 'BOM monitoring parameters for sellable pack variants. Monitoring Edge Function reads this to determine safety stock, target stock, and component mappings.';



COMMENT ON COLUMN "public"."bom_monitoring_config"."collection_type" IS 'NULL for single-variety packs (use component_variant_id). fixed = fixed recipe in bom_collection_components. pool = pick N from pool in bom_collection_components.';



CREATE TABLE IF NOT EXISTS "public"."bulb_label_staging" (
    "handle" "text" NOT NULL,
    "label_text" "text" NOT NULL,
    "shopify_gid" bigint,
    "written" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."bulb_label_staging" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."care_instruction_sources" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "care_instruction_id" "uuid" NOT NULL,
    "source_type" "text" NOT NULL,
    "reference_source_id" "uuid",
    "source_name" "text" NOT NULL,
    "source_url" "text",
    "source_detail" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "care_instruction_sources_source_type_check" CHECK (("source_type" = ANY (ARRAY['reference_source'::"text", 'web_article'::"text", 'pdf_document'::"text", 'expert_knowledge'::"text", 'database_extract'::"text"])))
);


ALTER TABLE "public"."care_instruction_sources" OWNER TO "postgres";


COMMENT ON TABLE "public"."care_instruction_sources" IS 'Audit trail: which sources contributed to each approved care instruction. One row per source per instruction.';



CREATE TABLE IF NOT EXISTS "public"."care_instructions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "care_profile_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "instruction_text" "text" NOT NULL,
    "trigger_type" "text" NOT NULL,
    "trigger_month" integer,
    "trigger_offset_value" integer,
    "trigger_offset_unit" "text",
    "plant_age_min_years" integer DEFAULT 0 NOT NULL,
    "plant_age_max_years" integer,
    "priority" integer DEFAULT 5 NOT NULL,
    "content_type" "text" NOT NULL,
    "source_pages" "text"[],
    "cloudinary_image_tag" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "embedding" "extensions"."vector"(1536),
    CONSTRAINT "care_instructions_content_type_check" CHECK (("content_type" = ANY (ARRAY['planting'::"text", 'watering'::"text", 'feeding'::"text", 'pruning'::"text", 'protection'::"text", 'aftercare'::"text", 'troubleshoot'::"text", 'seasonal-tip'::"text", 'sales-hook'::"text", 'tidbit'::"text"]))),
    CONSTRAINT "care_instructions_priority_check" CHECK ((("priority" >= 1) AND ("priority" <= 10))),
    CONSTRAINT "care_instructions_trigger_month_check" CHECK ((("trigger_month" >= 1) AND ("trigger_month" <= 12))),
    CONSTRAINT "care_instructions_trigger_offset_unit_check" CHECK (("trigger_offset_unit" = ANY (ARRAY['weeks'::"text", 'months'::"text", 'years'::"text"]))),
    CONSTRAINT "care_instructions_trigger_type_check" CHECK (("trigger_type" = ANY (ARRAY['month'::"text", 'weeks-after-purchase'::"text", 'months-after-purchase'::"text", 'years-after-purchase'::"text", 'event'::"text"])))
);


ALTER TABLE "public"."care_instructions" OWNER TO "postgres";


COMMENT ON TABLE "public"."care_instructions" IS 'Individual care advice items. Each row is one modular instruction (max 300 words) with a temporal trigger.';



CREATE TABLE IF NOT EXISTS "public"."care_profiles" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "genus" "text",
    "group_type" "text",
    "context" "text" NOT NULL,
    "plant_size_at_sale" "text",
    "lifecycle_type" "text" NOT NULL,
    "lifecycle_duration_years" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "species_ref_id" "uuid",
    CONSTRAINT "care_profiles_lifecycle_type_check" CHECK (("lifecycle_type" = ANY (ARRAY['annual'::"text", 'annual-bulb'::"text", 'perennial'::"text"])))
);


ALTER TABLE "public"."care_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."care_profiles" IS 'Grouping unit for shared care instructions. One profile = one combination of genus/group/context/size.';



CREATE TABLE IF NOT EXISTS "public"."checkout_funnel_daily" (
    "date" "date" NOT NULL,
    "view_sessions" integer,
    "cart_sessions" integer,
    "checkout_sessions" integer,
    "shipping_sessions" integer,
    "payment_sessions" integer,
    "completed_sessions" integer,
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."checkout_funnel_daily" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cloudinary_quality" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asset_id" "text" NOT NULL,
    "public_id" "text" NOT NULL,
    "folder" "text",
    "filename" "text",
    "format" "text",
    "width" integer,
    "height" integer,
    "bytes" integer,
    "focus_score" numeric,
    "iqa_score" numeric,
    "iqa_decision" "text",
    "tags" "text"[],
    "cloudinary_created_at" timestamp with time zone,
    "analysed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cloudinary_quality" OWNER TO "postgres";


COMMENT ON TABLE "public"."cloudinary_quality" IS 'Image quality scores from Cloudinary quality_analysis API. Stores focus and IQA scores to avoid redundant API calls and enable bulk querying.';



CREATE TABLE IF NOT EXISTS "public"."collection_urls" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "display_name" "text",
    "category" "text",
    "genus" "text",
    "species_ref_id" "uuid",
    "is_curated" boolean DEFAULT false NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "shopify_collection_id" bigint,
    "product_count" integer,
    "last_verified" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."collection_urls" OWNER TO "postgres";


COMMENT ON TABLE "public"."collection_urls" IS 'Ashridge Shopify collection URLs. Source of truth for internal linking in PDPs and guides. Initial load from site crawl; ongoing sync from Shopify API via n8n.';



COMMENT ON COLUMN "public"."collection_urls"."slug" IS 'The /collections/[slug] path — relative, no domain prefix';



COMMENT ON COLUMN "public"."collection_urls"."is_curated" IS 'True for editorial/best-of collections (best-garden-cherry-varieties) vs genus/product collections';



COMMENT ON COLUMN "public"."collection_urls"."shopify_collection_id" IS 'Shopify collection ID — populated by API sync';



CREATE TABLE IF NOT EXISTS "public"."content_crosslinks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "from_page_id" "uuid" NOT NULL,
    "to_page_id" "uuid" NOT NULL,
    "link_type" "text" NOT NULL,
    "verified_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "content_crosslinks_link_type_check" CHECK (("link_type" = ANY (ARRAY['internal_nav'::"text", 'related_guide'::"text", 'product_bridge'::"text", 'related_questions'::"text", 'in_body'::"text"])))
);


ALTER TABLE "public"."content_crosslinks" OWNER TO "postgres";


COMMENT ON TABLE "public"."content_crosslinks" IS 'Directional cross-links between content_ecosystem pages. verified_at tracks when the link was last confirmed live. Inbound link count per page drives the leverage component of the priority score.';



CREATE TABLE IF NOT EXISTS "public"."content_ecosystem" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "page_number" integer,
    "title" "text" NOT NULL,
    "short_title" "text",
    "page_type" "text" NOT NULL,
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "grade" "text",
    "slug" "text",
    "primary_keyword" "text",
    "search_volume" integer,
    "traffic_potential" integer,
    "target_keywords" "jsonb" DEFAULT '[]'::"jsonb",
    "factual_lead" "text",
    "related_questions" "jsonb" DEFAULT '[]'::"jsonb",
    "faqs" "jsonb" DEFAULT '[]'::"jsonb",
    "product_bridge" "jsonb" DEFAULT '[]'::"jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "competition_score" integer,
    CONSTRAINT "content_ecosystem_competition_score_check" CHECK ((("competition_score" >= 0) AND ("competition_score" <= 10))),
    CONSTRAINT "content_ecosystem_grade_check" CHECK (("grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'F'::"text"]))),
    CONSTRAINT "content_ecosystem_page_type_check" CHECK (("page_type" = ANY (ARRAY['pillar'::"text", 'guide'::"text", 'buying_guide'::"text", 'reference'::"text", 'comparison'::"text"]))),
    CONSTRAINT "content_ecosystem_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'drafted'::"text", 'needs_audit'::"text", 'published'::"text"])))
);


ALTER TABLE "public"."content_ecosystem" OWNER TO "postgres";


COMMENT ON TABLE "public"."content_ecosystem" IS 'Advice page ecosystem outlines — one row per planned or existing page, with FAQ checklists, related questions, and product bridge links. Drives the content production dashboard.';



COMMENT ON COLUMN "public"."content_ecosystem"."competition_score" IS 'Competitive pressure score 0-10, updated after each DataForSEO measurement run. 0 = no competitor coverage, 10 = dominated by multiple strong competitors.';



CREATE TABLE IF NOT EXISTS "public"."content_feed_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "title" "text" NOT NULL,
    "url" "text" NOT NULL,
    "source_name" "text" NOT NULL,
    "source_feed_url" "text",
    "published_at" timestamp with time zone,
    "summary" "text",
    "categories" "text"[],
    "relevance_tag" "text",
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "extracted_to" "uuid",
    "feedly_entry_id" "text",
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source_type" "text" DEFAULT 'feedly'::"text" NOT NULL,
    "content_body" "text",
    "extraction_result" "jsonb",
    "extracted_at" timestamp with time zone,
    CONSTRAINT "content_feed_items_relevance_tag_check" CHECK (("relevance_tag" = ANY (ARRAY['lavender'::"text", 'clematis'::"text", 'dahlia'::"text", 'sweet-pea'::"text", 'cosmos'::"text", 'spring-bulb'::"text", 'rose'::"text", 'hedging'::"text", 'fruit-tree'::"text", 'salvia'::"text", 'general-gardening'::"text", 'rhs'::"text", 'media-coverage'::"text", 'competitor'::"text", 'culinary-craft'::"text", 'wildlife-pollinators'::"text", 'climate-weather'::"text", 'pests-diseases'::"text", 'unknown'::"text", 'perennials'::"text", 'shrubs'::"text", 'trees'::"text", 'bulbs'::"text", 'soft-fruit'::"text", 'climbers'::"text", 'fruit-trees'::"text", 'dahlias'::"text", 'sweet-peas'::"text", 'roses'::"text"]))),
    CONSTRAINT "content_feed_items_source_type_check" CHECK (("source_type" = ANY (ARRAY['feedly'::"text", 'sitemap_crawl'::"text", 'crawl'::"text"]))),
    CONSTRAINT "content_feed_items_status_check" CHECK (("status" = ANY (ARRAY['new'::"text", 'relevant'::"text", 'irrelevant'::"text", 'processed'::"text", 'knowledge-extracted'::"text"])))
);


ALTER TABLE "public"."content_feed_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."content_feed_items" IS 'Incoming content signals from Feedly via n8n. Each row is an article or broadcast episode guide that the monitoring pipeline has found. Items are triaged by relevance, and relevant ones are sent to the Claude API for knowledge extraction into knowledge_staging.';



COMMENT ON COLUMN "public"."content_feed_items"."source_type" IS 'Origin of this item: feedly = RSS via Feedly, sitemap_crawl = discovered via monitored site sitemap diffing.';



COMMENT ON COLUMN "public"."content_feed_items"."content_body" IS 'Full page content as markdown. Populated at crawl time for sitemap_crawl items; NULL for feedly items (fetched at extraction time).';



COMMENT ON COLUMN "public"."content_feed_items"."extraction_result" IS 'Raw JSON from Claude API extraction prompt — varieties, tags, FAQs, growing advice, tidbits, companions';



COMMENT ON COLUMN "public"."content_feed_items"."extracted_at" IS 'When this page was processed by the extraction pipeline';



CREATE TABLE IF NOT EXISTS "public"."content_improvements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content_ecosystem_id" "uuid",
    "category" "text" NOT NULL,
    "page_slug" "text",
    "priority" integer NOT NULL,
    "description" "text" NOT NULL,
    "improvement_type" "text",
    "status" "text" DEFAULT 'planned'::"text" NOT NULL,
    "published_at" timestamp with time zone,
    "search_impact_query" "text",
    "search_impact_volume" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "content_improvements_improvement_type_check" CHECK (("improvement_type" = ANY (ARRAY['structure'::"text", 'content'::"text", 'seo'::"text", 'citability'::"text", 'new_page'::"text"]))),
    CONSTRAINT "content_improvements_status_check" CHECK (("status" = ANY (ARRAY['planned'::"text", 'in_progress'::"text", 'published'::"text", 'deferred'::"text"])))
);


ALTER TABLE "public"."content_improvements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_performance_snapshots" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content_ecosystem_id" "uuid",
    "category" "text" NOT NULL,
    "page_slug" "text",
    "snapshot_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "snapshot_type" "text" NOT NULL,
    "ahrefs_traffic" integer,
    "ahrefs_keywords_top3" integer,
    "ahrefs_keywords_top10" integer,
    "ahrefs_keywords_total" integer,
    "citability_queries_tested" integer,
    "citability_queries_cited" integer,
    "citability_platforms_tested" "text"[],
    "citability_top_competitors" "jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "content_performance_snapshots_snapshot_type_check" CHECK (("snapshot_type" = ANY (ARRAY['baseline'::"text", 'periodic'::"text", 'post_publish'::"text"])))
);


ALTER TABLE "public"."content_performance_snapshots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cosmo_docs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "type" "text" NOT NULL,
    "status" "text" DEFAULT 'live'::"text" NOT NULL,
    "tags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "summary" "text" NOT NULL,
    "usage_notes" "text",
    "calling_pattern" "text",
    "dependencies" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "notes" "text",
    "version" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "body" "text",
    CONSTRAINT "cosmo_docs_status_check" CHECK (("status" = ANY (ARRAY['live'::"text", 'designed'::"text", 'diagnostic'::"text", 'retired'::"text"]))),
    CONSTRAINT "cosmo_docs_type_check" CHECK (("type" = ANY (ARRAY['edge_function'::"text", 'database_table'::"text", 'database_view'::"text", 'n8n_workflow'::"text", 'pipeline'::"text", 'dashboard'::"text", 'governance_file'::"text", 'external_tool'::"text", 'process'::"text"])))
);


ALTER TABLE "public"."cosmo_docs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cultivar_pest_disease" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cultivar_id" "uuid" NOT NULL,
    "pest_disease_id" "uuid" NOT NULL,
    "relationship" "text" NOT NULL,
    "notes" "text",
    "source_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cultivar_pest_disease" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cultivar_reference" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cultivar_name" "text" NOT NULL,
    "species_ref_id" "uuid" NOT NULL,
    "source_id" "uuid" NOT NULL,
    "description" "text",
    "source_section" "text",
    "extracted_by" "text" DEFAULT 'manual'::"text",
    "extraction_confidence" "text" DEFAULT 'high'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fruit_use" "text",
    "pollination_group" "text",
    "pollination_status" "text",
    "flower_date" integer,
    "harvest_season" "text",
    "bearing_habit" "text",
    "vigour" "text",
    "tree_form" "text",
    "parentage" "text",
    "origin" "text",
    "biennial" boolean,
    "rhs_agm_year" integer,
    "rhs_agm" boolean DEFAULT false,
    "rhs_hardiness" "text",
    "flower_form" "text",
    "flower_size_class" "text",
    "flower_colour" "text",
    "height_cm" integer,
    "cultivar_group" "text",
    "fragrance" "text",
    "repeat_flowering" boolean,
    "breeder" "text",
    "year_introduced" integer,
    "spread_cm" integer,
    "rhs_verification_status" "text" DEFAULT 'unverified'::"text",
    "verification_notes" "text",
    "verified_at" timestamp with time zone,
    "nfc_data" "jsonb",
    CONSTRAINT "cultivar_reference_rhs_verification_status_check" CHECK (("rhs_verification_status" = ANY (ARRAY['unverified'::"text", 'rhs_verified_match'::"text", 'rhs_verified_discrepancy'::"text", 'rhs_not_found'::"text", 'register_verified_match'::"text", 'register_verified_discrepancy'::"text"])))
);


ALTER TABLE "public"."cultivar_reference" OWNER TO "postgres";


COMMENT ON COLUMN "public"."cultivar_reference"."rhs_agm_year" IS 'Year the RHS Award of Garden Merit was granted (2-digit in source, stored as 4-digit). NULL = no AGM.';



COMMENT ON COLUMN "public"."cultivar_reference"."flower_form" IS 'NDS class for dahlias (Decorative, Cactus, Ball, etc), NSPS type for sweet peas (Spencer, Old-Fashioned, etc), clematis group';



COMMENT ON COLUMN "public"."cultivar_reference"."flower_size_class" IS 'NDS size for dahlias (Miniature, Small, Medium, Large, Giant). NULL for non-dahlia genera';



COMMENT ON COLUMN "public"."cultivar_reference"."flower_colour" IS 'Colour description from authoritative source';



COMMENT ON COLUMN "public"."cultivar_reference"."height_cm" IS 'Typical height in centimetres at cultivar level';



COMMENT ON COLUMN "public"."cultivar_reference"."breeder" IS 'Breeder or raiser name. May include attribution qualifier in parentheses.';



COMMENT ON COLUMN "public"."cultivar_reference"."year_introduced" IS 'Year of introduction or registration.';



COMMENT ON COLUMN "public"."cultivar_reference"."spread_cm" IS 'Typical mature spread in centimetres.';



COMMENT ON COLUMN "public"."cultivar_reference"."rhs_verification_status" IS 'Verification status against RHS or authoritative genus register. unverified = not yet checked. rhs_verified_match = RHS data matches database. rhs_verified_discrepancy = RHS found but key fields differ — see verification_notes. rhs_not_found = cultivar not found on RHS (not necessarily wrong). register_verified_match/discrepancy = checked against specialist register (ICR, NSPS, etc.).';



COMMENT ON COLUMN "public"."cultivar_reference"."verification_notes" IS 'Free text. Records discrepancies found, resolution applied, or reason cultivar could not be verified.';



COMMENT ON COLUMN "public"."cultivar_reference"."nfc_data" IS 'Structured data from National Fruit Collection: flowering dates, physical descriptors, synonyms, accession number, image URL';



CREATE TABLE IF NOT EXISTS "public"."digest_exception_tracking" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_type" "text" NOT NULL,
    "exception_key" "text" NOT NULL,
    "exception_detail" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "first_seen_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "last_seen_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "consecutive_days" integer DEFAULT 1 NOT NULL,
    "escalated_at" "date",
    "resolved_at" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."digest_exception_tracking" OWNER TO "postgres";


COMMENT ON TABLE "public"."digest_exception_tracking" IS 'Tracks how long each stock/BOM exception has persisted, enabling escalation after N consecutive days';



CREATE TABLE IF NOT EXISTS "public"."editorial_content" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "month" integer NOT NULL,
    "year" integer NOT NULL,
    "content" "text",
    "topic_tags" "text"[],
    "content_type" "text",
    "source_publication" "text",
    "source_issue" "text",
    "geographic_relevance" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "summary" "text",
    CONSTRAINT "editorial_content_month_check" CHECK ((("month" >= 1) AND ("month" <= 12)))
);


ALTER TABLE "public"."editorial_content" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."editorial_location_mentions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "editorial_id" "uuid" NOT NULL,
    "location_id" "uuid" NOT NULL,
    "context" "text",
    "best_month_start" integer,
    "best_month_end" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "editorial_location_mentions_best_month_end_check" CHECK ((("best_month_end" >= 1) AND ("best_month_end" <= 12))),
    CONSTRAINT "editorial_location_mentions_best_month_start_check" CHECK ((("best_month_start" >= 1) AND ("best_month_start" <= 12)))
);


ALTER TABLE "public"."editorial_location_mentions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."editorial_plant_mentions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "editorial_id" "uuid" NOT NULL,
    "species_ref_id" "uuid",
    "cultivar_ref_id" "uuid",
    "plant_name_as_mentioned" "text" NOT NULL,
    "context" "text",
    "ashridge_sells" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."editorial_plant_mentions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."faq_bank" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "question" "text" NOT NULL,
    "answer" "text" NOT NULL,
    "category" "text" NOT NULL,
    "topic" "text" NOT NULL,
    "faq_type" "text" NOT NULL,
    "cluster_tag" "text",
    "species_ref_id" "uuid",
    "cultivar_id" "uuid",
    "source_id" "uuid",
    "used_on_slugs" "text"[] DEFAULT '{}'::"text"[],
    "ai_query_match" "text"[] DEFAULT '{}'::"text"[],
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "faq_bank_faq_type_check" CHECK (("faq_type" = ANY (ARRAY['situation'::"text", 'comparative'::"text", 'how_to'::"text", 'when'::"text", 'what_is'::"text", 'troubleshoot'::"text"]))),
    CONSTRAINT "faq_bank_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'published'::"text"])))
);


ALTER TABLE "public"."faq_bank" OWNER TO "postgres";


COMMENT ON TABLE "public"."faq_bank" IS 'Structured FAQ storage. Each row is a question-answer pair extracted from crawled content. Feeds PDPs, buying guides, advice pages, customer support, and newsletters.';



COMMENT ON COLUMN "public"."faq_bank"."cluster_tag" IS 'Groups related FAQs. When a cluster reaches 5+ FAQs on the same sub-topic, it is a candidate for an advice guide.';



COMMENT ON COLUMN "public"."faq_bank"."ai_query_match" IS 'AI search queries this FAQ answers. Populated during Ahrefs/DataForSEO analysis.';



CREATE TABLE IF NOT EXISTS "public"."ga4_daily_transactions" (
    "date" "date" NOT NULL,
    "property_id" "text" DEFAULT '317858552'::"text" NOT NULL,
    "transactions" integer,
    "revenue" numeric(10,2),
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."ga4_daily_transactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."garden_highlights" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "garden_id" "uuid" NOT NULL,
    "highlight_type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "starts_at" "date",
    "ends_at" "date",
    "is_recurring" boolean DEFAULT false,
    "recurrence_note" "text",
    "plants_mentioned" "text"[],
    "source_email_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_seen_at" timestamp with time zone,
    "temporal_note" "text",
    "merge_key" "text"
);


ALTER TABLE "public"."garden_highlights" OWNER TO "postgres";


COMMENT ON COLUMN "public"."garden_highlights"."last_seen_at" IS 'Last time this item was found on the garden page by the pipeline. Used to detect when items drop off.';



COMMENT ON COLUMN "public"."garden_highlights"."temporal_note" IS 'Garden own words about timing, verbatim from page. E.g. "looking fantastic for the next two weeks".';



COMMENT ON COLUMN "public"."garden_highlights"."merge_key" IS 'Deterministic key for upsert: garden_id::lower(title) for plants, garden_id::event::lower(title)::date for events.';



CREATE TABLE IF NOT EXISTS "public"."garden_locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "address" "text",
    "county" "text",
    "region" "text",
    "postcode" "text",
    "latitude" numeric(9,6),
    "longitude" numeric(9,6),
    "location_type" "text" DEFAULT 'garden'::"text",
    "website" "text",
    "opening_info" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "newsletter_signup_url" "text",
    "has_newsletter" boolean,
    "signup_method" "text",
    "signup_status" "text" DEFAULT 'not_attempted'::"text",
    "crawl_priority" "text" DEFAULT 'not_checked'::"text",
    "crawl_notes" "text",
    "content_feed_source_name" "text",
    "specialisms" "text"[],
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "head_gardener_name" "text",
    "head_gardener_title" "text",
    "seasonal_page_url" "text",
    "seasonal_page_type" "text",
    "last_scraped_at" timestamp with time zone
);


ALTER TABLE "public"."garden_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."governance_files" (
    "filename" "text" NOT NULL,
    "content" "text" NOT NULL,
    "content_type" "text" DEFAULT 'text/markdown'::"text" NOT NULL,
    "size_bytes" integer GENERATED ALWAYS AS ("octet_length"("content")) STORED,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "uploaded_by" "text" DEFAULT 'claude'::"text" NOT NULL
);


ALTER TABLE "public"."governance_files" OWNER TO "postgres";


COMMENT ON TABLE "public"."governance_files" IS 'Governance file distribution. Replaces Supabase Storage for governance files. Written via MCP execute_sql, read via governance-serve EF or direct SQL.';



CREATE TABLE IF NOT EXISTS "public"."governance_upload_chunks" (
    "upload_id" "uuid" NOT NULL,
    "chunk_index" integer NOT NULL,
    "chunk_content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."governance_upload_chunks" OWNER TO "postgres";


COMMENT ON TABLE "public"."governance_upload_chunks" IS 'Temporary staging for chunked governance file uploads. Chunks are assembled then deleted by assemble_governance_file().';



CREATE TABLE IF NOT EXISTS "public"."identity_graph_daily" (
    "date" "date" NOT NULL,
    "distinct_sessions" integer,
    "sessions_with_email" integer,
    "sessions_with_shopify_customer" integer,
    "sessions_with_purchase" integer,
    "email_attach_rate_pct" numeric(5,2),
    "customer_match_rate_pct" numeric(5,2),
    "refreshed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."identity_graph_daily" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."imagekit_upload_log" (
    "id" bigint NOT NULL,
    "source_path" "text" NOT NULL,
    "filename" "text" NOT NULL,
    "ik_folder" "text" NOT NULL,
    "ik_file_id" "text",
    "match_status" "text" NOT NULL,
    "cl_public_id" "text",
    "tags" "text"[],
    "alt_text" "text",
    "copyright" "text",
    "vision_status" "text",
    "file_size_bytes" bigint,
    "uploaded_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."imagekit_upload_log" OWNER TO "postgres";


ALTER TABLE "public"."imagekit_upload_log" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."imagekit_upload_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."inventory_policy_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sku" "text" NOT NULL,
    "katana_variant_id" integer,
    "previous_policy" "text",
    "new_policy" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "source" "text" NOT NULL,
    "quantity_in_stock" numeric,
    "quantity_expected" numeric,
    "effective_stock" numeric,
    "seasonal_context" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."inventory_policy_audit" OWNER TO "postgres";


COMMENT ON TABLE "public"."inventory_policy_audit" IS 'Permanent audit trail for every inventory policy change. One row per change, never overwritten.';



COMMENT ON COLUMN "public"."inventory_policy_audit"."reason" IS 'Decision tree output: in_season, cooling_off, presale_window, no_seasonal_policy, etc.';



COMMENT ON COLUMN "public"."inventory_policy_audit"."source" IS 'What triggered the change: sync-inventory-policy, reconcile-inventory-policy, fix-batch-deny, manual';



COMMENT ON COLUMN "public"."inventory_policy_audit"."seasonal_context" IS 'Seasonal policy state at time of change: e.g. season 11-4, presale opens 5/1';



CREATE TABLE IF NOT EXISTS "public"."katana_products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "katana_product_id" integer NOT NULL,
    "katana_name" "text" NOT NULL,
    "sku_prefix" "text",
    "product_type" "text" DEFAULT 'plant'::"text" NOT NULL,
    "species_ref_id" "uuid",
    "cultivar_ref_id" "uuid",
    "variant_count" integer DEFAULT 0,
    "katana_active" boolean DEFAULT true NOT NULL,
    "katana_last_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "katana_first_seen" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "bom_hash" "text",
    "bom_last_checked" timestamp with time zone,
    CONSTRAINT "katana_products_product_type_check" CHECK (("product_type" = ANY (ARRAY['plant'::"text", 'bundle'::"text", 'sundry'::"text", 'gift'::"text", 'rootstock'::"text", 'voucher'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."katana_products" OWNER TO "postgres";


COMMENT ON TABLE "public"."katana_products" IS 'Katana MRP product catalogue mapped to Cosmo reference layer. One row per base product (not per size variant). katana_active=false means the product was removed from Katana but persists here with all its reference links.';



COMMENT ON COLUMN "public"."katana_products"."sku_prefix" IS 'Base SKU before size suffix — e.g. CRATMON from CRATMON-40/60. The canonical product identifier in Katana.';



COMMENT ON COLUMN "public"."katana_products"."katana_active" IS 'true = currently in Katana catalogue. false = removed from Katana but retained in Cosmo with all reference links.';



COMMENT ON COLUMN "public"."katana_products"."katana_last_seen" IS 'Timestamp of last successful sync where this product was present in Katana.';



COMMENT ON COLUMN "public"."katana_products"."bom_hash" IS 'MD5 hash of sorted BOM ingredients for change detection. NULL = no BOM or not yet checked.';



COMMENT ON COLUMN "public"."katana_products"."bom_last_checked" IS 'When the BOM was last checked against Katana API';



CREATE TABLE IF NOT EXISTS "public"."katana_stock_sync" (
    "sku" "text" NOT NULL,
    "katana_variant_id" integer NOT NULL,
    "effective_stock" numeric,
    "shopify_inventory_policy" "text",
    "last_checked_at" timestamp with time zone DEFAULT "now"(),
    "last_changed_at" timestamp with time zone,
    "last_webhook_payload" "jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "slack_reported_at" timestamp with time zone,
    "acknowledged_at" timestamp with time zone,
    "quantity_in_stock" numeric,
    "quantity_expected" numeric,
    "manual_override" "text",
    "singles_safety_stock" integer DEFAULT 5 NOT NULL,
    "expected_supply" integer,
    "expected_supply_confidence" "text",
    "forecast_notes" "text",
    "forecast_updated_at" timestamp with time zone,
    CONSTRAINT "katana_stock_sync_expected_supply_confidence_check" CHECK (("expected_supply_confidence" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "katana_stock_sync_shopify_inventory_policy_check" CHECK (("shopify_inventory_policy" = ANY (ARRAY['CONTINUE'::"text", 'DENY'::"text"])))
);


ALTER TABLE "public"."katana_stock_sync" OWNER TO "postgres";


COMMENT ON COLUMN "public"."katana_stock_sync"."manual_override" IS 'When set to DENY or CONTINUE, reconciliation skips this SKU and respects the manual decision. NULL = no override, managed by automation.';



CREATE TABLE IF NOT EXISTS "public"."knowledge_staging" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "care_profile_id" "uuid",
    "title" "text" NOT NULL,
    "instruction_text" "text" NOT NULL,
    "trigger_type" "text",
    "trigger_month" integer,
    "trigger_offset_value" integer,
    "trigger_offset_unit" "text",
    "plant_age_min_years" integer DEFAULT 0 NOT NULL,
    "plant_age_max_years" integer,
    "priority" integer DEFAULT 5 NOT NULL,
    "content_type" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reject_reason" "text",
    "discovered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_at" timestamp with time zone,
    "merged_at" timestamp with time zone,
    "merged_instruction_id" "uuid",
    "similarity_check" "text",
    "embedding" "extensions"."vector"(1536),
    "sources" "jsonb" NOT NULL,
    "auto_approved_at" timestamp with time zone,
    CONSTRAINT "chk_staging_sources_non_empty" CHECK (("jsonb_array_length"("sources") > 0)),
    CONSTRAINT "knowledge_staging_content_type_check" CHECK (("content_type" = ANY (ARRAY['planting'::"text", 'watering'::"text", 'feeding'::"text", 'pruning'::"text", 'protection'::"text", 'aftercare'::"text", 'troubleshoot'::"text", 'seasonal-tip'::"text", 'sales-hook'::"text", 'tidbit'::"text"]))),
    CONSTRAINT "knowledge_staging_priority_check" CHECK ((("priority" >= 1) AND ("priority" <= 10))),
    CONSTRAINT "knowledge_staging_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'merged'::"text"]))),
    CONSTRAINT "knowledge_staging_trigger_month_check" CHECK ((("trigger_month" >= 1) AND ("trigger_month" <= 12))),
    CONSTRAINT "knowledge_staging_trigger_offset_unit_check" CHECK (("trigger_offset_unit" = ANY (ARRAY['weeks'::"text", 'months'::"text", 'years'::"text"]))),
    CONSTRAINT "knowledge_staging_trigger_type_check" CHECK (("trigger_type" = ANY (ARRAY['month'::"text", 'weeks-after-purchase'::"text", 'months-after-purchase'::"text", 'years-after-purchase'::"text", 'event'::"text"])))
);


ALTER TABLE "public"."knowledge_staging" OWNER TO "postgres";


COMMENT ON TABLE "public"."knowledge_staging" IS 'Review pipeline for new care knowledge. Items enter as pending, get reviewed, and either merge into care_instructions or are rejected with a reason.';



COMMENT ON COLUMN "public"."knowledge_staging"."sources" IS 'Array of source objects. Each: {"name": "...", "url": "...", "reference_source_id": "...", "detail": "page/section/fact"}. At least one required.';



CREATE TABLE IF NOT EXISTS "public"."knowledge_topics" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "topic_name" "text" NOT NULL,
    "topic_type" "text",
    "source_id" "uuid",
    "source_section" "text",
    "content" "text" NOT NULL,
    "topic_tags" "text"[],
    "related_genera" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."knowledge_topics" OWNER TO "postgres";


COMMENT ON TABLE "public"."knowledge_topics" IS 'Cross-cutting reference knowledge not tied to a single species. Covers topics like mycorrhizas, pest/disease overviews, cultivation techniques.';



CREATE TABLE IF NOT EXISTS "public"."monitored_pages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "site_id" "uuid" NOT NULL,
    "url" "text" NOT NULL,
    "sitemap_lastmod" timestamp with time zone,
    "content_hash" "text",
    "page_title" "text",
    "first_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_checked_at" timestamp with time zone,
    "last_changed_at" timestamp with time zone,
    "status" "text" DEFAULT 'new'::"text" NOT NULL,
    "crawl_error" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "page_type" "text",
    "page_content" "text",
    "content_crawled_at" timestamp with time zone,
    CONSTRAINT "monitored_pages_page_type_check" CHECK (("page_type" = ANY (ARRAY['pdp'::"text", 'collection'::"text", 'blog'::"text", 'blog_index'::"text", 'info'::"text", 'policy'::"text", 'tool'::"text", 'homepage'::"text", 'other'::"text"]))),
    CONSTRAINT "monitored_pages_status_check" CHECK (("status" = ANY (ARRAY['new'::"text", 'crawled'::"text", 'unchanged'::"text", 'error'::"text", 'excluded'::"text"])))
);


ALTER TABLE "public"."monitored_pages" OWNER TO "postgres";


COMMENT ON TABLE "public"."monitored_pages" IS 'Crawl state for each known URL. Tracks content hash for change detection.';



COMMENT ON COLUMN "public"."monitored_pages"."content_hash" IS 'SHA-256 of crawled markdown content. Used to detect real changes even when lastmod is stale.';



COMMENT ON COLUMN "public"."monitored_pages"."status" IS 'new = discovered but not yet crawled. crawled = content fetched and hashed. unchanged = re-checked, no change. error = crawl failed. excluded = URL matched pattern but manually excluded.';



CREATE TABLE IF NOT EXISTS "public"."monitored_sites" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "site_name" "text" NOT NULL,
    "base_url" "text" NOT NULL,
    "sitemap_urls" "text"[] NOT NULL,
    "url_patterns" "text"[],
    "crawl_method" "text" DEFAULT 'firecrawl'::"text" NOT NULL,
    "check_frequency_hours" integer DEFAULT 24 NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "last_checked_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "monitored_sites_crawl_method_check" CHECK (("crawl_method" = ANY (ARRAY['firecrawl'::"text", 'web_fetch'::"text"])))
);


ALTER TABLE "public"."monitored_sites" OWNER TO "postgres";


COMMENT ON TABLE "public"."monitored_sites" IS 'Sites monitored for new content via sitemap diffing. Each row configures one site.';



COMMENT ON COLUMN "public"."monitored_sites"."sitemap_urls" IS 'Array of sitemap or sitemap index URLs to fetch. Multiple sitemaps per site supported.';



COMMENT ON COLUMN "public"."monitored_sites"."url_patterns" IS 'SQL LIKE-style path patterns to include, e.g. /advice/%. NULL means all URLs from sitemap are monitored.';



COMMENT ON COLUMN "public"."monitored_sites"."crawl_method" IS 'How to fetch page content: firecrawl (JS rendering) or web_fetch (simple HTTP).';



CREATE TABLE IF NOT EXISTS "public"."notification_routing" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_type" "text" NOT NULL,
    "recipient_type" "text" NOT NULL,
    "recipient_id" "text" NOT NULL,
    "recipient_label" "text" NOT NULL,
    "frequency" "text" NOT NULL,
    "escalation_threshold" integer DEFAULT 0 NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "suppress_if_empty" boolean DEFAULT true NOT NULL,
    "last_sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text",
    CONSTRAINT "notification_routing_frequency_check" CHECK (("frequency" = ANY (ARRAY['daily'::"text", 'weekday'::"text", 'monday'::"text", 'tuesday'::"text", 'wednesday'::"text", 'thursday'::"text", 'friday'::"text", 'weekly_mon'::"text", 'weekly_tue'::"text", 'weekly_wed'::"text", 'weekly_thu'::"text", 'weekly_fri'::"text", 'monthly_1st'::"text", 'monthly_last_weekday'::"text"]))),
    CONSTRAINT "notification_routing_recipient_type_check" CHECK (("recipient_type" = ANY (ARRAY['channel'::"text", 'user'::"text"])))
);


ALTER TABLE "public"."notification_routing" OWNER TO "postgres";


COMMENT ON TABLE "public"."notification_routing" IS 'Controls who receives which reports, how often, and with what escalation threshold';



COMMENT ON COLUMN "public"."notification_routing"."escalation_threshold" IS 'Minimum consecutive days an exception must persist before sending to this recipient. 0 = send immediately';



CREATE TABLE IF NOT EXISTS "public"."odin_requirements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "title" "text" NOT NULL,
    "detail" "text",
    "raised_at" "date" DEFAULT CURRENT_DATE NOT NULL,
    "raised_in_context" "text",
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "priority" "text" DEFAULT 'normal'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "notion_page_id" "text",
    CONSTRAINT "odin_requirements_category_check" CHECK (("category" = ANY (ARRAY['requirement'::"text", 'question'::"text", 'suggestion'::"text", 'concern'::"text", 'integration-point'::"text"]))),
    CONSTRAINT "odin_requirements_priority_check" CHECK (("priority" = ANY (ARRAY['high'::"text", 'normal'::"text", 'low'::"text"]))),
    CONSTRAINT "odin_requirements_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'discussed'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."odin_requirements" OWNER TO "postgres";


COMMENT ON COLUMN "public"."odin_requirements"."notion_page_id" IS 'Notion Inbox page ID mirroring this requirement. Phase 2a backfill 18 Apr 2026. Null when no mirror exists.';



CREATE TABLE IF NOT EXISTS "public"."page_improvement_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "page_id" "uuid" NOT NULL,
    "category" "text" NOT NULL,
    "note_title" "text" NOT NULL,
    "note_body" "text" NOT NULL,
    "reference_urls" "jsonb" DEFAULT '[]'::"jsonb",
    "reference_site" "text",
    "species_ref_id" "uuid",
    "priority" integer DEFAULT 5 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "page_improvement_notes_category_check" CHECK (("category" = ANY (ARRAY['correction'::"text", 'missing_detail'::"text", 'phrasing'::"text", 'faq_opportunity'::"text", 'competitive_gap'::"text", 'seo_opportunity'::"text", 'cross_link'::"text", 'visual'::"text", 'trust_signal'::"text"]))),
    CONSTRAINT "page_improvement_notes_priority_check" CHECK ((("priority" >= 1) AND ("priority" <= 10))),
    CONSTRAINT "page_improvement_notes_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text", 'rejected'::"text", 'implemented'::"text"])))
);


ALTER TABLE "public"."page_improvement_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pdp_content" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "body_html" "text",
    "body_html_clean" "text",
    "seo_title" "text",
    "seo_description" "text",
    "comments" "jsonb" DEFAULT '[]'::"jsonb",
    "published_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "human_edited" boolean DEFAULT false NOT NULL,
    CONSTRAINT "pdp_content_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'approved'::"text", 'published'::"text", 'archived'::"text", 'legacy'::"text"])))
);


ALTER TABLE "public"."pdp_content" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pest_disease_reference" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "scientific_name" "text",
    "type" "text" NOT NULL,
    "description" "text",
    "symptoms" "text",
    "conditions" "text",
    "control_methods" "text",
    "uk_notes" "text",
    "source_id" "uuid" NOT NULL,
    "source_section" "text",
    "extracted_by" "text" DEFAULT 'manual'::"text",
    "extraction_confidence" "text" DEFAULT 'high'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "communication_tier" "text" DEFAULT 'reactive'::"text" NOT NULL,
    CONSTRAINT "pest_disease_reference_communication_tier_check" CHECK (("communication_tier" = ANY (ARRAY['proactive'::"text", 'reactive'::"text", 'internal'::"text"])))
);


ALTER TABLE "public"."pest_disease_reference" OWNER TO "postgres";


COMMENT ON COLUMN "public"."pest_disease_reference"."communication_tier" IS 'Controls how this pest/disease surfaces in customer communications. proactive = can appear in lifecycle emails, care guides, newsletters (resistance framing only). reactive = only surfaces in customer support and website reference pages. internal = knowledge base only, not customer-facing.';



CREATE TABLE IF NOT EXISTS "public"."plant_awards" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "award_name" "text" NOT NULL,
    "award_year" integer NOT NULL,
    "award_position" "text" DEFAULT 'winner'::"text" NOT NULL,
    "plant_name" "text" NOT NULL,
    "cultivar_id" "uuid",
    "species_ref_id" "uuid",
    "breeder" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "awarding_body" "text"
);


ALTER TABLE "public"."plant_awards" OWNER TO "postgres";


COMMENT ON TABLE "public"."plant_awards" IS 'Competitive plant awards from flower shows, trials, and specialist societies. Not for quality marks like RHS AGM (tracked on species_reference). Each row = one plant recognised at one event in one year.';



COMMENT ON COLUMN "public"."plant_awards"."award_name" IS 'Name of the award, e.g. Chelsea Plant of the Year, Rose of the Year, National Dahlia Society Best Seedling';



COMMENT ON COLUMN "public"."plant_awards"."award_position" IS 'winner, 2nd, 3rd, peoples_choice';



COMMENT ON COLUMN "public"."plant_awards"."plant_name" IS 'Full display name as given by the show, e.g. Clematis koreana AMBER (Wit141205)';



COMMENT ON COLUMN "public"."plant_awards"."awarding_body" IS 'Organisation behind the award, e.g. RHS, RNRS, National Dahlia Society, National Sweet Pea Society';



CREATE TABLE IF NOT EXISTS "public"."plant_tag_definitions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tag_category" "text" NOT NULL,
    "tag_name" "text" NOT NULL,
    "tag_display" "text" NOT NULL,
    "tag_group" "text",
    "data_type" "text" DEFAULT 'boolean'::"text" NOT NULL,
    "scale_values" "text"[],
    "applies_to" "text"[] DEFAULT '{species,cultivar}'::"text"[] NOT NULL,
    "synonyms" "text"[] DEFAULT '{}'::"text"[],
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "description" "text",
    "proposed_count" integer DEFAULT 0,
    "proposed_sources" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plant_tag_definitions_data_type_check" CHECK (("data_type" = ANY (ARRAY['boolean'::"text", 'text'::"text", 'numeric'::"text", 'scale'::"text"]))),
    CONSTRAINT "plant_tag_definitions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'proposed'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."plant_tag_definitions" OWNER TO "postgres";


COMMENT ON TABLE "public"."plant_tag_definitions" IS 'Controlled vocabulary of plant attributes. Self-extending: extraction pipeline proposes new tags when it encounters unrecognised characteristics repeatedly.';



COMMENT ON COLUMN "public"."plant_tag_definitions"."synonyms" IS 'Alternative words/phrases for discoverability. Searched alongside tag_name and tag_display when looking up tags.';



COMMENT ON COLUMN "public"."plant_tag_definitions"."proposed_count" IS 'For proposed tags: how many times extraction has suggested this tag across different pages.';



CREATE TABLE IF NOT EXISTS "public"."plant_tags" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "species_ref_id" "uuid",
    "cultivar_id" "uuid",
    "tag_id" "uuid" NOT NULL,
    "tag_value" "text" NOT NULL,
    "source_id" "uuid",
    "confidence" "text" DEFAULT 'medium'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "plant_tags_check" CHECK ((("species_ref_id" IS NOT NULL) OR ("cultivar_id" IS NOT NULL))),
    CONSTRAINT "plant_tags_confidence_check" CHECK (("confidence" = ANY (ARRAY['high'::"text", 'medium'::"text", 'low'::"text"])))
);


ALTER TABLE "public"."plant_tags" OWNER TO "postgres";


COMMENT ON TABLE "public"."plant_tags" IS 'Plant attribute assignments. Each row links a plant (species or cultivar) to a tag definition with a value and source.';



CREATE TABLE IF NOT EXISTS "public"."product_bom" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "katana_product_id" integer NOT NULL,
    "variant_sku" "text" NOT NULL,
    "ingredient_sku" "text" NOT NULL,
    "ingredient_sku_prefix" "text" NOT NULL,
    "ingredient_katana_product_id" integer,
    "species_ref_id" "uuid",
    "quantity" integer NOT NULL,
    "rank" integer DEFAULT 0,
    "bom_fetched_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "active_on_site" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."product_bom" OWNER TO "postgres";


COMMENT ON TABLE "public"."product_bom" IS 'Bill of materials for bundle/mix products. Sourced from Katana /v1/recipes endpoint. Monitored daily for composition changes that require PDP updates.';



COMMENT ON COLUMN "public"."product_bom"."ingredient_sku_prefix" IS 'SKU prefix (e.g., CRATMON) for joining to katana_products.sku_prefix to resolve the ingredient product';



COMMENT ON COLUMN "public"."product_bom"."bom_fetched_at" IS 'When this BOM row was last confirmed from Katana API';



COMMENT ON COLUMN "public"."product_bom"."active_on_site" IS 'False for legacy/draft products not sold on ashridgetrees.co.uk. Suppresses BOM-blocked notifications.';



CREATE TABLE IF NOT EXISTS "public"."reference_claims" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "species_ref_id" "uuid",
    "source_id" "uuid" NOT NULL,
    "latin_name" "text" NOT NULL,
    "claim_field" "text" NOT NULL,
    "claim_value" "text" NOT NULL,
    "claim_unit" "text",
    "claim_context" "text",
    "synonym_of" "text",
    "adopted" boolean DEFAULT false,
    "conflicts_with" "uuid"[],
    "resolution_note" "text",
    "source_page" integer,
    "source_section" "text",
    "extracted_by" "text" DEFAULT 'manual'::"text",
    "extraction_confidence" "text" DEFAULT 'high'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reference_claims_extraction_confidence_check" CHECK (("extraction_confidence" = ANY (ARRAY['high'::"text", 'medium'::"text", 'low'::"text"])))
);


ALTER TABLE "public"."reference_claims" OWNER TO "postgres";


COMMENT ON TABLE "public"."reference_claims" IS 'Individual facts from individual sources. The audit trail. When Crawford says 5m and RHS says 4m, both claims are stored here. The adopted claim populates species_reference. Discrepancies surface for review.';



CREATE TABLE IF NOT EXISTS "public"."reference_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reference_source_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "content_format" "text" DEFAULT 'text'::"text",
    "page_count" integer,
    "notes" "text",
    "stored_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "reference_documents_content_format_check" CHECK (("content_format" = ANY (ARRAY['text'::"text", 'markdown'::"text", 'html'::"text"])))
);


ALTER TABLE "public"."reference_documents" OWNER TO "postgres";


COMMENT ON TABLE "public"."reference_documents" IS 'Full text content of authoritative source documents, linked to reference_sources. Keeps source material in the Supabase ecosystem so pipeline processes can read it directly. Replaces KB file storage for documents that inform the database.';



COMMENT ON COLUMN "public"."reference_documents"."reference_source_id" IS 'FK to reference_sources. One document per source entry, or multiple documents if a source has separately useful sections.';



COMMENT ON COLUMN "public"."reference_documents"."content" IS 'Full extracted text of the source document. Stored as plain text regardless of original format (PDF, HTML, etc.).';



CREATE TABLE IF NOT EXISTS "public"."reference_sources" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_name" "text" NOT NULL,
    "source_type" "text" NOT NULL,
    "author" "text",
    "publisher" "text",
    "isbn" "text",
    "publication_year" integer,
    "edition" "text",
    "scope_notes" "text",
    "authority_level" "text" DEFAULT 'secondary'::"text" NOT NULL,
    "ingestion_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "species_count" integer,
    "claims_count" integer,
    "ingested_at" timestamp with time zone,
    "ingested_by" "text",
    "file_path" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reference_sources_authority_level_check" CHECK (("authority_level" = ANY (ARRAY['primary'::"text", 'secondary'::"text", 'tertiary'::"text", 'internal'::"text"]))),
    CONSTRAINT "reference_sources_ingestion_status_check" CHECK (("ingestion_status" = ANY (ARRAY['pending'::"text", 'partial'::"text", 'complete'::"text", 'superseded'::"text"]))),
    CONSTRAINT "reference_sources_source_type_check" CHECK (("source_type" = ANY (ARRAY['book'::"text", 'factsheet'::"text", 'database'::"text", 'website'::"text", 'rhs-agm-list'::"text", 'nursery-catalogue'::"text", 'journal'::"text", 'internal-audit'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."reference_sources" OWNER TO "postgres";


COMMENT ON TABLE "public"."reference_sources" IS 'Tracks every document ingested into the Cosmo reference layer. Each source generates claims in reference_claims. Authority level determines how conflicts are resolved.';



CREATE TABLE IF NOT EXISTS "public"."rootstock_reference" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "percent_full_size" "text",
    "height" "text",
    "spread" "text",
    "staking_required" "text",
    "hardiness" "text",
    "bearing_age" "text",
    "average_yield" "text",
    "anchorage" "text",
    "suckering" "text",
    "burr_knots" "text",
    "bud_break" "text",
    "defoliation" "text",
    "soil_tolerances" "jsonb",
    "disease_resistance" "jsonb",
    "notes" "text",
    "source_id" "uuid",
    "source_section" "text" DEFAULT 'art-apples'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rootstock_reference" OWNER TO "postgres";


COMMENT ON TABLE "public"."rootstock_reference" IS 'Apple rootstock characteristics from ART apple book. soil_tolerances keys: heavy, medium, light, dry, moist, wet, fertile, poor, drought_tolerance, waterlog_tolerance. disease_resistance keys: woolly_aphid, canker, scab, mildew, fireblight, silverleaf, crown_rot, crown_gall.';



CREATE TABLE IF NOT EXISTS "public"."seasonal_selling_policy" (
    "handle" "text" NOT NULL,
    "sku_prefix" "text",
    "start_month" integer NOT NULL,
    "end_month" integer NOT NULL,
    "presale_allowed" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "presale_start_month" integer,
    "presale_start_day" integer DEFAULT 1,
    "cannot_source" boolean DEFAULT false NOT NULL,
    "cannot_source_notes" "text",
    CONSTRAINT "seasonal_selling_policy_end_month_check" CHECK ((("end_month" >= 1) AND ("end_month" <= 12))),
    CONSTRAINT "seasonal_selling_policy_presale_start_day_check" CHECK ((("presale_start_day" >= 1) AND ("presale_start_day" <= 31))),
    CONSTRAINT "seasonal_selling_policy_presale_start_month_check" CHECK ((("presale_start_month" >= 1) AND ("presale_start_month" <= 12))),
    CONSTRAINT "seasonal_selling_policy_start_month_check" CHECK ((("start_month" >= 1) AND ("start_month" <= 12)))
);


ALTER TABLE "public"."seasonal_selling_policy" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shopify_customers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shopify_customer_id" bigint NOT NULL,
    "email" "text" NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "postcode" "text",
    "city" "text",
    "county" "text",
    "region" "text",
    "country_code" "text" DEFAULT 'GB'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."shopify_customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shopify_order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "shopify_line_item_id" bigint NOT NULL,
    "product_title" "text" NOT NULL,
    "variant_title" "text",
    "sku" "text",
    "quantity" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(10,2),
    "shopify_product_id" bigint,
    "katana_product_id" "uuid",
    "species_ref_id" "uuid",
    "cultivar_ref_id" "uuid",
    "match_method" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."shopify_order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shopify_orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shopify_order_id" bigint NOT NULL,
    "order_number" "text" NOT NULL,
    "customer_id" "uuid",
    "order_date" timestamp with time zone NOT NULL,
    "fulfillment_status" "text",
    "financial_status" "text",
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "total_price" numeric(10,2)
);


ALTER TABLE "public"."shopify_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shopify_slugs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "resource_type" "text" NOT NULL,
    "shopify_resource_id" bigint,
    "blog_handle" "text",
    "ahrefs_confirmed" boolean DEFAULT false,
    "ahrefs_volume" integer,
    "ahrefs_audit_date" "date",
    "species_ref_id" "uuid",
    "old_slugs" "jsonb" DEFAULT '[]'::"jsonb",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "article_needs_blog" CHECK ((("resource_type" <> 'article'::"text") OR ("blog_handle" IS NOT NULL))),
    CONSTRAINT "shopify_slugs_resource_type_check" CHECK (("resource_type" = ANY (ARRAY['product'::"text", 'article'::"text", 'collection'::"text", 'page'::"text", 'policy'::"text"])))
);


ALTER TABLE "public"."shopify_slugs" OWNER TO "postgres";


COMMENT ON TABLE "public"."shopify_slugs" IS 'Centralised slug registry for all Ashridge URLs: products, blog articles, collections, pages, and policies. Publishing workflows validate against this table. Collections, pages, and policies are reference entries — not used by publishing workflows but available for cross-referencing.';



COMMENT ON COLUMN "public"."shopify_slugs"."slug" IS 'The Shopify handle — e.g. star-of-tuscany-jasmine-plants or how-to-grow-dahlias';



COMMENT ON COLUMN "public"."shopify_slugs"."blog_handle" IS 'For articles only — which Shopify blog this belongs to (e.g. roses, garden-plants)';



COMMENT ON COLUMN "public"."shopify_slugs"."ahrefs_confirmed" IS 'Has this slug been verified through Ahrefs keyword research?';



COMMENT ON COLUMN "public"."shopify_slugs"."old_slugs" IS 'Array of {slug, redirected_at, shopify_redirect_id} objects for redirect tracking';



CREATE TABLE IF NOT EXISTS "public"."species_pest_disease" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "species_ref_id" "uuid" NOT NULL,
    "pest_disease_id" "uuid" NOT NULL,
    "relationship" "text" NOT NULL,
    "notes" "text",
    "source_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."species_pest_disease" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."species_reference" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "latin_name" "text" NOT NULL,
    "genus" "text" NOT NULL,
    "species" "text",
    "cultivar" "text",
    "family" "text",
    "common_names" "text"[],
    "synonyms" "text"[],
    "size_class" "text",
    "max_height_m" numeric(5,2),
    "height_10yr_m" numeric(5,2),
    "spread_m" numeric(5,2),
    "hardiness_zone_min" integer,
    "hardiness_zone_max" integer,
    "rhs_hardiness" "text",
    "soil_moisture" "text",
    "soil_ph" "text",
    "light_preference" "text",
    "light_tolerance" "text",
    "evergreen_status" "text",
    "nitrogen_fixer" boolean DEFAULT false,
    "dioecious" boolean DEFAULT false,
    "uk_performance" "text",
    "uk_performance_note" "text",
    "origin_region" "text",
    "native_to_uk" boolean DEFAULT false,
    "edible_parts" "text"[],
    "edible_notes" "text",
    "toxic_parts" "text"[],
    "toxic_notes" "text",
    "bee_plant" boolean DEFAULT false,
    "pollinator_notes" "text",
    "uses_medicinal" boolean DEFAULT false,
    "uses_timber" boolean DEFAULT false,
    "uses_dye" boolean DEFAULT false,
    "uses_fibre" boolean DEFAULT false,
    "uses_hedging" boolean DEFAULT false,
    "uses_erosion" boolean DEFAULT false,
    "uses_ground_cover" boolean DEFAULT false,
    "uses_windbreak" boolean DEFAULT false,
    "uses_notes" "text",
    "ashridge_product" boolean DEFAULT false,
    "shopify_handles" "text"[],
    "last_audited_at" timestamp with time zone,
    "audit_notes" "text",
    "confidence" "text" DEFAULT 'unverified'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "rhs_agm" boolean DEFAULT false,
    "rhs_agm_year" integer,
    CONSTRAINT "species_reference_confidence_check" CHECK (("confidence" = ANY (ARRAY['verified'::"text", 'adopted'::"text", 'conflicted'::"text", 'unverified'::"text"]))),
    CONSTRAINT "species_reference_evergreen_status_check" CHECK (("evergreen_status" = ANY (ARRAY['evergreen'::"text", 'semi-evergreen'::"text", 'deciduous'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_light_preference_check" CHECK (("light_preference" = ANY (ARRAY['full-sun'::"text", 'partial-shade'::"text", 'full-shade'::"text", 'any'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_light_tolerance_check" CHECK (("light_tolerance" = ANY (ARRAY['full-sun-only'::"text", 'tolerates-partial-shade'::"text", 'tolerates-full-shade'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_size_class_check" CHECK (("size_class" = ANY (ARRAY['tree'::"text", 'large-shrub'::"text", 'medium-shrub'::"text", 'small-shrub'::"text", 'dwarf-shrub'::"text", 'prostrate-shrub'::"text", 'climber'::"text", 'perennial'::"text", 'annual'::"text", 'bulb'::"text", 'grass'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_soil_moisture_check" CHECK (("soil_moisture" = ANY (ARRAY['dry'::"text", 'well-drained'::"text", 'moist'::"text", 'wet'::"text", 'any'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_soil_ph_check" CHECK (("soil_ph" = ANY (ARRAY['acid'::"text", 'acid-neutral'::"text", 'neutral'::"text", 'alkaline-neutral'::"text", 'alkaline'::"text", 'any'::"text", NULL::"text"]))),
    CONSTRAINT "species_reference_uk_performance_check" CHECK (("uk_performance" = ANY (ARRAY['a'::"text", 'b'::"text", 'c'::"text", 'd'::"text", 'e'::"text", NULL::"text"])))
);


ALTER TABLE "public"."species_reference" OWNER TO "postgres";


COMMENT ON TABLE "public"."species_reference" IS 'Canonical botanical reference data — one row per species. Holds the adopted "truth" when sources agree, and flags conflicts when they don''t. Edibility and toxicity fields are critical for PDP fact-checking.';



CREATE TABLE IF NOT EXISTS "public"."temp_picklist_orders" (
    "order_no" "text" NOT NULL,
    "sp_packs" "jsonb" DEFAULT '[]'::"jsonb",
    "collections" "jsonb" DEFAULT '[]'::"jsonb",
    "non_sp" integer DEFAULT 0
);


ALTER TABLE "public"."temp_picklist_orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tracklution_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "received_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "event_name" "text",
    "event_id" "text",
    "event_timestamp" timestamp with time zone,
    "value" numeric(10,2),
    "currency" "text",
    "quantity" integer,
    "session_id" "text",
    "click_id" "text",
    "click_id_type" "text",
    "utm_source" "text",
    "utm_medium" "text",
    "utm_campaign" "text",
    "utm_content" "text",
    "utm_term" "text",
    "email_hash" "text",
    "phone_hash" "text",
    "external_id" "text",
    "product_id" "text",
    "product_name" "text",
    "product_category" "text",
    "shopify_order_id" "text",
    "raw_payload" "jsonb",
    "entry_url" "text",
    "landing_page" "text" GENERATED ALWAYS AS (
CASE
    WHEN ("entry_url" ~~ '%/sandbox/modern%'::"text") THEN ('https://www.ashridgetrees.co.uk'::"text" || "regexp_replace"("entry_url", '^.*?/sandbox/modern'::"text", ''::"text"))
    ELSE "entry_url"
END) STORED,
    "referrer_source" "text"
);


ALTER TABLE "public"."tracklution_events" OWNER TO "postgres";


COMMENT ON TABLE "public"."tracklution_events" IS 'Real-time event stream from Tracklution Custom Connector webhook. Receives Purchase, ViewContent and other events with full attribution data.';



COMMENT ON COLUMN "public"."tracklution_events"."landing_page" IS 'Real landing page URL, extracted from Shopify web pixel sandbox entry_url. Generated column.';



COMMENT ON COLUMN "public"."tracklution_events"."referrer_source" IS 'HTTP referrer domain (e.g. chatgpt.com, claude.ai). Populated once Tracklution support adds referrer to Custom Connector payload.';



CREATE OR REPLACE VIEW "public"."v_ashridge_species_audit" AS
 SELECT "latin_name",
    "genus",
    "common_names",
    "max_height_m",
    "hardiness_zone_min",
    "evergreen_status",
    "edible_parts",
    "toxic_parts",
    "bee_plant",
    "confidence",
    "audit_notes",
    "shopify_handles",
    "last_audited_at",
    ( SELECT "count"(*) AS "count"
           FROM "public"."reference_claims" "rc"
          WHERE ("rc"."species_ref_id" = "sr"."id")) AS "claim_count",
    ( SELECT "count"(DISTINCT "rc"."source_id") AS "count"
           FROM "public"."reference_claims" "rc"
          WHERE ("rc"."species_ref_id" = "sr"."id")) AS "source_count"
   FROM "public"."species_reference" "sr"
  WHERE ("ashridge_product" = true)
  ORDER BY "confidence" DESC, "genus", "latin_name";


ALTER VIEW "public"."v_ashridge_species_audit" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_ashridge_species_audit" IS 'Quick audit view: all species Ashridge sells, their reference data, confidence level, and how many sources back them up. Unverified or conflicted species need attention.';



CREATE OR REPLACE VIEW "public"."v_conflicting_claims" AS
 SELECT "sr"."latin_name",
    "sr"."genus",
    "rc1"."claim_field",
    "rc1"."claim_value" AS "value_1",
    "rs1"."source_name" AS "source_1",
    "rc2"."claim_value" AS "value_2",
    "rs2"."source_name" AS "source_2",
    "rc1"."id" AS "claim_1_id",
    "rc2"."id" AS "claim_2_id"
   FROM (((("public"."reference_claims" "rc1"
     JOIN "public"."reference_claims" "rc2" ON ((("rc1"."latin_name" = "rc2"."latin_name") AND ("rc1"."claim_field" = "rc2"."claim_field") AND ("rc1"."source_id" <> "rc2"."source_id") AND ("rc1"."claim_value" <> "rc2"."claim_value") AND ("rc1"."id" < "rc2"."id"))))
     JOIN "public"."reference_sources" "rs1" ON (("rc1"."source_id" = "rs1"."id")))
     JOIN "public"."reference_sources" "rs2" ON (("rc2"."source_id" = "rs2"."id")))
     LEFT JOIN "public"."species_reference" "sr" ON (("rc1"."species_ref_id" = "sr"."id")))
  ORDER BY "sr"."latin_name", "rc1"."claim_field";


ALTER VIEW "public"."v_conflicting_claims" OWNER TO "postgres";


COMMENT ON VIEW "public"."v_conflicting_claims" IS 'Shows all cases where two sources disagree on the same fact for the same species. Use for PDP fact-checking audits.';



CREATE OR REPLACE VIEW "public"."v_customer_plants" AS
 SELECT "sc"."id" AS "customer_id",
    "sc"."email",
    "sc"."first_name",
    "sc"."last_name",
    "sc"."postcode",
    "sc"."county",
    "sc"."region",
    "so"."order_date",
    "so"."order_number",
    "soi"."id" AS "order_item_id",
    "soi"."product_title",
    "soi"."variant_title",
    "soi"."sku",
    "soi"."quantity",
    "soi"."species_ref_id",
    "soi"."cultivar_ref_id",
    "soi"."katana_product_id",
    "sr"."latin_name",
    "sr"."common_names",
    "cr"."cultivar_name",
    ("so"."order_date")::"date" AS "purchase_date",
    (((EXTRACT(year FROM "age"("now"(), "so"."order_date")))::integer * 12) + (EXTRACT(month FROM "age"("now"(), "so"."order_date")))::integer) AS "months_since_purchase"
   FROM (((("public"."shopify_order_items" "soi"
     JOIN "public"."shopify_orders" "so" ON (("soi"."order_id" = "so"."id")))
     JOIN "public"."shopify_customers" "sc" ON (("so"."customer_id" = "sc"."id")))
     LEFT JOIN "public"."species_reference" "sr" ON (("soi"."species_ref_id" = "sr"."id")))
     LEFT JOIN "public"."cultivar_reference" "cr" ON (("soi"."cultivar_ref_id" = "cr"."id")))
  WHERE (("so"."fulfillment_status" = 'fulfilled'::"text") AND ("so"."cancelled_at" IS NULL) AND ("so"."financial_status" <> ALL (ARRAY['refunded'::"text", 'voided'::"text"])));


ALTER VIEW "public"."v_customer_plants" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_unreported_stock_changes" AS
 SELECT "sku",
    "effective_stock",
    "shopify_inventory_policy",
    "last_changed_at",
    "slack_reported_at",
    "notes"
   FROM "public"."katana_stock_sync"
  WHERE (("last_changed_at" IS NOT NULL) AND (("slack_reported_at" IS NULL) OR ("slack_reported_at" < "last_changed_at")))
  ORDER BY "last_changed_at";


ALTER VIEW "public"."v_unreported_stock_changes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."variant_shipping_rootgrow" (
    "variant_sku" "text" NOT NULL,
    "title" "text" NOT NULL,
    "product_type" "text" NOT NULL,
    "category" "text",
    "variant_weight_grams" numeric,
    "variant_requires_shipping" boolean DEFAULT true,
    "shipping_label_cost" numeric,
    "current_rootgrow_g" numeric,
    "corrected_rootgrow_g" numeric,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."variant_shipping_rootgrow" OWNER TO "postgres";


COMMENT ON TABLE "public"."variant_shipping_rootgrow" IS 'Reference data for variant shipping weights and rootgrow dosages. Source of truth — SKUs must match Shopify and Katana. Replaces REFvariantshippingrootgrowv1_0.csv.';



COMMENT ON COLUMN "public"."variant_shipping_rootgrow"."variant_weight_grams" IS 'Native Shopify variant weight in grams. Used by data feeds and Shopify flows. Not a real physical weight.';



COMMENT ON COLUMN "public"."variant_shipping_rootgrow"."corrected_rootgrow_g" IS 'Corrected rootgrow dosage in grams per GOV-rootgrow-dosage-policy.';



CREATE TABLE IF NOT EXISTS "public"."workflow_health" (
    "workflow_id" "text" NOT NULL,
    "workflow_name" "text" NOT NULL,
    "expected_interval_minutes" integer NOT NULL,
    "last_success_at" timestamp with time zone,
    "last_error_at" timestamp with time zone,
    "last_error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."workflow_health" OWNER TO "postgres";


COMMENT ON TABLE "public"."workflow_health" IS 'Tracks n8n workflow execution health. Each workflow reports success/failure here. Dashboard checks for stale entries.';



CREATE TABLE IF NOT EXISTS "public"."wpt_results" (
    "id" integer NOT NULL,
    "test_date" "date" NOT NULL,
    "test_id" "text" NOT NULL,
    "url" "text" NOT NULL,
    "label" "text" NOT NULL,
    "device" "text" NOT NULL,
    "fcp_ms" integer,
    "lcp_ms" integer,
    "tti_ms" integer,
    "tbt_ms" integer,
    "cls" numeric(6,4),
    "speed_index" integer,
    "fully_loaded_ms" integer,
    "ttfb_ms" integer,
    "total_kb" numeric(10,2),
    "request_count" integer,
    "result_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wpt_results_device_check" CHECK (("device" = ANY (ARRAY['desktop'::"text", 'mobile'::"text"])))
);


ALTER TABLE "public"."wpt_results" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."wpt_results_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."wpt_results_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."wpt_results_id_seq" OWNED BY "public"."wpt_results"."id";



CREATE TABLE IF NOT EXISTS "public"."wpt_test_queue" (
    "id" integer NOT NULL,
    "test_date" "date" NOT NULL,
    "test_id" "text" NOT NULL,
    "url" "text" NOT NULL,
    "label" "text" NOT NULL,
    "device" "text" NOT NULL,
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wpt_test_queue_device_check" CHECK (("device" = ANY (ARRAY['desktop'::"text", 'mobile'::"text"]))),
    CONSTRAINT "wpt_test_queue_status_check" CHECK (("status" = ANY (ARRAY['submitted'::"text", 'complete'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."wpt_test_queue" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."wpt_test_queue_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."wpt_test_queue_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."wpt_test_queue_id_seq" OWNED BY "public"."wpt_test_queue"."id";



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_collection_segments" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_collection_segments_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_error_state" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_error_state_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_forecast_update_queue" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_forecast_update_queue_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_actual_composition" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_mo_actual_composition_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipe_audit" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipes" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_mo_recipes_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_pending_mos" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_pending_mos_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_safety_stock_audit" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_safety_stock_audit_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_stock_movement_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"archive_sweetpea"."sweetpea_stock_movement_log_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."alert_schedule" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."alert_schedule_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."wpt_results" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."wpt_results_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."wpt_test_queue" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."wpt_test_queue_id_seq"'::"regclass");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_collection_segments"
    ADD CONSTRAINT "sweetpea_collection_segments_collection_sku_segment_name_key" UNIQUE ("collection_sku", "segment_name");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_collection_segments"
    ADD CONSTRAINT "sweetpea_collection_segments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_colour_map"
    ADD CONSTRAINT "sweetpea_colour_map_pkey" PRIMARY KEY ("variety_stub");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_colour_map"
    ADD CONSTRAINT "sweetpea_colour_map_single_sku_key" UNIQUE ("single_sku");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_error_state"
    ADD CONSTRAINT "sweetpea_error_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_forecast_update_queue"
    ADD CONSTRAINT "sweetpea_forecast_update_queue_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_katana_mo_status_cache"
    ADD CONSTRAINT "sweetpea_katana_mo_status_cache_pkey" PRIMARY KEY ("mo_id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_actual_composition"
    ADD CONSTRAINT "sweetpea_mo_actual_composition_mo_id_pack_number_single_sku_key" UNIQUE ("mo_id", "pack_number", "single_sku");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_actual_composition"
    ADD CONSTRAINT "sweetpea_mo_actual_composition_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipe_audit"
    ADD CONSTRAINT "sweetpea_mo_recipe_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipes"
    ADD CONSTRAINT "sweetpea_mo_recipes_mo_id_single_sku_key" UNIQUE ("mo_id", "single_sku");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipes"
    ADD CONSTRAINT "sweetpea_mo_recipes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_pending_mos"
    ADD CONSTRAINT "sweetpea_pending_mos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_safety_stock_audit"
    ADD CONSTRAINT "sweetpea_safety_stock_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_stock_movement_log"
    ADD CONSTRAINT "sweetpea_stock_movement_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_webhook_log"
    ADD CONSTRAINT "sweetpea_webhook_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ai_search_daily"
    ADD CONSTRAINT "ai_search_daily_pkey" PRIMARY KEY ("date", "ai_platform", "landing_page_path");



ALTER TABLE ONLY "public"."alert_schedule"
    ADD CONSTRAINT "alert_schedule_alert_type_day_of_week_report_time_key" UNIQUE ("alert_type", "day_of_week", "report_time");



ALTER TABLE ONLY "public"."alert_schedule"
    ADD CONSTRAINT "alert_schedule_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attribution_channel_daily"
    ADD CONSTRAINT "attribution_channel_daily_pkey" PRIMARY KEY ("date", "channel", "ai_platform");



ALTER TABLE ONLY "public"."attribution_daily_snapshot"
    ADD CONSTRAINT "attribution_daily_snapshot_pkey" PRIMARY KEY ("date");



ALTER TABLE ONLY "public"."backfill_state"
    ADD CONSTRAINT "backfill_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."blog_articles"
    ADD CONSTRAINT "blog_articles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."blog_articles"
    ADD CONSTRAINT "blog_articles_shopify_article_id_key" UNIQUE ("shopify_article_id");



ALTER TABLE ONLY "public"."blog_articles"
    ADD CONSTRAINT "blog_articles_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."bom_collection_components"
    ADD CONSTRAINT "bom_collection_components_pack_variant_id_component_variant_key" UNIQUE ("pack_variant_id", "component_variant_id");



ALTER TABLE ONLY "public"."bom_collection_components"
    ADD CONSTRAINT "bom_collection_components_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bom_monitoring_config"
    ADD CONSTRAINT "bom_monitoring_config_pack_variant_id_key" UNIQUE ("pack_variant_id");



ALTER TABLE ONLY "public"."bom_monitoring_config"
    ADD CONSTRAINT "bom_monitoring_config_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bulb_label_staging"
    ADD CONSTRAINT "bulb_label_staging_pkey" PRIMARY KEY ("handle");



ALTER TABLE ONLY "public"."care_instruction_sources"
    ADD CONSTRAINT "care_instruction_sources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."care_instructions"
    ADD CONSTRAINT "care_instructions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."care_profiles"
    ADD CONSTRAINT "care_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."checkout_funnel_daily"
    ADD CONSTRAINT "checkout_funnel_daily_pkey" PRIMARY KEY ("date");



ALTER TABLE ONLY "public"."cloudinary_quality"
    ADD CONSTRAINT "cloudinary_quality_asset_id_key" UNIQUE ("asset_id");



ALTER TABLE ONLY "public"."cloudinary_quality"
    ADD CONSTRAINT "cloudinary_quality_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collection_urls"
    ADD CONSTRAINT "collection_urls_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."collection_urls"
    ADD CONSTRAINT "collection_urls_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."content_crosslinks"
    ADD CONSTRAINT "content_crosslinks_from_page_id_to_page_id_link_type_key" UNIQUE ("from_page_id", "to_page_id", "link_type");



ALTER TABLE ONLY "public"."content_crosslinks"
    ADD CONSTRAINT "content_crosslinks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_ecosystem"
    ADD CONSTRAINT "content_ecosystem_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_feed_items"
    ADD CONSTRAINT "content_feed_items_feedly_entry_id_key" UNIQUE ("feedly_entry_id");



ALTER TABLE ONLY "public"."content_feed_items"
    ADD CONSTRAINT "content_feed_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_feed_items"
    ADD CONSTRAINT "content_feed_items_url_key" UNIQUE ("url");



ALTER TABLE ONLY "public"."content_improvements"
    ADD CONSTRAINT "content_improvements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_performance_snapshots"
    ADD CONSTRAINT "content_performance_snapshots_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cosmo_docs"
    ADD CONSTRAINT "cosmo_docs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cultivar_pest_disease"
    ADD CONSTRAINT "cultivar_pest_disease_cultivar_id_pest_disease_id_source_id_key" UNIQUE ("cultivar_id", "pest_disease_id", "source_id");



ALTER TABLE ONLY "public"."cultivar_pest_disease"
    ADD CONSTRAINT "cultivar_pest_disease_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cultivar_reference"
    ADD CONSTRAINT "cultivar_reference_cultivar_name_species_ref_id_key" UNIQUE ("cultivar_name", "species_ref_id");



ALTER TABLE ONLY "public"."cultivar_reference"
    ADD CONSTRAINT "cultivar_reference_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."digest_exception_tracking"
    ADD CONSTRAINT "digest_exception_tracking_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."digest_exception_tracking"
    ADD CONSTRAINT "digest_exception_tracking_report_type_exception_key_first_s_key" UNIQUE ("report_type", "exception_key", "first_seen_at");



ALTER TABLE ONLY "public"."editorial_content"
    ADD CONSTRAINT "editorial_content_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."editorial_content"
    ADD CONSTRAINT "editorial_content_title_month_year_key" UNIQUE ("title", "month", "year");



ALTER TABLE ONLY "public"."editorial_location_mentions"
    ADD CONSTRAINT "editorial_location_mentions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."editorial_plant_mentions"
    ADD CONSTRAINT "editorial_plant_mentions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."faq_bank"
    ADD CONSTRAINT "faq_bank_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ga4_daily_transactions"
    ADD CONSTRAINT "ga4_daily_transactions_pkey" PRIMARY KEY ("date");



ALTER TABLE ONLY "public"."garden_highlights"
    ADD CONSTRAINT "garden_highlights_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."garden_locations"
    ADD CONSTRAINT "garden_locations_name_postcode_key" UNIQUE ("name", "postcode");



ALTER TABLE ONLY "public"."garden_locations"
    ADD CONSTRAINT "garden_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."governance_files"
    ADD CONSTRAINT "governance_files_pkey" PRIMARY KEY ("filename");



ALTER TABLE ONLY "public"."governance_upload_chunks"
    ADD CONSTRAINT "governance_upload_chunks_pkey" PRIMARY KEY ("upload_id", "chunk_index");



ALTER TABLE ONLY "public"."identity_graph_daily"
    ADD CONSTRAINT "identity_graph_daily_pkey" PRIMARY KEY ("date");



ALTER TABLE ONLY "public"."imagekit_upload_log"
    ADD CONSTRAINT "imagekit_upload_log_ik_folder_filename_key" UNIQUE ("ik_folder", "filename");



ALTER TABLE ONLY "public"."imagekit_upload_log"
    ADD CONSTRAINT "imagekit_upload_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_policy_audit"
    ADD CONSTRAINT "inventory_policy_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."katana_products"
    ADD CONSTRAINT "katana_products_katana_product_id_key" UNIQUE ("katana_product_id");



ALTER TABLE ONLY "public"."katana_products"
    ADD CONSTRAINT "katana_products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."katana_stock_sync"
    ADD CONSTRAINT "katana_stock_sync_pkey" PRIMARY KEY ("sku");



ALTER TABLE ONLY "public"."katana_stock_sync"
    ADD CONSTRAINT "katana_stock_sync_variant_id_unique" UNIQUE ("katana_variant_id");



ALTER TABLE ONLY "public"."knowledge_staging"
    ADD CONSTRAINT "knowledge_staging_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_topics"
    ADD CONSTRAINT "knowledge_topics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_topics"
    ADD CONSTRAINT "knowledge_topics_topic_name_source_section_key" UNIQUE ("topic_name", "source_section");



ALTER TABLE ONLY "public"."monitored_pages"
    ADD CONSTRAINT "monitored_pages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."monitored_pages"
    ADD CONSTRAINT "monitored_pages_url_key" UNIQUE ("url");



ALTER TABLE ONLY "public"."monitored_sites"
    ADD CONSTRAINT "monitored_sites_base_url_key" UNIQUE ("base_url");



ALTER TABLE ONLY "public"."monitored_sites"
    ADD CONSTRAINT "monitored_sites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_routing"
    ADD CONSTRAINT "notification_routing_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notification_routing"
    ADD CONSTRAINT "notification_routing_report_type_recipient_id_key" UNIQUE ("report_type", "recipient_id");



ALTER TABLE ONLY "public"."odin_requirements"
    ADD CONSTRAINT "odin_requirements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."page_improvement_notes"
    ADD CONSTRAINT "page_improvement_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pdp_content"
    ADD CONSTRAINT "pdp_content_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pdp_content"
    ADD CONSTRAINT "pdp_content_slug_version_key" UNIQUE ("slug", "version");



ALTER TABLE ONLY "public"."pest_disease_reference"
    ADD CONSTRAINT "pest_disease_reference_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."pest_disease_reference"
    ADD CONSTRAINT "pest_disease_reference_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plant_awards"
    ADD CONSTRAINT "plant_awards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plant_awards"
    ADD CONSTRAINT "plant_awards_unique_award" UNIQUE ("award_name", "award_year", "award_position", "plant_name");



ALTER TABLE ONLY "public"."plant_tag_definitions"
    ADD CONSTRAINT "plant_tag_definitions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."plant_tag_definitions"
    ADD CONSTRAINT "plant_tag_definitions_tag_category_tag_name_key" UNIQUE ("tag_category", "tag_name");



ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_bom"
    ADD CONSTRAINT "product_bom_katana_product_id_variant_sku_ingredient_sku_key" UNIQUE ("katana_product_id", "variant_sku", "ingredient_sku");



ALTER TABLE ONLY "public"."product_bom"
    ADD CONSTRAINT "product_bom_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reference_claims"
    ADD CONSTRAINT "reference_claims_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reference_documents"
    ADD CONSTRAINT "reference_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."reference_sources"
    ADD CONSTRAINT "reference_sources_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rootstock_reference"
    ADD CONSTRAINT "rootstock_reference_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."rootstock_reference"
    ADD CONSTRAINT "rootstock_reference_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."seasonal_selling_policy"
    ADD CONSTRAINT "seasonal_selling_policy_pkey" PRIMARY KEY ("handle");



ALTER TABLE ONLY "public"."shopify_customers"
    ADD CONSTRAINT "shopify_customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shopify_customers"
    ADD CONSTRAINT "shopify_customers_shopify_customer_id_key" UNIQUE ("shopify_customer_id");



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_shopify_line_item_id_key" UNIQUE ("shopify_line_item_id");



ALTER TABLE ONLY "public"."shopify_orders"
    ADD CONSTRAINT "shopify_orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shopify_orders"
    ADD CONSTRAINT "shopify_orders_shopify_order_id_key" UNIQUE ("shopify_order_id");



ALTER TABLE ONLY "public"."shopify_slugs"
    ADD CONSTRAINT "shopify_slugs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."species_pest_disease"
    ADD CONSTRAINT "species_pest_disease_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."species_pest_disease"
    ADD CONSTRAINT "species_pest_disease_species_ref_id_pest_disease_id_source__key" UNIQUE ("species_ref_id", "pest_disease_id", "source_id");



ALTER TABLE ONLY "public"."species_reference"
    ADD CONSTRAINT "species_reference_latin_name_key" UNIQUE ("latin_name");



ALTER TABLE ONLY "public"."species_reference"
    ADD CONSTRAINT "species_reference_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."temp_picklist_orders"
    ADD CONSTRAINT "temp_picklist_orders_pkey" PRIMARY KEY ("order_no");



ALTER TABLE ONLY "public"."tracklution_events"
    ADD CONSTRAINT "tracklution_events_event_id_unique" UNIQUE ("event_id");



ALTER TABLE ONLY "public"."tracklution_events"
    ADD CONSTRAINT "tracklution_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shopify_slugs"
    ADD CONSTRAINT "unique_slug_per_type" UNIQUE ("slug", "resource_type");



ALTER TABLE ONLY "public"."variant_shipping_rootgrow"
    ADD CONSTRAINT "variant_shipping_rootgrow_pkey" PRIMARY KEY ("variant_sku");



ALTER TABLE ONLY "public"."workflow_health"
    ADD CONSTRAINT "workflow_health_pkey" PRIMARY KEY ("workflow_id");



ALTER TABLE ONLY "public"."wpt_results"
    ADD CONSTRAINT "wpt_results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wpt_test_queue"
    ADD CONSTRAINT "wpt_test_queue_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_scs_collection" ON "archive_sweetpea"."sweetpea_collection_segments" USING "btree" ("collection_sku");



CREATE INDEX "idx_ses_by_sku" ON "archive_sweetpea"."sweetpea_error_state" USING "btree" ("affected_sku", "detected_at" DESC);



CREATE INDEX "idx_ses_open_critical" ON "archive_sweetpea"."sweetpea_error_state" USING "btree" ("detected_at" DESC) WHERE (("status" = 'open'::"text") AND ("severity" = 'critical'::"text"));



CREATE INDEX "idx_sfuq_unprocessed" ON "archive_sweetpea"."sweetpea_forecast_update_queue" USING "btree" ("enqueued_at") WHERE ("processed_at" IS NULL);



CREATE INDEX "idx_smac_mo" ON "archive_sweetpea"."sweetpea_mo_actual_composition" USING "btree" ("mo_id");



CREATE INDEX "idx_smac_sku" ON "archive_sweetpea"."sweetpea_mo_actual_composition" USING "btree" ("single_sku");



CREATE INDEX "idx_smr_mo" ON "archive_sweetpea"."sweetpea_mo_recipes" USING "btree" ("mo_id");



CREATE INDEX "idx_smr_single" ON "archive_sweetpea"."sweetpea_mo_recipes" USING "btree" ("single_sku") WHERE ("locked_at" IS NULL);



CREATE INDEX "idx_smra_mo_changed" ON "archive_sweetpea"."sweetpea_mo_recipe_audit" USING "btree" ("mo_id", "changed_at" DESC);



CREATE INDEX "idx_spm_flavour_status" ON "archive_sweetpea"."sweetpea_pending_mos" USING "btree" ("flavour", "status") WHERE ("status" <> ALL (ARRAY['completed'::"text", 'cancelled'::"text"]));



CREATE UNIQUE INDEX "idx_spm_one_blocked_reservation_per_sku" ON "archive_sweetpea"."sweetpea_pending_mos" USING "btree" ("sku") WHERE (("flavour" = 'reservation'::"text") AND ("status" = 'blocked_on_supply'::"text"));



CREATE UNIQUE INDEX "idx_spm_one_open_reservation_per_sku" ON "archive_sweetpea"."sweetpea_pending_mos" USING "btree" ("sku") WHERE (("flavour" = 'reservation'::"text") AND ("status" = ANY (ARRAY['pending_katana_create'::"text", 'NOT_STARTED'::"text"])));



CREATE INDEX "idx_spm_sku_status" ON "archive_sweetpea"."sweetpea_pending_mos" USING "btree" ("sku", "status");



CREATE INDEX "idx_ssml_sku_occurred" ON "archive_sweetpea"."sweetpea_stock_movement_log" USING "btree" ("sku", "occurred_at" DESC);



CREATE INDEX "idx_sssa_sku_changed" ON "archive_sweetpea"."sweetpea_safety_stock_audit" USING "btree" ("sku", "changed_at" DESC);



CREATE INDEX "idx_sweetpea_colour_map_pool_category" ON "archive_sweetpea"."sweetpea_colour_map" USING "btree" ("colour_category") WHERE ("in_cottage_pool" = true);



CREATE INDEX "idx_sweetpea_colour_map_single_sku" ON "archive_sweetpea"."sweetpea_colour_map" USING "btree" ("single_sku");



CREATE INDEX "idx_sweetpea_webhook_log_processed_at" ON "archive_sweetpea"."sweetpea_webhook_log" USING "btree" ("processed_at" DESC);



CREATE INDEX "idx_sweetpea_webhook_log_unalerted_holds" ON "archive_sweetpea"."sweetpea_webhook_log" USING "btree" ("processed_at" DESC) WHERE (("action" = 'mo_held_low_singles'::"text") AND ("alerted_at" IS NULL));



CREATE UNIQUE INDEX "uq_sweetpea_webhook_log_idempotency" ON "archive_sweetpea"."sweetpea_webhook_log" USING "btree" ("shopify_order_id", COALESCE("sku", ''::"text"), "event_type");



CREATE INDEX "idx_blog_articles_blog_handle" ON "public"."blog_articles" USING "btree" ("blog_handle");



CREATE INDEX "idx_blog_articles_shopify_id" ON "public"."blog_articles" USING "btree" ("shopify_article_id");



CREATE INDEX "idx_blog_articles_slug" ON "public"."blog_articles" USING "btree" ("slug");



CREATE INDEX "idx_care_instructions_content" ON "public"."care_instructions" USING "btree" ("content_type");



CREATE INDEX "idx_care_instructions_embedding" ON "public"."care_instructions" USING "ivfflat" ("embedding" "extensions"."vector_cosine_ops") WITH ("lists"='10');



CREATE INDEX "idx_care_instructions_profile" ON "public"."care_instructions" USING "btree" ("care_profile_id");



CREATE INDEX "idx_care_instructions_trigger" ON "public"."care_instructions" USING "btree" ("trigger_type", "trigger_month");



CREATE INDEX "idx_cis_instruction" ON "public"."care_instruction_sources" USING "btree" ("care_instruction_id");



CREATE INDEX "idx_cis_ref_source" ON "public"."care_instruction_sources" USING "btree" ("reference_source_id") WHERE ("reference_source_id" IS NOT NULL);



CREATE INDEX "idx_collection_urls_category" ON "public"."collection_urls" USING "btree" ("category");



CREATE INDEX "idx_collection_urls_genus" ON "public"."collection_urls" USING "btree" ("genus");



CREATE INDEX "idx_collection_urls_slug" ON "public"."collection_urls" USING "btree" ("slug");



CREATE INDEX "idx_collection_urls_species_ref" ON "public"."collection_urls" USING "btree" ("species_ref_id");



CREATE INDEX "idx_content_ecosystem_category" ON "public"."content_ecosystem" USING "btree" ("category");



CREATE INDEX "idx_content_ecosystem_status" ON "public"."content_ecosystem" USING "btree" ("status");



CREATE INDEX "idx_cosmo_docs_tags" ON "public"."cosmo_docs" USING "gin" ("tags");



CREATE INDEX "idx_cosmo_docs_type" ON "public"."cosmo_docs" USING "btree" ("type");



CREATE INDEX "idx_cultivar_pest_disease_cultivar" ON "public"."cultivar_pest_disease" USING "btree" ("cultivar_id");



CREATE INDEX "idx_cultivar_pest_disease_pest" ON "public"."cultivar_pest_disease" USING "btree" ("pest_disease_id");



CREATE INDEX "idx_cultivar_reference_species" ON "public"."cultivar_reference" USING "btree" ("species_ref_id");



CREATE INDEX "idx_digest_exceptions_active" ON "public"."digest_exception_tracking" USING "btree" ("report_type") WHERE ("resolved_at" IS NULL);



CREATE INDEX "idx_editorial_location_editorial" ON "public"."editorial_location_mentions" USING "btree" ("editorial_id");



CREATE INDEX "idx_editorial_location_location" ON "public"."editorial_location_mentions" USING "btree" ("location_id");



CREATE INDEX "idx_editorial_month" ON "public"."editorial_content" USING "btree" ("month");



CREATE INDEX "idx_editorial_month_year" ON "public"."editorial_content" USING "btree" ("month", "year");



CREATE INDEX "idx_editorial_plant_editorial" ON "public"."editorial_plant_mentions" USING "btree" ("editorial_id");



CREATE INDEX "idx_editorial_plant_species" ON "public"."editorial_plant_mentions" USING "btree" ("species_ref_id");



CREATE INDEX "idx_editorial_tags" ON "public"."editorial_content" USING "gin" ("topic_tags");



CREATE INDEX "idx_editorial_year" ON "public"."editorial_content" USING "btree" ("year");



CREATE INDEX "idx_faq_bank_category" ON "public"."faq_bank" USING "btree" ("category");



CREATE INDEX "idx_faq_bank_cluster" ON "public"."faq_bank" USING "btree" ("cluster_tag") WHERE ("cluster_tag" IS NOT NULL);



CREATE INDEX "idx_faq_bank_species" ON "public"."faq_bank" USING "btree" ("species_ref_id") WHERE ("species_ref_id" IS NOT NULL);



CREATE INDEX "idx_faq_bank_type" ON "public"."faq_bank" USING "btree" ("faq_type");



CREATE INDEX "idx_feed_items_published" ON "public"."content_feed_items" USING "btree" ("published_at");



CREATE INDEX "idx_feed_items_relevance" ON "public"."content_feed_items" USING "btree" ("relevance_tag");



CREATE INDEX "idx_feed_items_source" ON "public"."content_feed_items" USING "btree" ("source_name");



CREATE INDEX "idx_feed_items_status" ON "public"."content_feed_items" USING "btree" ("status");



CREATE INDEX "idx_garden_county" ON "public"."garden_locations" USING "btree" ("county");



CREATE INDEX "idx_garden_highlights_ends_at" ON "public"."garden_highlights" USING "btree" ("ends_at");



CREATE INDEX "idx_garden_highlights_garden_id" ON "public"."garden_highlights" USING "btree" ("garden_id");



CREATE UNIQUE INDEX "idx_garden_highlights_merge_key" ON "public"."garden_highlights" USING "btree" ("merge_key") WHERE (("is_recurring" = false) AND ("source_email_date" IS NULL));



CREATE INDEX "idx_garden_highlights_plants" ON "public"."garden_highlights" USING "gin" ("plants_mentioned");



CREATE INDEX "idx_garden_highlights_type" ON "public"."garden_highlights" USING "btree" ("highlight_type");



CREATE INDEX "idx_garden_region" ON "public"."garden_locations" USING "btree" ("region");



CREATE INDEX "idx_improvements_category" ON "public"."content_improvements" USING "btree" ("category", "priority");



CREATE INDEX "idx_improvements_status" ON "public"."content_improvements" USING "btree" ("status");



CREATE INDEX "idx_inventory_policy_audit_created" ON "public"."inventory_policy_audit" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_inventory_policy_audit_sku" ON "public"."inventory_policy_audit" USING "btree" ("sku");



CREATE INDEX "idx_katana_products_active" ON "public"."katana_products" USING "btree" ("katana_active");



CREATE INDEX "idx_katana_products_cultivar" ON "public"."katana_products" USING "btree" ("cultivar_ref_id") WHERE ("cultivar_ref_id" IS NOT NULL);



CREATE INDEX "idx_katana_products_species" ON "public"."katana_products" USING "btree" ("species_ref_id") WHERE ("species_ref_id" IS NOT NULL);



CREATE INDEX "idx_katana_products_type" ON "public"."katana_products" USING "btree" ("product_type");



CREATE INDEX "idx_katana_stock_sync_variant_id" ON "public"."katana_stock_sync" USING "btree" ("katana_variant_id");



CREATE INDEX "idx_knowledge_staging_embedding" ON "public"."knowledge_staging" USING "ivfflat" ("embedding" "extensions"."vector_cosine_ops") WITH ("lists"='10');



CREATE INDEX "idx_kss_expected_supply" ON "public"."katana_stock_sync" USING "btree" ("sku") WHERE ("expected_supply" IS NOT NULL);



CREATE INDEX "idx_monitored_pages_site_status" ON "public"."monitored_pages" USING "btree" ("site_id", "status");



CREATE INDEX "idx_odin_requirements_notion_page_id" ON "public"."odin_requirements" USING "btree" ("notion_page_id") WHERE ("notion_page_id" IS NOT NULL);



CREATE INDEX "idx_page_improvement_notes_category" ON "public"."page_improvement_notes" USING "btree" ("category");



CREATE INDEX "idx_page_improvement_notes_page_id" ON "public"."page_improvement_notes" USING "btree" ("page_id");



CREATE INDEX "idx_page_improvement_notes_priority" ON "public"."page_improvement_notes" USING "btree" ("priority");



CREATE INDEX "idx_page_improvement_notes_status" ON "public"."page_improvement_notes" USING "btree" ("status");



CREATE INDEX "idx_pdp_content_slug_status" ON "public"."pdp_content" USING "btree" ("slug", "status");



CREATE INDEX "idx_perf_snapshots_category" ON "public"."content_performance_snapshots" USING "btree" ("category", "snapshot_date");



CREATE INDEX "idx_perf_snapshots_page" ON "public"."content_performance_snapshots" USING "btree" ("page_slug", "snapshot_date");



CREATE INDEX "idx_plant_awards_cultivar" ON "public"."plant_awards" USING "btree" ("cultivar_id") WHERE ("cultivar_id" IS NOT NULL);



CREATE INDEX "idx_plant_awards_species" ON "public"."plant_awards" USING "btree" ("species_ref_id") WHERE ("species_ref_id" IS NOT NULL);



CREATE INDEX "idx_plant_awards_year" ON "public"."plant_awards" USING "btree" ("award_year");



CREATE INDEX "idx_plant_tags_cultivar" ON "public"."plant_tags" USING "btree" ("cultivar_id") WHERE ("cultivar_id" IS NOT NULL);



CREATE UNIQUE INDEX "idx_plant_tags_dedup" ON "public"."plant_tags" USING "btree" (COALESCE("species_ref_id", '00000000-0000-0000-0000-000000000000'::"uuid"), COALESCE("cultivar_id", '00000000-0000-0000-0000-000000000000'::"uuid"), "tag_id", COALESCE("source_id", '00000000-0000-0000-0000-000000000000'::"uuid"));



CREATE INDEX "idx_plant_tags_species" ON "public"."plant_tags" USING "btree" ("species_ref_id") WHERE ("species_ref_id" IS NOT NULL);



CREATE INDEX "idx_plant_tags_tag" ON "public"."plant_tags" USING "btree" ("tag_id");



CREATE INDEX "idx_product_bom_ingredient_prefix" ON "public"."product_bom" USING "btree" ("ingredient_sku_prefix");



CREATE INDEX "idx_product_bom_product" ON "public"."product_bom" USING "btree" ("katana_product_id");



CREATE INDEX "idx_reference_claims_adopted" ON "public"."reference_claims" USING "btree" ("adopted") WHERE ("adopted" = true);



CREATE INDEX "idx_reference_claims_conflicts" ON "public"."reference_claims" USING "btree" ("conflicts_with") WHERE ("conflicts_with" IS NOT NULL);



CREATE INDEX "idx_reference_claims_field" ON "public"."reference_claims" USING "btree" ("claim_field");



CREATE INDEX "idx_reference_claims_latin" ON "public"."reference_claims" USING "btree" ("latin_name");



CREATE INDEX "idx_reference_claims_source" ON "public"."reference_claims" USING "btree" ("source_id");



CREATE INDEX "idx_reference_claims_species" ON "public"."reference_claims" USING "btree" ("species_ref_id");



CREATE INDEX "idx_reference_documents_source" ON "public"."reference_documents" USING "btree" ("reference_source_id");



CREATE INDEX "idx_reference_sources_status" ON "public"."reference_sources" USING "btree" ("ingestion_status");



CREATE INDEX "idx_reference_sources_type" ON "public"."reference_sources" USING "btree" ("source_type");



CREATE INDEX "idx_shopify_customers_email" ON "public"."shopify_customers" USING "btree" ("email");



CREATE INDEX "idx_shopify_customers_postcode" ON "public"."shopify_customers" USING "btree" ("postcode");



CREATE INDEX "idx_shopify_order_items_order_id" ON "public"."shopify_order_items" USING "btree" ("order_id");



CREATE INDEX "idx_shopify_order_items_sku" ON "public"."shopify_order_items" USING "btree" ("sku");



CREATE INDEX "idx_shopify_order_items_species" ON "public"."shopify_order_items" USING "btree" ("species_ref_id");



CREATE INDEX "idx_shopify_order_items_unmatched_created" ON "public"."shopify_order_items" USING "btree" ("created_at") WHERE ("species_ref_id" IS NULL);



CREATE INDEX "idx_shopify_orders_customer_id" ON "public"."shopify_orders" USING "btree" ("customer_id");



CREATE INDEX "idx_shopify_orders_fulfillment" ON "public"."shopify_orders" USING "btree" ("fulfillment_status");



CREATE INDEX "idx_shopify_orders_order_date" ON "public"."shopify_orders" USING "btree" ("order_date");



CREATE INDEX "idx_shopify_slugs_resource_type" ON "public"."shopify_slugs" USING "btree" ("resource_type");



CREATE INDEX "idx_shopify_slugs_slug" ON "public"."shopify_slugs" USING "btree" ("slug");



CREATE INDEX "idx_shopify_slugs_species" ON "public"."shopify_slugs" USING "btree" ("species_ref_id") WHERE ("species_ref_id" IS NOT NULL);



CREATE INDEX "idx_species_pest_disease_pest" ON "public"."species_pest_disease" USING "btree" ("pest_disease_id");



CREATE INDEX "idx_species_pest_disease_species" ON "public"."species_pest_disease" USING "btree" ("species_ref_id");



CREATE INDEX "idx_species_reference_ashridge" ON "public"."species_reference" USING "btree" ("ashridge_product") WHERE ("ashridge_product" = true);



CREATE INDEX "idx_species_reference_bee" ON "public"."species_reference" USING "btree" ("bee_plant") WHERE ("bee_plant" = true);



CREATE INDEX "idx_species_reference_confidence" ON "public"."species_reference" USING "btree" ("confidence");



CREATE INDEX "idx_species_reference_genus" ON "public"."species_reference" USING "btree" ("genus");



CREATE INDEX "idx_species_reference_toxic" ON "public"."species_reference" USING "btree" ("toxic_parts") WHERE ("toxic_parts" IS NOT NULL);



CREATE INDEX "idx_ssp_sku_prefix" ON "public"."seasonal_selling_policy" USING "btree" ("sku_prefix");



CREATE INDEX "idx_staging_discovered" ON "public"."knowledge_staging" USING "btree" ("discovered_at");



CREATE INDEX "idx_staging_profile" ON "public"."knowledge_staging" USING "btree" ("care_profile_id");



CREATE INDEX "idx_staging_status" ON "public"."knowledge_staging" USING "btree" ("status");



CREATE INDEX "idx_tracklution_events_date_source" ON "public"."tracklution_events" USING "btree" ("received_at" DESC, "utm_source") WHERE ("event_name" = ANY (ARRAY['Purchase'::"text", 'ViewContent'::"text"]));



CREATE INDEX "idx_tracklution_events_event_name" ON "public"."tracklution_events" USING "btree" ("event_name");



CREATE INDEX "idx_tracklution_events_landing_page" ON "public"."tracklution_events" USING "btree" ("landing_page");



CREATE INDEX "idx_tracklution_events_raw_payload" ON "public"."tracklution_events" USING "gin" ("raw_payload");



CREATE INDEX "idx_tracklution_events_received_at" ON "public"."tracklution_events" USING "btree" ("received_at" DESC);



CREATE INDEX "idx_tracklution_events_referrer_source" ON "public"."tracklution_events" USING "btree" ("referrer_source");



CREATE INDEX "idx_tracklution_events_shopify_order_id" ON "public"."tracklution_events" USING "btree" ("shopify_order_id");



CREATE INDEX "idx_tracklution_events_utm_source" ON "public"."tracklution_events" USING "btree" ("utm_source");



CREATE INDEX "idx_wpt_queue_date" ON "public"."wpt_test_queue" USING "btree" ("test_date");



CREATE INDEX "idx_wpt_results_date" ON "public"."wpt_results" USING "btree" ("test_date");



CREATE UNIQUE INDEX "idx_wpt_results_unique" ON "public"."wpt_results" USING "btree" ("test_date", "url", "device");



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."care_instructions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."care_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "trg_katana_stock_sync_updated_at" BEFORE UPDATE ON "public"."katana_stock_sync" FOR EACH ROW EXECUTE FUNCTION "public"."update_katana_stock_sync_updated_at"();



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_actual_composition"
    ADD CONSTRAINT "sweetpea_mo_actual_composition_mo_id_fkey" FOREIGN KEY ("mo_id") REFERENCES "archive_sweetpea"."sweetpea_pending_mos"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "archive_sweetpea"."sweetpea_mo_recipes"
    ADD CONSTRAINT "sweetpea_mo_recipes_mo_id_fkey" FOREIGN KEY ("mo_id") REFERENCES "archive_sweetpea"."sweetpea_pending_mos"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_instruction_sources"
    ADD CONSTRAINT "care_instruction_sources_care_instruction_id_fkey" FOREIGN KEY ("care_instruction_id") REFERENCES "public"."care_instructions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_instruction_sources"
    ADD CONSTRAINT "care_instruction_sources_reference_source_id_fkey" FOREIGN KEY ("reference_source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."care_instructions"
    ADD CONSTRAINT "care_instructions_care_profile_id_fkey" FOREIGN KEY ("care_profile_id") REFERENCES "public"."care_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."care_profiles"
    ADD CONSTRAINT "care_profiles_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."collection_urls"
    ADD CONSTRAINT "collection_urls_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."content_crosslinks"
    ADD CONSTRAINT "content_crosslinks_from_page_id_fkey" FOREIGN KEY ("from_page_id") REFERENCES "public"."content_ecosystem"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_crosslinks"
    ADD CONSTRAINT "content_crosslinks_to_page_id_fkey" FOREIGN KEY ("to_page_id") REFERENCES "public"."content_ecosystem"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_feed_items"
    ADD CONSTRAINT "content_feed_items_extracted_to_fkey" FOREIGN KEY ("extracted_to") REFERENCES "public"."knowledge_staging"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."content_improvements"
    ADD CONSTRAINT "content_improvements_content_ecosystem_id_fkey" FOREIGN KEY ("content_ecosystem_id") REFERENCES "public"."content_ecosystem"("id");



ALTER TABLE ONLY "public"."content_performance_snapshots"
    ADD CONSTRAINT "content_performance_snapshots_content_ecosystem_id_fkey" FOREIGN KEY ("content_ecosystem_id") REFERENCES "public"."content_ecosystem"("id");



ALTER TABLE ONLY "public"."cultivar_pest_disease"
    ADD CONSTRAINT "cultivar_pest_disease_cultivar_id_fkey" FOREIGN KEY ("cultivar_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."cultivar_pest_disease"
    ADD CONSTRAINT "cultivar_pest_disease_pest_disease_id_fkey" FOREIGN KEY ("pest_disease_id") REFERENCES "public"."pest_disease_reference"("id");



ALTER TABLE ONLY "public"."cultivar_pest_disease"
    ADD CONSTRAINT "cultivar_pest_disease_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."cultivar_reference"
    ADD CONSTRAINT "cultivar_reference_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."cultivar_reference"
    ADD CONSTRAINT "cultivar_reference_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."editorial_location_mentions"
    ADD CONSTRAINT "editorial_location_mentions_editorial_id_fkey" FOREIGN KEY ("editorial_id") REFERENCES "public"."editorial_content"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."editorial_location_mentions"
    ADD CONSTRAINT "editorial_location_mentions_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."garden_locations"("id");



ALTER TABLE ONLY "public"."editorial_plant_mentions"
    ADD CONSTRAINT "editorial_plant_mentions_cultivar_ref_id_fkey" FOREIGN KEY ("cultivar_ref_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."editorial_plant_mentions"
    ADD CONSTRAINT "editorial_plant_mentions_editorial_id_fkey" FOREIGN KEY ("editorial_id") REFERENCES "public"."editorial_content"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."editorial_plant_mentions"
    ADD CONSTRAINT "editorial_plant_mentions_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."faq_bank"
    ADD CONSTRAINT "faq_bank_cultivar_id_fkey" FOREIGN KEY ("cultivar_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."faq_bank"
    ADD CONSTRAINT "faq_bank_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."faq_bank"
    ADD CONSTRAINT "faq_bank_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."garden_highlights"
    ADD CONSTRAINT "garden_highlights_garden_id_fkey" FOREIGN KEY ("garden_id") REFERENCES "public"."garden_locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."katana_products"
    ADD CONSTRAINT "katana_products_cultivar_ref_id_fkey" FOREIGN KEY ("cultivar_ref_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."katana_products"
    ADD CONSTRAINT "katana_products_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."knowledge_staging"
    ADD CONSTRAINT "knowledge_staging_care_profile_id_fkey" FOREIGN KEY ("care_profile_id") REFERENCES "public"."care_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."knowledge_staging"
    ADD CONSTRAINT "knowledge_staging_merged_instruction_id_fkey" FOREIGN KEY ("merged_instruction_id") REFERENCES "public"."care_instructions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."knowledge_topics"
    ADD CONSTRAINT "knowledge_topics_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."monitored_pages"
    ADD CONSTRAINT "monitored_pages_site_id_fkey" FOREIGN KEY ("site_id") REFERENCES "public"."monitored_sites"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."page_improvement_notes"
    ADD CONSTRAINT "page_improvement_notes_page_id_fkey" FOREIGN KEY ("page_id") REFERENCES "public"."monitored_pages"("id");



ALTER TABLE ONLY "public"."page_improvement_notes"
    ADD CONSTRAINT "page_improvement_notes_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."pest_disease_reference"
    ADD CONSTRAINT "pest_disease_reference_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."plant_awards"
    ADD CONSTRAINT "plant_awards_cultivar_id_fkey" FOREIGN KEY ("cultivar_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."plant_awards"
    ADD CONSTRAINT "plant_awards_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_cultivar_id_fkey" FOREIGN KEY ("cultivar_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."plant_tags"
    ADD CONSTRAINT "plant_tags_tag_id_fkey" FOREIGN KEY ("tag_id") REFERENCES "public"."plant_tag_definitions"("id");



ALTER TABLE ONLY "public"."product_bom"
    ADD CONSTRAINT "product_bom_katana_product_id_fkey" FOREIGN KEY ("katana_product_id") REFERENCES "public"."katana_products"("katana_product_id");



ALTER TABLE ONLY "public"."product_bom"
    ADD CONSTRAINT "product_bom_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."reference_claims"
    ADD CONSTRAINT "reference_claims_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."reference_claims"
    ADD CONSTRAINT "reference_claims_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."reference_documents"
    ADD CONSTRAINT "reference_documents_reference_source_id_fkey" FOREIGN KEY ("reference_source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."rootstock_reference"
    ADD CONSTRAINT "rootstock_reference_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_cultivar_ref_id_fkey" FOREIGN KEY ("cultivar_ref_id") REFERENCES "public"."cultivar_reference"("id");



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_katana_product_id_fkey" FOREIGN KEY ("katana_product_id") REFERENCES "public"."katana_products"("id");



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."shopify_orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shopify_order_items"
    ADD CONSTRAINT "shopify_order_items_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."shopify_orders"
    ADD CONSTRAINT "shopify_orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."shopify_customers"("id");



ALTER TABLE ONLY "public"."shopify_slugs"
    ADD CONSTRAINT "shopify_slugs_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE ONLY "public"."species_pest_disease"
    ADD CONSTRAINT "species_pest_disease_pest_disease_id_fkey" FOREIGN KEY ("pest_disease_id") REFERENCES "public"."pest_disease_reference"("id");



ALTER TABLE ONLY "public"."species_pest_disease"
    ADD CONSTRAINT "species_pest_disease_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."reference_sources"("id");



ALTER TABLE ONLY "public"."species_pest_disease"
    ADD CONSTRAINT "species_pest_disease_species_ref_id_fkey" FOREIGN KEY ("species_ref_id") REFERENCES "public"."species_reference"("id");



ALTER TABLE "archive_sweetpea"."sweetpea_collection_segments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_colour_map" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_error_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_forecast_update_queue" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_katana_mo_status_cache" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_mo_actual_composition" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_mo_recipe_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_mo_recipes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_pending_mos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_safety_stock_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_stock_movement_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "archive_sweetpea"."sweetpea_webhook_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Allow anon insert to cloudinary_quality" ON "public"."cloudinary_quality" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "Allow anon select on cloudinary_quality" ON "public"."cloudinary_quality" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Allow anon update to cloudinary_quality" ON "public"."cloudinary_quality" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Allow authenticated access to page_improvement_notes" ON "public"."page_improvement_notes" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Allow authenticated insert" ON "public"."cloudinary_quality" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated insert on pdp_content" ON "public"."pdp_content" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated insert shopify_customers" ON "public"."shopify_customers" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated insert shopify_order_items" ON "public"."shopify_order_items" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated insert shopify_orders" ON "public"."shopify_orders" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Allow authenticated read" ON "public"."cloudinary_quality" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated read on pdp_content" ON "public"."pdp_content" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated read shopify_customers" ON "public"."shopify_customers" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated read shopify_order_items" ON "public"."shopify_order_items" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated read shopify_orders" ON "public"."shopify_orders" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated update" ON "public"."cloudinary_quality" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated update on pdp_content" ON "public"."pdp_content" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated update shopify_customers" ON "public"."shopify_customers" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated update shopify_order_items" ON "public"."shopify_order_items" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Allow authenticated update shopify_orders" ON "public"."shopify_orders" FOR UPDATE TO "authenticated" USING (true);



CREATE POLICY "Allow read access to shopify_slugs" ON "public"."shopify_slugs" FOR SELECT USING (true);



CREATE POLICY "Anon can insert digest_exception_tracking" ON "public"."digest_exception_tracking" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "Anon can read digest_exception_tracking" ON "public"."digest_exception_tracking" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Anon can read notification_routing" ON "public"."notification_routing" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Anon can update digest_exception_tracking" ON "public"."digest_exception_tracking" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Anon can update notification_routing" ON "public"."notification_routing" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated read" ON "public"."care_instruction_sources" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."care_instructions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."care_profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."content_feed_items" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."cultivar_pest_disease" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."cultivar_reference" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."editorial_content" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."editorial_location_mentions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."editorial_plant_mentions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."garden_locations" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."knowledge_staging" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."knowledge_topics" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."pest_disease_reference" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."reference_claims" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."reference_sources" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."rootstock_reference" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."species_pest_disease" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated read" ON "public"."species_reference" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated update" ON "public"."content_feed_items" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated update" ON "public"."knowledge_staging" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can delete alert_schedule" ON "public"."alert_schedule" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can delete monitored_pages" ON "public"."monitored_pages" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can delete monitored_sites" ON "public"."monitored_sites" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can insert alert_schedule" ON "public"."alert_schedule" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can insert monitored_pages" ON "public"."monitored_pages" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can insert monitored_sites" ON "public"."monitored_sites" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Authenticated users can modify content_ecosystem" ON "public"."content_ecosystem" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can modify cosmo_docs" ON "public"."cosmo_docs" TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can read alert_schedule" ON "public"."alert_schedule" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read content_crosslinks" ON "public"."content_crosslinks" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read content_ecosystem" ON "public"."content_ecosystem" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read cosmo_docs" ON "public"."cosmo_docs" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read katana_products" ON "public"."katana_products" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read katana_stock_sync" ON "public"."katana_stock_sync" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read monitored_pages" ON "public"."monitored_pages" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read monitored_sites" ON "public"."monitored_sites" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can read plant_awards" ON "public"."plant_awards" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can update alert_schedule" ON "public"."alert_schedule" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can update monitored_pages" ON "public"."monitored_pages" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can update monitored_sites" ON "public"."monitored_sites" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "Authenticated users can write katana_stock_sync" ON "public"."katana_stock_sync" TO "authenticated" USING (true);



CREATE POLICY "Service role full access" ON "public"."care_instruction_sources" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access" ON "public"."care_instructions" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access" ON "public"."care_profiles" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access" ON "public"."content_feed_items" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access" ON "public"."knowledge_staging" USING (true) WITH CHECK (true);



CREATE POLICY "Service role full access katana_stock_sync" ON "public"."katana_stock_sync" TO "service_role" USING (true);



CREATE POLICY "Service role full access on plant_awards" ON "public"."plant_awards" TO "service_role" USING (true);



ALTER TABLE "public"."ai_search_daily" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."alert_schedule" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "anon_full_access" ON "public"."alert_schedule" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."care_instruction_sources" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."care_instructions" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."care_profiles" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."collection_urls" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."content_crosslinks" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."content_ecosystem" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."content_feed_items" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."cosmo_docs" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."cultivar_pest_disease" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."cultivar_reference" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."editorial_content" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."editorial_location_mentions" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."editorial_plant_mentions" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."faq_bank" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."garden_locations" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."inventory_policy_audit" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."katana_products" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."katana_stock_sync" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."knowledge_staging" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."knowledge_topics" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."monitored_pages" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."monitored_sites" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."notification_routing" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."odin_requirements" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."page_improvement_notes" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."pdp_content" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."pest_disease_reference" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."plant_awards" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."plant_tag_definitions" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."plant_tags" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."product_bom" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."reference_claims" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."reference_documents" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."reference_sources" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."rootstock_reference" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."seasonal_selling_policy" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."shopify_customers" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."shopify_order_items" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."shopify_orders" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."shopify_slugs" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."species_pest_disease" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_full_access" ON "public"."species_reference" TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "anon_read_governance_files" ON "public"."governance_files" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_improvements" ON "public"."content_improvements" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_pdp_content" ON "public"."pdp_content" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_snapshots" ON "public"."content_performance_snapshots" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_temp" ON "public"."temp_picklist_orders" FOR SELECT TO "anon" USING (true);



CREATE POLICY "anon_read_workflow_health" ON "public"."workflow_health" FOR SELECT USING (true);



CREATE POLICY "anon_write_workflow_health" ON "public"."workflow_health" USING (true);



ALTER TABLE "public"."attribution_channel_daily" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attribution_daily_snapshot" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "authenticated users can read tracklution_events" ON "public"."tracklution_events" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_improvements" ON "public"."content_improvements" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "authenticated_read_snapshots" ON "public"."content_performance_snapshots" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."backfill_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."blog_articles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bom_collection_components" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bom_monitoring_config" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bulb_label_staging" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."care_instruction_sources" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."care_instructions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."care_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."checkout_funnel_daily" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cloudinary_quality" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."collection_urls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_crosslinks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_ecosystem" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_feed_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_improvements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."content_performance_snapshots" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cosmo_docs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cultivar_pest_disease" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cultivar_reference" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."digest_exception_tracking" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."editorial_content" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."editorial_location_mentions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."editorial_plant_mentions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."faq_bank" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ga4_daily_transactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."garden_highlights" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."garden_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."governance_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."governance_upload_chunks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."identity_graph_daily" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."imagekit_upload_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_policy_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."katana_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."katana_stock_sync" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_staging" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_topics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."monitored_pages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."monitored_sites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notification_routing" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."odin_requirements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."page_improvement_notes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pdp_content" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pest_disease_reference" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."plant_awards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."plant_tag_definitions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."plant_tags" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_bom" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reference_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reference_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."reference_sources" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."rootstock_reference" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."seasonal_selling_policy" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shopify_customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shopify_order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shopify_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shopify_slugs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."species_pest_disease" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."species_reference" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."temp_picklist_orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tracklution_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."workflow_health" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


SET SESSION AUTHORIZATION "postgres";
RESET SESSION AUTHORIZATION;



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";







































































































































































































































































































































































































































































































































GRANT ALL ON FUNCTION "public"."assemble_governance_file"("p_upload_id" "uuid", "p_filename" "text", "p_content_type" "text", "p_uploaded_by" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."assemble_governance_file"("p_upload_id" "uuid", "p_filename" "text", "p_content_type" "text", "p_uploaded_by" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."assemble_governance_file"("p_upload_id" "uuid", "p_filename" "text", "p_content_type" "text", "p_uploaded_by" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."batch_update_shopify_total_price"("p_rows" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."batch_update_shopify_total_price"("p_rows" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."batch_update_shopify_total_price"("p_rows" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."bulk_upsert_katana_stock"("rows" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_ai_platforms"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_ai_platforms"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_ai_platforms"("p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_channels"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_channels"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_channels"("p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_daily_comparison"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_daily_comparison"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_daily_comparison"("p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_identity"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_identity"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_identity"("p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_overview"("p_from" "date", "p_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_overview"("p_from" "date", "p_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_overview"("p_from" "date", "p_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_attribution_pipeline_health"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_attribution_pipeline_health"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_attribution_pipeline_health"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_bom_blocked_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_bom_blocked_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_bom_blocked_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_cannot_source_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_cannot_source_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_cannot_source_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_channel_health"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_channel_health"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_channel_health"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_katana_products_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_katana_products_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_katana_products_summary"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_manual_override_detail"("p_category" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_manual_override_detail"("p_category" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_manual_override_detail"("p_category" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_manual_override_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_manual_override_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_manual_override_summary"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_next_queue_articles"("n" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_next_queue_articles"("n" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_next_queue_articles"("n" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_policy_mismatches"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_policy_mismatches"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_policy_mismatches"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_shopify_daily_stats"("p_date_from" "date", "p_date_to" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_shopify_daily_stats"("p_date_from" "date", "p_date_to" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_shopify_daily_stats"("p_date_from" "date", "p_date_to" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_stock_digest_exceptions"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_stock_digest_exceptions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_stock_digest_exceptions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_table_size_warnings"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_table_size_warnings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_table_size_warnings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tracklution_campaigns"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_tracklution_campaigns"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tracklution_campaigns"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tracklution_channel_detail"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_source" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_tracklution_channel_detail"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_source" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tracklution_channel_detail"("p_from" timestamp with time zone, "p_to" timestamp with time zone, "p_source" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tracklution_channels"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_tracklution_channels"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tracklution_channels"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_tracklution_overview"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_tracklution_overview"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_tracklution_overview"("p_from" timestamp with time zone, "p_to" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."governance_archive_prune"("p_older_than_days" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."match_order_items_to_species"() TO "anon";
GRANT ALL ON FUNCTION "public"."match_order_items_to_species"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_order_items_to_species"() TO "service_role";



GRANT ALL ON FUNCTION "public"."match_order_items_to_species"("p_since" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."match_order_items_to_species"("p_since" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_order_items_to_species"("p_since" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."report_workflow_health"("p_workflow_id" "text", "p_status" "text", "p_error_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."report_workflow_health"("p_workflow_id" "text", "p_status" "text", "p_error_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."report_workflow_health"("p_workflow_id" "text", "p_status" "text", "p_error_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_placeholder_skus"("mappings" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_placeholder_skus"("mappings" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_placeholder_skus"("mappings" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."supersede_and_archive_check"("p_request_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."supersede_and_archive_fire"("p_base_pattern" "text", "p_new_filename" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_shopify_orders"("p_orders" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."sync_shopify_orders"("p_orders" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_shopify_orders"("p_orders" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_katana_stock_sync_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_katana_stock_sync_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_katana_stock_sync_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";
























GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_collection_segments" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_collection_segments" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_collection_segments" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_collection_segments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_collection_segments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_collection_segments_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_colour_map" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_colour_map" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_colour_map" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_error_state" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_error_state" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_error_state" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_error_state_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_error_state_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_error_state_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_forecast_update_queue" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_forecast_update_queue" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_forecast_update_queue" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_forecast_update_queue_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_katana_mo_status_cache" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_katana_mo_status_cache" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_katana_mo_status_cache" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_actual_composition" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_actual_composition" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_actual_composition" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_actual_composition_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipe_audit" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipe_audit" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipe_audit" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipe_audit_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipes" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipes" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_mo_recipes" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_mo_recipes_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_pending_mos" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_pending_mos" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_pending_mos" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_pending_mos_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_pending_mos_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_pending_mos_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_safety_stock_audit" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_safety_stock_audit" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_safety_stock_audit" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_safety_stock_audit_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_stock_movement_log" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_stock_movement_log" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_stock_movement_log" TO "service_role";



GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_stock_movement_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_stock_movement_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "archive_sweetpea"."sweetpea_stock_movement_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_webhook_log" TO "anon";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_webhook_log" TO "authenticated";
GRANT ALL ON TABLE "archive_sweetpea"."sweetpea_webhook_log" TO "service_role";



SET SESSION AUTHORIZATION "postgres";
RESET SESSION AUTHORIZATION;



SET SESSION AUTHORIZATION "postgres";
RESET SESSION AUTHORIZATION;









GRANT ALL ON TABLE "public"."ai_search_daily" TO "anon";
GRANT ALL ON TABLE "public"."ai_search_daily" TO "authenticated";
GRANT ALL ON TABLE "public"."ai_search_daily" TO "service_role";



GRANT ALL ON TABLE "public"."alert_schedule" TO "anon";
GRANT ALL ON TABLE "public"."alert_schedule" TO "authenticated";
GRANT ALL ON TABLE "public"."alert_schedule" TO "service_role";



GRANT ALL ON SEQUENCE "public"."alert_schedule_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."alert_schedule_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."alert_schedule_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."attribution_channel_daily" TO "anon";
GRANT ALL ON TABLE "public"."attribution_channel_daily" TO "authenticated";
GRANT ALL ON TABLE "public"."attribution_channel_daily" TO "service_role";



GRANT ALL ON TABLE "public"."attribution_daily_snapshot" TO "anon";
GRANT ALL ON TABLE "public"."attribution_daily_snapshot" TO "authenticated";
GRANT ALL ON TABLE "public"."attribution_daily_snapshot" TO "service_role";



GRANT ALL ON TABLE "public"."backfill_state" TO "anon";
GRANT ALL ON TABLE "public"."backfill_state" TO "authenticated";
GRANT ALL ON TABLE "public"."backfill_state" TO "service_role";



GRANT ALL ON TABLE "public"."blog_articles" TO "anon";
GRANT ALL ON TABLE "public"."blog_articles" TO "authenticated";
GRANT ALL ON TABLE "public"."blog_articles" TO "service_role";



GRANT ALL ON TABLE "public"."bom_collection_components" TO "anon";
GRANT ALL ON TABLE "public"."bom_collection_components" TO "authenticated";
GRANT ALL ON TABLE "public"."bom_collection_components" TO "service_role";



GRANT ALL ON TABLE "public"."bom_monitoring_config" TO "anon";
GRANT ALL ON TABLE "public"."bom_monitoring_config" TO "authenticated";
GRANT ALL ON TABLE "public"."bom_monitoring_config" TO "service_role";



GRANT ALL ON TABLE "public"."bulb_label_staging" TO "anon";
GRANT ALL ON TABLE "public"."bulb_label_staging" TO "authenticated";
GRANT ALL ON TABLE "public"."bulb_label_staging" TO "service_role";



GRANT ALL ON TABLE "public"."care_instruction_sources" TO "anon";
GRANT ALL ON TABLE "public"."care_instruction_sources" TO "authenticated";
GRANT ALL ON TABLE "public"."care_instruction_sources" TO "service_role";



GRANT ALL ON TABLE "public"."care_instructions" TO "anon";
GRANT ALL ON TABLE "public"."care_instructions" TO "authenticated";
GRANT ALL ON TABLE "public"."care_instructions" TO "service_role";



GRANT ALL ON TABLE "public"."care_profiles" TO "anon";
GRANT ALL ON TABLE "public"."care_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."care_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."checkout_funnel_daily" TO "anon";
GRANT ALL ON TABLE "public"."checkout_funnel_daily" TO "authenticated";
GRANT ALL ON TABLE "public"."checkout_funnel_daily" TO "service_role";



GRANT ALL ON TABLE "public"."cloudinary_quality" TO "anon";
GRANT ALL ON TABLE "public"."cloudinary_quality" TO "authenticated";
GRANT ALL ON TABLE "public"."cloudinary_quality" TO "service_role";



GRANT ALL ON TABLE "public"."collection_urls" TO "anon";
GRANT ALL ON TABLE "public"."collection_urls" TO "authenticated";
GRANT ALL ON TABLE "public"."collection_urls" TO "service_role";



GRANT ALL ON TABLE "public"."content_crosslinks" TO "anon";
GRANT ALL ON TABLE "public"."content_crosslinks" TO "authenticated";
GRANT ALL ON TABLE "public"."content_crosslinks" TO "service_role";



GRANT ALL ON TABLE "public"."content_ecosystem" TO "anon";
GRANT ALL ON TABLE "public"."content_ecosystem" TO "authenticated";
GRANT ALL ON TABLE "public"."content_ecosystem" TO "service_role";



GRANT ALL ON TABLE "public"."content_feed_items" TO "anon";
GRANT ALL ON TABLE "public"."content_feed_items" TO "authenticated";
GRANT ALL ON TABLE "public"."content_feed_items" TO "service_role";



GRANT ALL ON TABLE "public"."content_improvements" TO "anon";
GRANT ALL ON TABLE "public"."content_improvements" TO "authenticated";
GRANT ALL ON TABLE "public"."content_improvements" TO "service_role";



GRANT ALL ON TABLE "public"."content_performance_snapshots" TO "anon";
GRANT ALL ON TABLE "public"."content_performance_snapshots" TO "authenticated";
GRANT ALL ON TABLE "public"."content_performance_snapshots" TO "service_role";



GRANT ALL ON TABLE "public"."cosmo_docs" TO "anon";
GRANT ALL ON TABLE "public"."cosmo_docs" TO "authenticated";
GRANT ALL ON TABLE "public"."cosmo_docs" TO "service_role";



GRANT ALL ON TABLE "public"."cultivar_pest_disease" TO "anon";
GRANT ALL ON TABLE "public"."cultivar_pest_disease" TO "authenticated";
GRANT ALL ON TABLE "public"."cultivar_pest_disease" TO "service_role";



GRANT ALL ON TABLE "public"."cultivar_reference" TO "anon";
GRANT ALL ON TABLE "public"."cultivar_reference" TO "authenticated";
GRANT ALL ON TABLE "public"."cultivar_reference" TO "service_role";



GRANT ALL ON TABLE "public"."digest_exception_tracking" TO "anon";
GRANT ALL ON TABLE "public"."digest_exception_tracking" TO "authenticated";
GRANT ALL ON TABLE "public"."digest_exception_tracking" TO "service_role";



GRANT ALL ON TABLE "public"."editorial_content" TO "anon";
GRANT ALL ON TABLE "public"."editorial_content" TO "authenticated";
GRANT ALL ON TABLE "public"."editorial_content" TO "service_role";



GRANT ALL ON TABLE "public"."editorial_location_mentions" TO "anon";
GRANT ALL ON TABLE "public"."editorial_location_mentions" TO "authenticated";
GRANT ALL ON TABLE "public"."editorial_location_mentions" TO "service_role";



GRANT ALL ON TABLE "public"."editorial_plant_mentions" TO "anon";
GRANT ALL ON TABLE "public"."editorial_plant_mentions" TO "authenticated";
GRANT ALL ON TABLE "public"."editorial_plant_mentions" TO "service_role";



GRANT ALL ON TABLE "public"."faq_bank" TO "anon";
GRANT ALL ON TABLE "public"."faq_bank" TO "authenticated";
GRANT ALL ON TABLE "public"."faq_bank" TO "service_role";



GRANT ALL ON TABLE "public"."ga4_daily_transactions" TO "anon";
GRANT ALL ON TABLE "public"."ga4_daily_transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."ga4_daily_transactions" TO "service_role";



GRANT ALL ON TABLE "public"."garden_highlights" TO "anon";
GRANT ALL ON TABLE "public"."garden_highlights" TO "authenticated";
GRANT ALL ON TABLE "public"."garden_highlights" TO "service_role";



GRANT ALL ON TABLE "public"."garden_locations" TO "anon";
GRANT ALL ON TABLE "public"."garden_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."garden_locations" TO "service_role";



GRANT ALL ON TABLE "public"."governance_files" TO "anon";
GRANT ALL ON TABLE "public"."governance_files" TO "authenticated";
GRANT ALL ON TABLE "public"."governance_files" TO "service_role";



GRANT ALL ON TABLE "public"."governance_upload_chunks" TO "anon";
GRANT ALL ON TABLE "public"."governance_upload_chunks" TO "authenticated";
GRANT ALL ON TABLE "public"."governance_upload_chunks" TO "service_role";



GRANT ALL ON TABLE "public"."identity_graph_daily" TO "anon";
GRANT ALL ON TABLE "public"."identity_graph_daily" TO "authenticated";
GRANT ALL ON TABLE "public"."identity_graph_daily" TO "service_role";



GRANT ALL ON TABLE "public"."imagekit_upload_log" TO "anon";
GRANT ALL ON TABLE "public"."imagekit_upload_log" TO "authenticated";
GRANT ALL ON TABLE "public"."imagekit_upload_log" TO "service_role";



GRANT ALL ON SEQUENCE "public"."imagekit_upload_log_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."imagekit_upload_log_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."imagekit_upload_log_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_policy_audit" TO "anon";
GRANT ALL ON TABLE "public"."inventory_policy_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_policy_audit" TO "service_role";



GRANT ALL ON TABLE "public"."katana_products" TO "anon";
GRANT ALL ON TABLE "public"."katana_products" TO "authenticated";
GRANT ALL ON TABLE "public"."katana_products" TO "service_role";



GRANT ALL ON TABLE "public"."katana_stock_sync" TO "anon";
GRANT ALL ON TABLE "public"."katana_stock_sync" TO "authenticated";
GRANT ALL ON TABLE "public"."katana_stock_sync" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_staging" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_staging" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_staging" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_topics" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_topics" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_topics" TO "service_role";



GRANT ALL ON TABLE "public"."monitored_pages" TO "anon";
GRANT ALL ON TABLE "public"."monitored_pages" TO "authenticated";
GRANT ALL ON TABLE "public"."monitored_pages" TO "service_role";



GRANT ALL ON TABLE "public"."monitored_sites" TO "anon";
GRANT ALL ON TABLE "public"."monitored_sites" TO "authenticated";
GRANT ALL ON TABLE "public"."monitored_sites" TO "service_role";



GRANT ALL ON TABLE "public"."notification_routing" TO "anon";
GRANT ALL ON TABLE "public"."notification_routing" TO "authenticated";
GRANT ALL ON TABLE "public"."notification_routing" TO "service_role";



GRANT ALL ON TABLE "public"."odin_requirements" TO "anon";
GRANT ALL ON TABLE "public"."odin_requirements" TO "authenticated";
GRANT ALL ON TABLE "public"."odin_requirements" TO "service_role";



GRANT ALL ON TABLE "public"."page_improvement_notes" TO "anon";
GRANT ALL ON TABLE "public"."page_improvement_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."page_improvement_notes" TO "service_role";



GRANT ALL ON TABLE "public"."pdp_content" TO "anon";
GRANT ALL ON TABLE "public"."pdp_content" TO "authenticated";
GRANT ALL ON TABLE "public"."pdp_content" TO "service_role";



GRANT ALL ON TABLE "public"."pest_disease_reference" TO "anon";
GRANT ALL ON TABLE "public"."pest_disease_reference" TO "authenticated";
GRANT ALL ON TABLE "public"."pest_disease_reference" TO "service_role";



GRANT ALL ON TABLE "public"."plant_awards" TO "anon";
GRANT ALL ON TABLE "public"."plant_awards" TO "authenticated";
GRANT ALL ON TABLE "public"."plant_awards" TO "service_role";



GRANT ALL ON TABLE "public"."plant_tag_definitions" TO "anon";
GRANT ALL ON TABLE "public"."plant_tag_definitions" TO "authenticated";
GRANT ALL ON TABLE "public"."plant_tag_definitions" TO "service_role";



GRANT ALL ON TABLE "public"."plant_tags" TO "anon";
GRANT ALL ON TABLE "public"."plant_tags" TO "authenticated";
GRANT ALL ON TABLE "public"."plant_tags" TO "service_role";



GRANT ALL ON TABLE "public"."product_bom" TO "anon";
GRANT ALL ON TABLE "public"."product_bom" TO "authenticated";
GRANT ALL ON TABLE "public"."product_bom" TO "service_role";



GRANT ALL ON TABLE "public"."reference_claims" TO "anon";
GRANT ALL ON TABLE "public"."reference_claims" TO "authenticated";
GRANT ALL ON TABLE "public"."reference_claims" TO "service_role";



GRANT ALL ON TABLE "public"."reference_documents" TO "anon";
GRANT ALL ON TABLE "public"."reference_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."reference_documents" TO "service_role";



GRANT ALL ON TABLE "public"."reference_sources" TO "anon";
GRANT ALL ON TABLE "public"."reference_sources" TO "authenticated";
GRANT ALL ON TABLE "public"."reference_sources" TO "service_role";



GRANT ALL ON TABLE "public"."rootstock_reference" TO "anon";
GRANT ALL ON TABLE "public"."rootstock_reference" TO "authenticated";
GRANT ALL ON TABLE "public"."rootstock_reference" TO "service_role";



GRANT ALL ON TABLE "public"."seasonal_selling_policy" TO "anon";
GRANT ALL ON TABLE "public"."seasonal_selling_policy" TO "authenticated";
GRANT ALL ON TABLE "public"."seasonal_selling_policy" TO "service_role";



GRANT ALL ON TABLE "public"."shopify_customers" TO "anon";
GRANT ALL ON TABLE "public"."shopify_customers" TO "authenticated";
GRANT ALL ON TABLE "public"."shopify_customers" TO "service_role";



GRANT ALL ON TABLE "public"."shopify_order_items" TO "anon";
GRANT ALL ON TABLE "public"."shopify_order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."shopify_order_items" TO "service_role";



GRANT ALL ON TABLE "public"."shopify_orders" TO "anon";
GRANT ALL ON TABLE "public"."shopify_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."shopify_orders" TO "service_role";



GRANT ALL ON TABLE "public"."shopify_slugs" TO "anon";
GRANT ALL ON TABLE "public"."shopify_slugs" TO "authenticated";
GRANT ALL ON TABLE "public"."shopify_slugs" TO "service_role";



GRANT ALL ON TABLE "public"."species_pest_disease" TO "anon";
GRANT ALL ON TABLE "public"."species_pest_disease" TO "authenticated";
GRANT ALL ON TABLE "public"."species_pest_disease" TO "service_role";



GRANT ALL ON TABLE "public"."species_reference" TO "anon";
GRANT ALL ON TABLE "public"."species_reference" TO "authenticated";
GRANT ALL ON TABLE "public"."species_reference" TO "service_role";



GRANT ALL ON TABLE "public"."temp_picklist_orders" TO "anon";
GRANT ALL ON TABLE "public"."temp_picklist_orders" TO "authenticated";
GRANT ALL ON TABLE "public"."temp_picklist_orders" TO "service_role";



GRANT ALL ON TABLE "public"."tracklution_events" TO "anon";
GRANT ALL ON TABLE "public"."tracklution_events" TO "authenticated";
GRANT ALL ON TABLE "public"."tracklution_events" TO "service_role";



GRANT ALL ON TABLE "public"."v_ashridge_species_audit" TO "anon";
GRANT ALL ON TABLE "public"."v_ashridge_species_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."v_ashridge_species_audit" TO "service_role";



GRANT ALL ON TABLE "public"."v_conflicting_claims" TO "anon";
GRANT ALL ON TABLE "public"."v_conflicting_claims" TO "authenticated";
GRANT ALL ON TABLE "public"."v_conflicting_claims" TO "service_role";



GRANT ALL ON TABLE "public"."v_customer_plants" TO "anon";
GRANT ALL ON TABLE "public"."v_customer_plants" TO "authenticated";
GRANT ALL ON TABLE "public"."v_customer_plants" TO "service_role";



GRANT ALL ON TABLE "public"."v_unreported_stock_changes" TO "anon";
GRANT ALL ON TABLE "public"."v_unreported_stock_changes" TO "authenticated";
GRANT ALL ON TABLE "public"."v_unreported_stock_changes" TO "service_role";



GRANT ALL ON TABLE "public"."variant_shipping_rootgrow" TO "anon";
GRANT ALL ON TABLE "public"."variant_shipping_rootgrow" TO "authenticated";
GRANT ALL ON TABLE "public"."variant_shipping_rootgrow" TO "service_role";



GRANT ALL ON TABLE "public"."workflow_health" TO "anon";
GRANT ALL ON TABLE "public"."workflow_health" TO "authenticated";
GRANT ALL ON TABLE "public"."workflow_health" TO "service_role";



GRANT ALL ON TABLE "public"."wpt_results" TO "anon";
GRANT ALL ON TABLE "public"."wpt_results" TO "authenticated";
GRANT ALL ON TABLE "public"."wpt_results" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wpt_results_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wpt_results_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wpt_results_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."wpt_test_queue" TO "anon";
GRANT ALL ON TABLE "public"."wpt_test_queue" TO "authenticated";
GRANT ALL ON TABLE "public"."wpt_test_queue" TO "service_role";



GRANT ALL ON SEQUENCE "public"."wpt_test_queue_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."wpt_test_queue_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."wpt_test_queue_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































drop extension if exists "pg_net";

create extension if not exists "pg_net" with schema "public";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.get_channel_health()
 RETURNS TABLE(channel_name text, src text, medium text, last_event_at timestamp with time zone, age_minutes numeric, status text, detail text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$

-- Elevar-based channel health. Data is daily aggregated, not real-time.
-- "last_event_at" = refreshed_at for the most recent day with sessions for that channel.
-- Thresholds: green if data within 2 days, amber within 4, red beyond.
WITH
  active AS (
    SELECT EXTRACT(HOUR FROM NOW() AT TIME ZONE 'UTC')::int >= 6
       AND EXTRACT(HOUR FROM NOW() AT TIME ZONE 'UTC')::int < 21 AS is_active
  ),
  channel_latest AS (
    SELECT channel,
           max(date) AS latest_date,
           max(refreshed_at) AS latest_refresh,
           sum(distinct_sessions) FILTER (WHERE date >= current_date - 1) AS recent_sessions,
           sum(purchase_events) FILTER (WHERE date >= current_date - 1) AS recent_purchases
    FROM attribution_channel_daily
    WHERE date >= current_date - 7
    GROUP BY channel
  )

SELECT 'Google CPC'::text, 'google'::text, 'cpc'::text, g.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - g.latest_refresh)) / 60)::numeric,
  CASE WHEN g.latest_date IS NULL THEN 'red'
       WHEN NOT a.is_active AND g.latest_date >= current_date - 1 THEN 'green'
       WHEN g.latest_date >= current_date - 1 THEN 'green'
       WHEN g.latest_date >= current_date - 3 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN g.latest_date IS NULL THEN 'No Google CPC data in 7 days — campaigns may be paused'
       WHEN NOT a.is_active AND g.latest_date >= current_date - 1 THEN 'Outside active hours — last data: ' || g.latest_date
       WHEN g.latest_date >= current_date - 1 THEN 'Healthy — ' || COALESCE(g.recent_sessions, 0) || ' sessions, ' || COALESCE(g.recent_purchases, 0) || ' purchases'
       WHEN g.latest_date >= current_date - 3 THEN 'Last data: ' || g.latest_date || ' — gap developing, monitor'
       ELSE 'Last data: ' || g.latest_date || ' — campaigns may be paused or budget exhausted' END
FROM channel_latest g, active a
WHERE g.channel = 'Google CPC'

UNION ALL

SELECT 'Bing CPC'::text, 'bing'::text, 'cpc'::text, b.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - b.latest_refresh)) / 60)::numeric,
  CASE WHEN b.latest_date IS NULL THEN 'red'
       WHEN NOT a.is_active AND b.latest_date >= current_date - 1 THEN 'green'
       WHEN b.latest_date >= current_date - 1 THEN 'green'
       WHEN b.latest_date >= current_date - 3 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN b.latest_date IS NULL THEN 'No Bing CPC data in 7 days — campaigns may be paused'
       WHEN NOT a.is_active AND b.latest_date >= current_date - 1 THEN 'Outside active hours — last data: ' || b.latest_date
       WHEN b.latest_date >= current_date - 1 THEN 'Healthy — ' || COALESCE(b.recent_sessions, 0) || ' sessions, ' || COALESCE(b.recent_purchases, 0) || ' purchases'
       WHEN b.latest_date >= current_date - 3 THEN 'Last data: ' || b.latest_date || ' — gap developing, monitor'
       ELSE 'Last data: ' || b.latest_date || ' — campaigns may be paused or budget exhausted' END
FROM channel_latest b, active a
WHERE b.channel = 'Bing CPC'

UNION ALL

SELECT 'Email (Klaviyo)'::text, 'email'::text, 'campaign / flow'::text, k.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - k.latest_refresh)) / 60)::numeric,
  CASE WHEN k.latest_date IS NULL THEN 'amber'
       WHEN k.latest_date >= current_date - 2 THEN 'green'
       WHEN k.latest_date >= current_date - 4 THEN 'amber'
       ELSE 'red' END,
  CASE WHEN k.latest_date IS NULL THEN 'No email events in 7 days — check Klaviyo schedule'
       WHEN k.latest_date >= current_date - 2 THEN 'Healthy — ' || COALESCE(k.recent_sessions, 0) || ' sessions, ' || COALESCE(k.recent_purchases, 0) || ' purchases'
       WHEN k.latest_date >= current_date - 4 THEN 'Last data: ' || k.latest_date || ' — quiet period or no recent campaigns'
       ELSE 'Last data: ' || k.latest_date || ' — check Klaviyo campaign schedule' END
FROM channel_latest k
WHERE k.channel = 'Email'

UNION ALL

SELECT 'AI Search'::text, 'ai'::text, 'referral'::text, ai.latest_refresh,
  ROUND(EXTRACT(EPOCH FROM (NOW() - ai.latest_refresh)) / 60)::numeric,
  CASE WHEN ai.latest_date IS NULL THEN 'amber'
       WHEN ai.latest_date >= current_date - 2 THEN 'green'
       ELSE 'amber' END,
  CASE WHEN ai.latest_date IS NULL THEN 'No AI search traffic detected yet'
       WHEN ai.latest_date >= current_date - 2 THEN 'Active — ' || COALESCE(ai.recent_sessions, 0) || ' sessions (Elevar enrichment)'
       ELSE 'Last AI traffic: ' || ai.latest_date || ' — sporadic, expected for emerging channel' END
FROM channel_latest ai
WHERE ai.channel = 'AI Search';

$function$
;


  create policy "Service role manages sweetpea batch files"
  on "storage"."objects"
  as permissive
  for all
  to service_role
using ((bucket_id = 'sweetpea-batches'::text))
with check ((bucket_id = 'sweetpea-batches'::text));



