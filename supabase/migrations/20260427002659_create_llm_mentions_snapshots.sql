CREATE TABLE llm_mentions_snapshots (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  snapshot_date date DEFAULT CURRENT_DATE,
  ashridge_mentions integer,
  ashridge_ai_volume bigint,
  competitors jsonb,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE llm_mentions_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_read" ON llm_mentions_snapshots
  FOR SELECT TO anon USING (true);

CREATE POLICY "service_write" ON llm_mentions_snapshots
  FOR ALL TO service_role USING (true);
