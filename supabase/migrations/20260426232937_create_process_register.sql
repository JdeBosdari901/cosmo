
CREATE TABLE process_register (
  process_id         text PRIMARY KEY,
  name               text NOT NULL,
  version            text NOT NULL,
  status             text NOT NULL CHECK (status IN ('UNAUDITED','IN_PROGRESS','AUDITED')),
  plain_english_doc  text,
  flowchart_doc      text,
  techspec_doc       text,
  last_audited       date,
  last_changed       date NOT NULL DEFAULT current_date,
  approved_by        text,
  notes              text
);
