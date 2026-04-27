
CREATE TABLE watchdog_alert_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_at          timestamptz NOT NULL DEFAULT now(),
  pattern         text NOT NULL CHECK (pattern IN ('1','2','3')),
  ef_slug         text NOT NULL,
  process_name    text,
  process_summary text,
  failure_reason  text NOT NULL,
  resolved_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
