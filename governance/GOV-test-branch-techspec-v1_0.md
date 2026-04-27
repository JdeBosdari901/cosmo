# Test Branch Spin-Up and Teardown — Technical Specification
# GOV-test-branch-techspec-v1_0.md

**Version:** 1.0
**Date:** 27 April 2026
**Status:** AWAITING JdeB SIGN-OFF — do not execute any steps before approval
**Approved by:** [pending]
**Flowchart:** `test-branch-flowchart-v3.mermaid` (in `governance_files` table)
**Governs:** All Supabase branch creation and teardown within the Cosmo project
**Framework:** SYS-drift-prevention-v1_0.md Phase 4

---

## Table of Contents

| Section | Purpose |
|---|---|
| Purpose and scope | What this spec governs and what it does not |
| Infrastructure prerequisites | What must exist before the first branch is created |
| `test_branch_log` table | DDL for the branch instance registry |
| Naming convention | How branches are named |
| Spin-up procedure (S1–S5) | Step-by-step with exact tool calls |
| DRY_RUN injection | Content-pipeline-specific env var pattern |
| Seed data procedure | When seeding is required and how to execute it |
| End-to-end test procedure | How to run and verify a pipeline test on a branch |
| Teardown procedure (D1–D4) | D1 checklist, deletion, archival |
| Promotion procedure | What happens when tests pass |
| HALT conditions | How Claude behaves when a gate fails |
| Registering this process | Row to add to `process_register` |
| Revision log | Version history |

---

## Purpose and Scope

This spec governs every Supabase branch creation and teardown in the Cosmo project. It translates `test-branch-flowchart-v3.mermaid` into executable instructions with exact tool calls, SQL, and decision criteria.

**In scope:**
- Spinning up a branch for any purpose (content pipeline testing, EF development, schema migration testing)
- DRY_RUN injection for content pipeline branches specifically
- Seed data population for content pipeline branches
- Running an end-to-end content pipeline test on a branch
- Tearing down and archiving a branch

**Out of scope:**
- Writing content pipeline EF code (see `SPEC-content-pipeline-v0_2.md`)
- The EF Watchdog process (see EF Watchdog Phase 4 spec, 26 April 2026)
- Production deployments (promotion from branch to production is covered in §"Promotion procedure" but the production deployment steps are in the relevant EF or pipeline spec)

---

## Infrastructure Prerequisites

The following must exist and be verified before the first branch is created. All are one-time setup items — not repeated per branch.

| Item | Status as of 27 April 2026 | Verification |
|---|---|---|
| GitHub integration | **Active.** Repo `JdeBosdari901/cosmo` connected to Supabase. Baseline migration (7,553 lines) + 53 EFs committed 26 April 2026. | `list_branches` returns branch with EFs present after S2. |
| `process_register` table | **Exists.** Created during EF Watchdog Stage 2 (27 April 2026). Tracks governance process documentation. | `SELECT COUNT(*) FROM process_register;` |
| `test_branch_log` table | **Does not yet exist.** Must be created before the first branch spin-up. DDL in next section. | `SELECT COUNT(*) FROM test_branch_log;` after creation. |
| Supabase Management API PAT | **`cosmo-admin` PAT in credentials.** Used for EF secret injection (DRY_RUN). See `SYS-credentials-v1_11.md`. | Test with `GET /v1/projects/cuposlohqvhikyulhrsx` — expect 200. |
| Slack MCP | **Connected.** Channel: `#jdeb-todo-list`. | Used in S5 and D4. |

**Blocking condition:** `test_branch_log` must be created (see next section) before any branch spin-up. `process_register` already exists and does not need to be created.

---

## `test_branch_log` Table

This table tracks every branch instance — one row per branch created. It is distinct from `process_register`, which tracks governance process documentation. `process_register` records the existence and version of this spec; `test_branch_log` records each execution of the process.

### DDL

```sql
CREATE TABLE IF NOT EXISTS public.test_branch_log (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_name          text NOT NULL,
    project_ref          text NOT NULL,
    branch_id            uuid NOT NULL,
    purpose              text NOT NULL,
    dry_run              boolean NOT NULL DEFAULT false,
    created_at           timestamptz NOT NULL DEFAULT NOW(),
    planned_deletion_date date NOT NULL,
    status               text NOT NULL DEFAULT 'ACTIVE'
                           CHECK (status IN ('ACTIVE', 'ARCHIVED')),
    archived_at          timestamptz,
    notes                text
);

COMMENT ON TABLE public.test_branch_log IS
    'Registry of Supabase branch instances. One row per branch created. '
    'Distinct from process_register (which tracks governance process documentation).';
```

**Note on `branch_id` vs `project_ref`:** Supabase branches have two identifiers. `project_ref` is the short alphanumeric string used for all MCP tool calls (`execute_sql`, `list_edge_functions`, etc.). `branch_id` is the UUID returned by `list_branches` and required by `delete_branch`. Both must be recorded at creation — `project_ref` is returned by `create_branch`, `branch_id` requires a `list_branches` call after S2 to retrieve.

---

## Naming Convention

Branch names follow this pattern:

```
[workstream]-[descriptor]-[date]
```

Examples:
- `content-pipeline-test-20260427`
- `schema-migration-pdp-v2-20260427`
- `ef-publish-pdp-v14-20260427`

Keep branch names under 40 characters. No spaces. Hyphens only.

---

## Spin-Up Procedure

This section maps to flowchart steps S1–S5.

### S1 — Create Branch

**Tool:** `Supabase:create_branch` MCP

**Before calling:** Run `Supabase:get_cost` + `Supabase:confirm_cost` to confirm branch cost. Pass the returned `confirm_cost_id` to `create_branch`.

```
create_branch:
  project_id: cuposlohqvhikyulhrsx
  name:       [branch name per naming convention above]
  confirm_cost_id: [id from confirm_cost]
```

**Expected return:** An object containing `project_ref` (the branch's alphanumeric project ID). If `project_ref` is absent or the call errors: **HALT** — report to JdeB before proceeding.

**What Supabase does automatically at this point:** Applies all committed migrations from `JdeBosdari901/cosmo` `main` branch to the new branch database. Replicates schema. Deploys all committed Edge Functions. No manual migration or EF deployment step is needed.

### S2 — Poll Until ACTIVE_HEALTHY

**Tool:** `Supabase:list_branches` MCP (poll)

```
list_branches:
  project_id: cuposlohqvhikyulhrsx
```

Poll at approximately 30-second intervals. Look for the newly created branch by name. Check `preview_project_status`.

**Gate:** `preview_project_status = ACTIVE_HEALTHY` within 3 minutes.
- Yes → retrieve `id` (UUID) from the same row. Record both `project_ref` (from S1) and `branch_id` (this `id` field). Proceed.
- Timeout (3 min) → **HALT** — report last observed status to JdeB.

**Why record `branch_id` here:** `delete_branch` requires the `id` field (UUID), not `project_ref`. Retrieving it now avoids a lookup failure at D2.

---

**Branch creation is complete after S2. The next steps depend on the branch's purpose.**

---

### S3 — DRY_RUN Injection (All Branches)

**Applies to:** Every branch, without exception.

**Purpose:** When `DRY_RUN=true` is set as an EF secret on the branch, Edge Functions that make external API calls (Shopify, Katana, third-party services) skip those calls but proceed with all internal logic including database writes. This ensures branch testing never touches live external systems. For `publish-pdp` specifically: Shopify GraphQL calls are skipped; `pdp_content` INSERT proceeds normally.

**Tool:** `bash_tool` via Supabase Management API.

```bash
curl -s -X POST \
  "https://api.supabase.com/v1/projects/[BRANCH_PROJECT_REF]/secrets" \
  -H "Authorization: Bearer [SUPABASE_PAT_COSMO_ADMIN]" \
  -H "Content-Type: application/json" \
  -d '[{"name": "DRY_RUN", "value": "true"}]'
```

Replace `[BRANCH_PROJECT_REF]` with the `project_ref` from S1. Replace `[SUPABASE_PAT_COSMO_ADMIN]` with the `cosmo-admin` PAT from `SYS-credentials-v1_11.md`.

**Verification:** Re-fetch secrets list and confirm `DRY_RUN` appears:

```bash
curl -s \
  "https://api.supabase.com/v1/projects/[BRANCH_PROJECT_REF]/secrets" \
  -H "Authorization: Bearer [SUPABASE_PAT_COSMO_ADMIN]"
```

Expected: JSON array containing `{"name": "DRY_RUN"}`. If absent: **HALT** — do not proceed to seeding until injection is confirmed.

**Removal at promotion:** When promoting to production, `DRY_RUN` must NOT be present on the production EF. Verify explicitly before production deployment — production EFs must have no `DRY_RUN` secret.

---

### Seed Data Gate (C_seed)

**Decision:** Does the test require seed data in the branch database?

- **Content pipeline test:** Yes — seed data is required (see §"Seed Data Procedure" below).
- **EF code change test (no DB logic):** No — skip to S4.
- **Schema migration test:** Depends on the migration — assess per branch.

If seed data is not required, proceed directly to S4.

---

### S3 — Seed Data (When Required)

**Tool:** `Supabase:execute_sql` MCP, using the **branch** `project_ref` (not `cuposlohqvhikyulhrsx`).

**Critical:** All MCP calls after S2 must use the branch `project_ref`, not the production project ID. Using the production project ID will write seed data to live tables.

Seed data requirements for a content pipeline branch are defined in `SPEC-content-pipeline-v0_2.md` §"Test Branch Seed Data Requirements":

| Table | Minimum rows | Notes |
|---|---|---|
| `species_reference` | 1 | Parent species row for test cultivar. FK dependency. |
| `cultivar_reference` | ≥1 verified row | `rhs_verification_status` not 'unverified'. Pre-flight A2 passes. |
| `shopify_slugs` | 1 row for test slug | `ahrefs_confirmed = true`, `ahrefs_audit_date` within 90 days. Pre-flight A1 passes. |
| `faq_bank` | ≥5 approved rows | `status = 'approved'` for the test species/slug. Pre-flight A3 passes. |
| `governance_files` | Master rules + audit skill + verification hierarchy | Step 1 data load. Copy from production `governance_files`. |
| `pdp_content` | 0 rows for test slug | Tests `version = 1` branch of version logic. |

**Seed SQL is not defined in this spec.** A `seed.sql` file must be authored and committed to `JdeBosdari901/cosmo` before the first content pipeline branch is created. Once committed, Supabase applies it automatically at S1 (no manual S3 needed). Until `seed.sql` is committed, S3 is executed manually via MCP calls.

**Seed data selection:** Use real production data for test rows (copy species/cultivar/slug rows from production). Do not fabricate cultivar data — the pipeline's pre-flight and Step 1 logic reads real cultivar attributes.

**No-operation gate:** After seeding, verify critical rows exist on the branch:

```sql
-- Run on BRANCH project_ref
SELECT
    (SELECT COUNT(*) FROM shopify_slugs WHERE ahrefs_confirmed = true) AS confirmed_slugs,
    (SELECT COUNT(*) FROM cultivar_reference WHERE rhs_verification_status != 'unverified') AS verified_cultivars,
    (SELECT COUNT(*) FROM faq_bank WHERE status = 'approved') AS approved_faqs;
```

Expected: `confirmed_slugs ≥ 1`, `verified_cultivars ≥ 1`, `approved_faqs ≥ 5`. If any fail: **HALT**.

---

### S4 — Register Branch in `test_branch_log`

**Tool:** `Supabase:execute_sql` MCP, using the **production** `project_ref` (`cuposlohqvhikyulhrsx`).

The branch log lives in production so it persists after the branch is torn down.

```sql
INSERT INTO test_branch_log (
    branch_name,
    project_ref,
    branch_id,
    purpose,
    dry_run,
    planned_deletion_date,
    notes
) VALUES (
    '[branch name]',
    '[branch project_ref from S1]',
    '[branch_id UUID from S2]',
    '[one-sentence description of what is being tested]',
    [true if DRY_RUN was injected, else false],
    '[planned deletion date, typically 7 days out]',
    null
)
RETURNING id;
```

**Gate:** Confirm the returned `id` is non-null. If INSERT fails: **HALT**.

---

### S5 — Slack Confirmation

**Tool:** Slack MCP → `#jdeb-todo-list`

Message format:
```
Branch ready: [branch_name]
project_ref: [project_ref]
Purpose: [purpose]
DRY_RUN: [true/false]
Planned deletion: [planned_deletion_date]
```

**STOP: Branch is now ready for use.** All subsequent MCP calls for testing on this branch must use the branch `project_ref`.

---

## End-to-End Test Procedure (Content Pipeline)

This section covers what to run on the branch once it is ACTIVE_HEALTHY, seeded, and DRY_RUN-injected. It applies to content pipeline branches only.

### What constitutes a passing test

All of the following must be true:

1. Pre-flight query (A1/A2/A3) returns `PASS` for all three conditions against the seed data slug.
2. `publish-pdp` EF called on the branch returns HTTP 200.
3. Response body contains `dry_run: true` (confirming DRY_RUN was active).
4. No Shopify GraphQL call was made (confirm in EF logs — no `productUpdate` mutation appears).
5. A `pdp_content` row was written to the branch database at `version = 1`, `status = 'published'`.
6. `faq_bank.used_on_slugs` updated for the 5 FAQs included in the call.

### Verification queries (run on branch project_ref)

```sql
-- Check pdp_content row written
SELECT slug, version, status, published_at, human_edited
FROM pdp_content
WHERE slug = '[test_slug]';
-- Expected: 1 row, version = 1, status = 'published'

-- Check faq_bank updated
SELECT id, used_on_slugs
FROM faq_bank
WHERE '[test_slug]' = ANY(used_on_slugs);
-- Expected: 5 rows
```

### If a test fails

Write a FAILURE REPORT per `SYS-verification-protocol-v1_2.md`. Do not delete the branch until the failure is diagnosed and either fixed and re-tested, or the decision is made to abandon the branch. Premature deletion destroys the evidence.

---

## Teardown Procedure

This section maps to flowchart steps D1–D4.

### D1 — Branch State Assessment (Red + M4)

Claude presents the following checklist to JdeB before any deletion action. **JdeB must explicitly approve deletion before D2 runs.** "The tests are done" is not explicit approval — JdeB must say something equivalent to "proceed with deletion" or "delete the branch."

**Pre-deletion checklist (Claude reads and presents):**

```
Branch:          [branch_name]
project_ref:     [project_ref]
Created:         [created_at from test_branch_log]
Planned deletion: [planned_deletion_date]

□ Test outcome:      [PASS / FAIL / ABANDONED — describe]
□ All test artefacts captured (logs, screenshots, SQL results)?   [Y/N]
□ Any EF code changes ready for production deployment?            [Y/N — what]
□ Any schema changes from this branch to be promoted?             [Y/N — what]
□ seed.sql needs updating based on this test?                     [Y/N — what]
□ Session summary written?                                        [Y/N]
```

Claude does not proceed to D2 until JdeB has seen this checklist and responded with explicit approval to delete.

### D2 — Delete Branch

**Tool:** `Supabase:delete_branch` MCP

**Use `branch_id` (UUID) from `test_branch_log`, not `project_ref`.**

```
delete_branch:
  project_id: cuposlohqvhikyulhrsx
  branch_id:  [branch_id from test_branch_log — the UUID 'id' field]
```

**Gate:** Call `list_branches` and confirm the branch name/id is absent from the result.
- Absent → proceed.
- Still present → **HALT** — report to JdeB. Do not retry deletion without diagnosis.

### D3 — Archive Branch Record

**Tool:** `Supabase:execute_sql` MCP, production project_ref.

```sql
UPDATE test_branch_log
SET status      = 'ARCHIVED',
    archived_at = NOW(),
    notes       = '[outcome summary — one sentence]'
WHERE branch_id = '[branch_id]'
RETURNING status, archived_at;
```

**Gate:** Confirm `status = 'ARCHIVED'` in the returned row. If not updated: **HALT**.

### D4 — Slack Confirmation

**Tool:** Slack MCP → `#jdeb-todo-list`

Message format:
```
Branch deleted: [branch_name]
Outcome: [PASS/FAIL/ABANDONED]
Next action: [e.g. "Ready to deploy publish-pdp v14 to production" / "Debugging continues in new branch"]
```

---

## Promotion Procedure

**Trigger:** D1 checklist confirms tests passed and JdeB approves promotion.

**Content pipeline promotion sequence** (after branch teardown):

1. Deploy updated `publish-pdp` EF to production via `deploy_edge_function` MCP against `cuposlohqvhikyulhrsx`. **Do not set DRY_RUN on production.**
2. Commit EF code to `JdeBosdari901/cosmo` `main` branch (per EF deployment discipline in PI).
3. Run PI bump: apply the two PI changes documented in `SPEC-content-pipeline-v0_2.md` §"PI Changes Required":
   - Remove "Do not publish a PDP or advice page and skip the post-publish schema verification step" from WHAT NOT TO DO.
   - Update "Publish" trigger phrase to remove the manual `pdp_content` step.
4. Bump `publish-pdp` version in `cosmo_docs`.
5. Update `test_branch_log` row status to `ARCHIVED` (done at D3, before promotion).

**For other workstream branches:** Follow the equivalent promotion steps documented in the relevant spec.

---

## HALT Conditions

When any gate fails, Claude's next action is:

1. Stop immediately. Do not attempt to proceed past the failed gate.
2. Write: `HALT — [gate name] failed. [What was expected vs what was returned.]`
3. Report to JdeB with the exact output from the failed step.
4. Take no further action on the branch until JdeB gives an explicit direction.

**Halts do not trigger branch deletion.** The branch is preserved until JdeB decides to debug, abandon, or retry.

---

## Registering This Process in `process_register`

Once this spec is approved by JdeB, insert the following row into `process_register` (production):

```sql
INSERT INTO process_register (
    process_id,
    name,
    version,
    status,
    plain_english_doc,
    flowchart_doc,
    techspec_doc,
    last_changed,
    approved_by
) VALUES (
    'test-branch-spinup',
    'Test Branch Spin-Up and Teardown',
    'v1.0',
    'approved',
    null,
    'test-branch-flowchart-v3.mermaid',
    'GOV-test-branch-techspec-v1_0.md',
    '2026-04-27',
    'JdeB'
);
```

This row links the flowchart and tech spec filenames so any session querying `process_register` can find both documents by name and retrieve them from `governance_files`.

---

## Revision Log

- 27 April 2026 (v1.0): Initial version. Based on `test-branch-flowchart-v3.mermaid` (v3 approved 27 April 2026, uploaded to `governance_files` and committed to GitHub). DRY_RUN injection is a standard step for all branches — not content-pipeline-specific. Defines `test_branch_log` as the branch instance registry, distinct from `process_register` (governance process documentation). Both spec and flowchart committed to `governance/` directory in `JdeBosdari901/cosmo`.
