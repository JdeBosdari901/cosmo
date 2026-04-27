ALTER TABLE workflow_health
  ADD COLUMN monitored boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN workflow_health.monitored IS
  'Whether the EF Watchdog should alert on stale last_success_at for this row. Set FALSE when the underlying process is intentionally paused; the row is preserved for history and easy re-enablement.';
