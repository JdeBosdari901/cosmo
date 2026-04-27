-- migration: 20260427213759_add_missing_baseline_tables.sql
-- purpose: add three tables that exist in production but were not captured by
--   the 26 april 2026 baseline migration. without these, branches created
--   from the repo come up missing tables that the watchdog (watchdog_alert_log),
--   ai citability research (llm_mentions_snapshots), and process governance
--   (process_register) all depend on.
--
-- affected objects:
--   - public.llm_mentions_snapshots (new table, rls enabled, 5 policies)
--   - public.process_register (new table, rls enabled, no policies)
--   - public.watchdog_alert_log (new table, rls enabled, no policies)
--
-- reversibility: drop table ... cascade for each. data in production is
--   unchanged because every statement is idempotent (create table if not exists,
--   policy creation guarded by not exists check).
--
-- production safety: every statement is a no-op when the object already exists.
--   on a fresh branch, the table, rls state, and policies are all created.
--   on production, where these objects already exist, nothing changes.

-- ------------------------------------------------------------
-- llm_mentions_snapshots
-- ------------------------------------------------------------

create table if not exists public.llm_mentions_snapshots (
  id uuid primary key default gen_random_uuid(),
  snapshot_date date default current_date,
  ashridge_mentions integer,
  ashridge_ai_volume bigint,
  competitors jsonb,
  notes text,
  created_at timestamp with time zone default now()
);

alter table public.llm_mentions_snapshots enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'llm_mentions_snapshots'
      and policyname = 'anon_read'
  ) then
    execute $p$
      create policy "anon_read" on public.llm_mentions_snapshots
        for select to anon using (true)
    $p$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'llm_mentions_snapshots'
      and policyname = 'anon_insert'
  ) then
    execute $p$
      create policy "anon_insert" on public.llm_mentions_snapshots
        for insert to anon with check (true)
    $p$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'llm_mentions_snapshots'
      and policyname = 'authenticated_read'
  ) then
    execute $p$
      create policy "authenticated_read" on public.llm_mentions_snapshots
        for select to authenticated using (true)
    $p$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'llm_mentions_snapshots'
      and policyname = 'authenticated_insert'
  ) then
    execute $p$
      create policy "authenticated_insert" on public.llm_mentions_snapshots
        for insert to authenticated with check (true)
    $p$;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'llm_mentions_snapshots'
      and policyname = 'service_write'
  ) then
    execute $p$
      create policy "service_write" on public.llm_mentions_snapshots
        for all to service_role using (true)
    $p$;
  end if;
end $$;

-- ------------------------------------------------------------
-- process_register
-- ------------------------------------------------------------

create table if not exists public.process_register (
  process_id text primary key,
  name text not null,
  version text not null,
  status text not null check (status in ('UNAUDITED','IN_PROGRESS','AUDITED')),
  plain_english_doc text,
  flowchart_doc text,
  techspec_doc text,
  last_audited date,
  last_changed date not null default current_date,
  approved_by text,
  notes text
);

alter table public.process_register enable row level security;

-- no policies in production for this table; rls enabled means only
-- service_role (which bypasses rls) can read or write. left as-is to
-- mirror production exactly.

-- ------------------------------------------------------------
-- watchdog_alert_log
-- ------------------------------------------------------------

create table if not exists public.watchdog_alert_log (
  id uuid primary key default gen_random_uuid(),
  run_at timestamp with time zone not null default now(),
  pattern text not null check (pattern in ('1','2','3')),
  ef_slug text not null,
  process_name text,
  process_summary text,
  failure_reason text not null,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

alter table public.watchdog_alert_log enable row level security;

-- no policies in production for this table; rls enabled means only
-- service_role (which bypasses rls) can read or write. left as-is to
-- mirror production exactly.
