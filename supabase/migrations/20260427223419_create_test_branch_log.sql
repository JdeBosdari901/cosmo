-- migration: 20260427223419_create_test_branch_log.sql
-- purpose: registry of test branches created via the S1-S6 spin-up procedure.
--   one row per branch, lifecycle tracked via status column. lives on
--   production so the registry survives test-branch teardown.
-- reversibility: drop table public.test_branch_log cascade.
-- production safety: idempotent (create table if not exists).

create table if not exists public.test_branch_log (
  id                  uuid primary key default gen_random_uuid(),
  git_branch_name     text not null,
  branch_id           uuid not null,
  branch_project_ref  text not null,
  purpose             text not null,
  trigger_commit_sha  text not null,
  dry_run_set         boolean not null default true,
  status              text not null default 'active'
                        check (status in ('active','awaiting_teardown','archived')),
  created_at          timestamptz not null default now(),
  archived_at         timestamptz
);

-- partial unique index: a Git branch name can be reused once the prior
-- registration is archived (otherwise unique would block legitimate reuse).
create unique index if not exists test_branch_log_active_name_uniq
  on public.test_branch_log (git_branch_name)
  where status <> 'archived';

alter table public.test_branch_log enable row level security;

-- no policies: only service_role (which bypasses rls) can read or write.
-- matches the pattern of process_register and watchdog_alert_log.
