# Test Branch Teardown Procedure — D1–D4
# GOV-test-branch-teardown-v1_0.md

**Status:** D1–D4 procedures only. The spin-up half (S1–S6) is in the working session transcript and will be reworked in the next session before consolidation.

**Date:** 27 April 2026
**Supersedes:** the D1–D4 sections of `GOV-test-branch-techspec-v1_0.md` (which itself is unapproved)
**Approved:** D1 amendment, D2 Chunks 1–3, D3 Chunks 1–3, D4 — all signed off chunk-by-chunk in session of 27 April 2026
**Flowchart:** `test-branch-flowchart-v3.mermaid` — needs an update to v4 reflecting simplified D2 (no precondition check) and D1's `approved_registry_id` output. Flowchart update is an outstanding item.

---

## Scope of this document

This document covers only the teardown half of the test branch process: D1 through D4. It does not cover S1–S6 (spin-up). S1–S6 was drafted in the same session but the rework into chunk form has not been done; both halves will be consolidated into a single specification once S1–S6 has had the same treatment.

The flowchart and the `test_branch_log` DDL belong with the consolidated specification. They are referenced here but not reproduced.

---

## Inputs

D1 must produce, as an explicit output at the moment of approval:

- **`approved_registry_id`** — the `id` value (uuid) of the `test_branch_log` row that JdeB has approved for deletion. This is the canonical handover value used by D2 Chunk 1 and D3 throughout. Without it, D2 has no defined input.

D1 must also include, in the "For the record" block of its approval message, a line:

```
Registry id:  [test_branch_log.id]
```

This is the visible value from which `approved_registry_id` is taken at approval. The rest of D1's behaviour is unchanged from the existing draft.

---

## D2 — Delete the right branch

D2 has three chunks: identify the right branch, delete it, confirm it is gone.

### D2 Chunk 1 — Identify the right branch

Read the registry row that D1 named, so the rest of D2 acts on the right branch.

```
Supabase:execute_sql
  project_id: cuposlohqvhikyulhrsx
  query:      SELECT branch_id, branch_name FROM test_branch_log WHERE id = '[registry_id]';
```

`[registry_id]` is the value of `approved_registry_id`, set by D1 at the moment JdeB gave approval. D1's specification is responsible for setting it.

Pass `branch_id` to Chunk 2. Keep `branch_name` for use in any messages produced during D2 (it is not used as a tool argument).

If the query returns no row, HALT and present this message:

```
SOMETHING'S GONE WRONG AT D2 (READING THE REGISTRY).

Plain English:
I tried to look up the test_branch_log row that D1 told me to use,
and it isn't there. I've stopped before doing anything else. The
branch on Supabase has not been touched and the registry has not
been changed.

I won't do anything until you say so.

—
For the record:

What failed:  D2 Chunk 1 — registry row not found
Registry id: [registry_id]
```

---

### D2 Chunk 2 — Delete the right branch

Call `delete_branch` with the UUID identified in Chunk 1.

```
Supabase:delete_branch
  branch_id: [branch_id from Chunk 1]
```

`branch_id` is the branch's UUID, not its `project_ref`. The two are different identifiers — passing the slug here will fail.

If the call succeeds, proceed to Chunk 3.

If the call returns an error, HALT and present this message:

```
SOMETHING'S GONE WRONG AT D2 (DELETING THE BRANCH).

Plain English:
I called delete_branch but Supabase returned an error. The branch
may or may not have been deleted — the error needs to be read to
know which. I've stopped before doing anything else. The registry
row has not been changed.

The error returned by Supabase is shown below.

I won't do anything until you say so.

—
For the record:

What failed:  D2 Chunk 2 — delete_branch call
Branch:       [branch_name]
              branch_id: [branch_id]
Error:        [exact error returned by the MCP tool]
```

---

### D2 Chunk 3 — Confirm the branch is gone

Poll `list_branches` until the branch's UUID is no longer in the response.

```
Supabase:list_branches
  project_id: cuposlohqvhikyulhrsx
```

Repeat every 30 seconds until the `branch_id` from Chunk 1 is absent from the returned array, or until 5 minutes have elapsed.

If the `branch_id` is absent, D2 is complete. Hand off to D3.

If 5 minutes elapse and the `branch_id` is still present, HALT and present this message:

```
SOMETHING'S GONE WRONG AT D2 (CONFIRMING DELETION).

Plain English:
I called delete_branch and Supabase accepted the request, but the
branch is still showing in list_branches five minutes later. This
usually means the teardown is just slow rather than failed, but
I've stopped before going any further because the registry should
not be archived while the branch is still alive.

I won't do anything until you say so.

—
For the record:

What failed:  D2 Chunk 3 — branch still present after 5 minutes
Branch:       [branch_name]
              branch_id: [branch_id]
Polls run:    11 (every 30s, t=0 to t=300s)
```

**Note on polling values:** 30-second interval and 5-minute total are conservative defaults. No teardown duration is published in the Supabase Management API reference, CLI reference, or branching documentation as of 27 April 2026. After the first real D2 execution, these values can be tightened in a spec revision based on observed time-to-disappear.

---

## D3 — Archive the registry row

D3 has three chunks: update the row, confirm the update, hand off to D4.

### D3 Chunk 1 — Update the row

Mark the registry row as archived.

```
Supabase:execute_sql
  project_id: cuposlohqvhikyulhrsx
  query:      UPDATE test_branch_log
              SET status = 'ARCHIVED', archived_at = NOW()
              WHERE id = '[approved_registry_id]';
```

`[approved_registry_id]` is the same value used by D2 Chunk 1 — set by D1 at the moment of approval.

If the call returns an error, HALT and present this message:

```
SOMETHING'S GONE WRONG AT D3 (ARCHIVING THE REGISTRY).

Plain English:
The branch has been deleted from Supabase, but I tried to update
the test_branch_log row to ARCHIVED and Supabase returned an error.
The registry is now out of step with reality — the branch is gone
but the row still says ACTIVE. I've stopped before doing anything
else.

The error returned by Supabase is shown below.

I won't do anything until you say so.

—
For the record:

What failed:  D3 Chunk 1 — UPDATE call
Registry id: [approved_registry_id]
Error:       [exact error returned by the MCP tool]
```

If the call returns without error, proceed to Chunk 2.

---

### D3 Chunk 2 — Confirm the update

Read the row back and check status is now `'ARCHIVED'`. The same SELECT also reads `archived_at`, which is then handed forward to D4.

```
Supabase:execute_sql
  project_id: cuposlohqvhikyulhrsx
  query:      SELECT status, archived_at FROM test_branch_log WHERE id = '[approved_registry_id]';
```

Three possible outcomes:

**One row, status = `'ARCHIVED'`** → carry `archived_at` forward into the conversation context for D3 Chunk 3 to hand to D4. Proceed to Chunk 3.

**One row, status = `'ACTIVE'`** → HALT and present this message:

```
SOMETHING'S GONE WRONG AT D3 (CONFIRMING THE ARCHIVE).

Plain English:
The branch has been deleted from Supabase. I ran the UPDATE to
mark the registry row as ARCHIVED and Supabase did not return an
error, but when I read the row back it still says ACTIVE. The
update has not taken effect for some reason. The registry is out
of step with reality — the branch is gone but the row still says
ACTIVE.

I won't do anything until you say so.

—
For the record:

What failed:  D3 Chunk 2 — row still ACTIVE after UPDATE
Registry id: [approved_registry_id]
```

**No row** → HALT and present this message:

```
SOMETHING'S GONE WRONG AT D3 (CONFIRMING THE ARCHIVE).

Plain English:
The branch has been deleted from Supabase, but the registry row
I expected to update is no longer there. Either the registry id
is wrong, or the row was removed between D3 starting and now.
The branch is gone and there is no registry record of it.

I won't do anything until you say so.

—
For the record:

What failed:  D3 Chunk 2 — registry row not found
Registry id: [approved_registry_id]
```

---

### D3 Chunk 3 — Hand off to D4

Pass to D4: `branch_name` (from D2 Chunk 1) and `archived_at` (from D3 Chunk 2's SELECT).

D4 reads any other registry fields it needs from `test_branch_log` directly, using `[approved_registry_id]`.

D3 is complete. Proceed to D4.

---

## D4 — Send the Slack confirmation

D4 has one chunk. Single Slack call.

```
Slack:slack_send_message
  channel_id: [jdeb_todo_channel_id]
  message:
    Branch deleted: [branch_name]

    Plain English:
    The test branch [branch_name] has been deleted from Supabase
    and the test_branch_log row has been archived. Cleanup is complete.

    —
    For the record:

    Registry id:        [approved_registry_id]
    Branch name:        [branch_name]
    Archived at:        [archived_at]
```

If the call returns without error, D4 is complete. **D4 is the closing step of the D1–D4 teardown sequence; nothing follows it.** The conversation has no further teardown action.

If the call returns an error, HALT and present this message:

```
SOMETHING'S GONE WRONG AT D4 (SLACK CONFIRMATION).

Plain English:
The branch has been deleted and the registry has been archived —
the cleanup itself is complete. The Slack confirmation message to
#jdeb-todo-list did not send. Nothing in the Supabase project or
the registry needs putting right; only the notification didn't
reach Slack.

The error returned by Slack is shown below.

I won't do anything until you say so.

—
For the record:

What failed:  D4 — slack_send_message call
Branch:       [branch_name]
Registry id:  [approved_registry_id]
Error:        [exact error returned by the MCP tool]
```

---

## Outstanding items relevant to this document

- Channel ID for `#jdeb-todo-list` should be stored in `SYS-credentials-v1_11.md` so D4 (and any other process sending to this channel) does not need to look it up via `slack_search_channels` on every run. Until then, the placeholder `[jdeb_todo_channel_id]` is resolved at runtime.
- Flowchart needs updating to v4: simplified D2 (no precondition check), D1's `approved_registry_id` output named, edge from D3 archive path tightened to remove the cron-triggered branch which doesn't exist yet.
- This document is a partial spec. Consolidation with S1–S6 (after S1–S6 has been reworked into chunk form) produces the final test branch process specification.

---

## Revision log

- 27 April 2026 (v1.0): D1–D4 procedures consolidated from chunk-by-chunk sign-off in session of 27 April 2026. Replaces the D1–D4 sections of the unapproved `GOV-test-branch-techspec-v1_0.md`.
