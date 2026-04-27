# Content Production and Publish Pipeline — Technical Specification v0.2

**Status:** Working draft. Awaiting JdeB approval before any build begins.
**Supersedes:** v0.1 (AlsoAsked API replaced by DataForSEO organic SERP; no other changes)
**Predecessor:** `SES-summary-2026-04-26-content-pipeline-redesign-v2.md`
**EF Watchdog delegation:** Silent failure monitoring for `publish-pdp` is handled by the EF Watchdog (Phase 4 spec, 26 April 2026 session). This pipeline removes the manual post-publish schema verification step on that basis.

---

## Preconditions

These are maintained by separate processes and must be current before the pipeline runs. If either is stale, that is a failure of the upstream maintenance process, not this pipeline.

### P1 — External authority currency

**Cadence:** Quarterly.

**Authorities in scope:** David Austin (roses), Peter Beales (roses), Thorncroft Clematis (clematis), Downderry Nursery (lavender — snapshot), Sarah Raven (cosmos, dahlias, sweet peas).

**Procedure:** Diff current authority site content against the previous snapshot stored in `monitored_pages` using existing content hash change detection. If no change detected, re-verification is not required for that authority this cycle. If changes detected, re-verify the affected cultivar rows in `cultivar_reference` against the updated source and update `rhs_verification_status`, `verification_notes`, and `verified_at`.

**Schedule:** Calendar entry / Slack reminder. Human-initiated quarterly task.

---

### P2 — Category research freshness

**Cadence:** Quarterly.

**Scope:** Ahrefs keyword data and DataForSEO citability audits per product category. After each run, refresh `shopify_slugs.ahrefs_confirmed`, `ahrefs_volume`, and `ahrefs_audit_date` for the relevant category.

**Schedule:** Same quarterly rhythm as P1. Human-initiated.

---

## Pre-flight Check

Run once per target slug before entering the production layer. Three independent conditions checked simultaneously. Only conditions that fail trigger their corresponding step. All three can be evaluated in a single query.

```sql
-- Pre-flight check for slug = '[slug]'
WITH slug_row AS (
    SELECT id, slug, ahrefs_confirmed, ahrefs_audit_date, species_ref_id
    FROM shopify_slugs
    WHERE slug = '[slug]'
),
a1_check AS (
    SELECT
        CASE
            WHEN NOT EXISTS (SELECT 1 FROM slug_row)
                THEN 'MISSING — slug not in shopify_slugs'
            WHEN (SELECT ahrefs_confirmed FROM slug_row) IS NOT TRUE
                THEN 'FAIL — ahrefs_confirmed is false or null'
            WHEN (SELECT ahrefs_audit_date FROM slug_row) IS NULL
              OR (SELECT ahrefs_audit_date FROM slug_row) < NOW() - INTERVAL '90 days'
                THEN 'STALE — ahrefs_audit_date > 90 days or null'
            ELSE 'PASS'
        END AS a1_status
),
a2_check AS (
    SELECT
        CASE
            WHEN NOT EXISTS (SELECT 1 FROM slug_row)
                THEN 'SKIP — no slug row'
            WHEN EXISTS (
                SELECT 1 FROM cultivar_reference cr
                JOIN slug_row s ON cr.species_ref_id = s.species_ref_id
                WHERE cr.rhs_verification_status = 'unverified'
            )
                THEN 'FAIL — unverified cultivar rows exist for this species'
            ELSE 'PASS'
        END AS a2_status
),
a3_check AS (
    SELECT
        CASE
            WHEN (
                SELECT COUNT(*) FROM faq_bank fb
                JOIN slug_row s ON fb.species_ref_id = s.species_ref_id
                WHERE fb.status = 'approved'
            ) >= 5
            OR (
                SELECT COUNT(*) FROM faq_bank
                WHERE '[slug]' = ANY(used_on_slugs)
                AND status = 'approved'
            ) >= 5
                THEN 'PASS'
            ELSE 'FAIL — fewer than 5 approved FAQs for this species/slug'
        END AS a3_status
)
SELECT
    '[slug]' AS slug,
    (SELECT a1_status FROM a1_check) AS a1_slug_confirmed,
    (SELECT a2_status FROM a2_check) AS a2_cultivar_verified,
    (SELECT a3_status FROM a3_check) AS a3_faq_coverage;
```

**Schema note:** `shopify_slugs.species_ref_id` is the join key to `cultivar_reference`. This is a species-level link. The A2 check therefore flags any unverified cultivar in the species group, not just the specific cultivar being written about. For precise per-cultivar verification, a `cultivar_id` FK on `shopify_slugs` would be needed — flagged as a future schema improvement, not a blocker for v1.

---

## Step A1 — Ahrefs Slug Confirmation

**Trigger:** Pre-flight A1 returns FAIL or STALE.

**Action:** Run Ahrefs keyword check on the proposed slug to confirm keyword volume and intent match. Claude-assisted step using the Ahrefs MCP (`keywords-explorer-overview` or `keywords-explorer-matching-terms`).

**Completion criteria:** Slug confirmed as best available keyword for this product.

```sql
UPDATE shopify_slugs
SET ahrefs_confirmed   = true,
    ahrefs_volume      = [volume],
    ahrefs_audit_date  = CURRENT_DATE,
    notes              = '[rationale if slug changed]',
    updated_at         = NOW()
WHERE slug = '[slug]';
```

---

## Step A2 — Cultivar Row Verification

**Trigger:** Pre-flight A2 returns FAIL.

**Verification procedure:** Per `GOV-verification-hierarchy-v1_0.md`. For each unverified cultivar row in the species group:

1. Identify the appropriate authority tier for this genus (Tier 1: RHS; Tier 2: David Austin, Downderry, Thorncroft as applicable).
2. Cross-check classification, AGM status, and hardiness against that authority.
3. Update `cultivar_reference`:

```sql
UPDATE cultivar_reference
SET rhs_verification_status = 'register_verified_match', -- or appropriate status value
    verification_notes      = '[what was checked and confirmed]',
    verified_at             = NOW()
WHERE id = '[cultivar_uuid]';
```

**Fields requiring gate verification before content use:** `rhs_agm`, `rhs_agm_year`, `rhs_hardiness`, species/group classification, type classification. Per `GOV-verification-hierarchy-v1_0.md` §"The Verification Gate".

**Conflict resolution (Tier 1 vs Tier 2 disagreement):** Tier 1 wins. Set `rhs_verification_status = 'rhs_verified_discrepancy'`, record both values in `verification_notes`.

---

## Step A3 — FAQ Research

**Trigger:** Pre-flight A3 returns FAIL (fewer than 5 approved FAQs for this species/slug).

**Tool:** DataForSEO organic SERP API — existing subscription, $0.002 per call, no additional credentials required.

**Verified working:** Confirmed live 27 April 2026. PAA questions are returned as a `people_also_ask` item block within the standard organic SERP result. The dedicated `/people_also_ask/live/advanced` path does not exist; use `organic/live/advanced` and filter the response.

**Call pattern:**

```bash
POST https://api.dataforseo.com/v3/serp/google/organic/live/advanced
Authorization: Basic anVsaWFuQGFzaHJpZGdldHJlZXMuY28udWs6MjlkZTFlNTNlMDUyMzk1Mg==
Content-Type: application/json

[{
    "keyword": "[product category search term, e.g. 'climbing roses uk']",
    "language_code": "en",
    "location_code": 2826,
    "depth": 10
}]
```

`location_code: 2826` = United Kingdom. `depth: 10` returns one PAA block typically containing 4 questions.

**Response extraction:**

```python
items = response['tasks'][0]['result'][0]['items']
paa_block = next((i for i in items if i['type'] == 'people_also_ask'), None)
questions = [el['title'] for el in paa_block['items']] if paa_block else []
# questions is a list of PAA question strings
```

**Claude selection step (Red):** From the returned questions, Claude selects the most useful for this specific PDP, applying these criteria:

- Prioritise questions a buyer (not just a curious gardener) would ask
- Avoid questions already answered in the body copy
- No overlap in meaning between selected questions
- Answers must be writable within ~30 words with a link to a relevant guide

**Storage in `faq_bank`:**

```sql
INSERT INTO faq_bank (question, answer, category, topic, species_ref_id, status, created_at)
VALUES
    ('[question 1]', '[draft answer 1]', '[category]', '[topic]', '[species_ref_id]', 'draft', NOW()),
    ('[question 2]', '[draft answer 2]', '[category]', '[topic]', '[species_ref_id]', 'draft', NOW()),
    -- repeat for each selected question
    ;
```

Set `status = 'draft'` at INSERT. Claude drafts the answers. JdeB approves or edits. Status updated to `'approved'` after approval. FAQs must reach `'approved'` status before Step 3 can use them.

`used_on_slugs` is populated at Step 6 (after publish), not at insertion.

---

## Step 1 — Load Context

**What to load (sequential MCP calls — pg_net parallelism is a v2 optimisation):**

**1. Governance files** — via `governance_files` table or Storage bucket per PI §"Governance file access":

```sql
SELECT content FROM governance_files
WHERE filename IN (
    'GOV-pdp-master-rules-v8_54.md',
    'GOV-pdp-audit-skill-v3_22.md',
    'GOV-verification-hierarchy-v1_0.md'
);
```

(`GOV-verification-hierarchy-v1_0.md` will already be in context if Step A2 ran.)

**2. Cosmo DB data for this cultivar/species:**

```sql
-- Cultivar and species data (verified rows only)
SELECT cr.*, sr.genus, sr.species, sr.common_name
FROM cultivar_reference cr
JOIN shopify_slugs ss ON cr.species_ref_id = ss.species_ref_id
JOIN species_reference sr ON cr.species_ref_id = sr.id
WHERE ss.slug = '[slug]'
  AND cr.rhs_verification_status != 'unverified';

-- Approved FAQs for this species/slug
SELECT question, answer
FROM faq_bank
WHERE (
    species_ref_id = (SELECT species_ref_id FROM shopify_slugs WHERE slug = '[slug]')
    OR '[slug]' = ANY(used_on_slugs)
)
AND status = 'approved'
ORDER BY created_at;

-- Most recent published version (if any)
SELECT body_html, seo_title, seo_description, version, published_at
FROM pdp_content
WHERE slug = '[slug]' AND status = 'published'
ORDER BY published_at DESC
LIMIT 1;
```

**3. Live Ashridge page** — fetched from `pdp_content` as above. If no published version exists, this step is skipped. Never fetch from the live Shopify URL (PI §"WHAT NOT TO DO").

---

## Step 2 — Write PDP

Red step. Claude produces the PDP HTML following `GOV-pdp-master-rules-v8_54.md`. The master rules file governs this step in full.

---

## Step 3 — Structural Audit + Qualitative Review

### Amber — deterministic checks (scriptable from `GOV-pdp-audit-skill-v3_22.md` §2)

| Check | Criterion | Pass condition |
|---|---|---|
| CHECK 1 | Word count | 600–900 words (body + FAQs, excl. spec panel and Why Buy block) |
| CHECK 3 | H2 contains variety name | Any significant word from cultivar name present; not generic "About…" |
| CHECK 4 | Em dash density | < 0.3/100w → flag; ≥ 0.8/100w → hard fail |
| CHECK 6 | Banned vocabulary | Zero hits from BANNED list; zero multi-word banned phrases |
| CHECK 7 | "It is…" openers | ≤ 2 per PDP |
| CHECK 7a | Exclamation marks | ≤ 1 in body copy |
| CHECK 7b | "There is/are…" openers | ≤ 2 per PDP |
| CHECK 8 | Self-referential content | Zero hits |
| CHECK 11 | Duplicate internal links | Zero duplicates (subject to EXEMPT_URLS list) |
| FAQ count | FAQs present | Exactly 5 `<h3>` + answer pairs in FAQ section |

Any hard fail returns automatically to Step 2. Flag-level findings are included in the issues report delivered at Step 4.

### Red — qualitative checks (Claude judgement)

- Opening paragraph: hooks without generic framing; variety name in first sentence
- H2 editorial quality: describes what is distinctive about this cultivar
- Companion planting: recommendations present, appropriate, and following the Ashridge-first hierarchy
- FAQ quality: genuinely useful to a buyer; ~30 words each with guide link
- Overall tone: matches Ashridge's voice (knowledgeable, not corporate)
- Content accurately reflects the verified cultivar data loaded in Step 1

Both Amber and Red findings are delivered in a single prioritised issues report at the end of Step 3.

---

## Step 4 — JdeB Review

Human step. JdeB approves, requests edits, or rejects. If approved without edits, proceed directly to Step 6. If edits are requested, proceed to Step 5.

---

## Step 5 — Edit Diff

**Trigger:** JdeB makes edits to the draft.

**Procedure:**

1. Save Claude's draft as `/tmp/pdp_draft_original.html` before delivery to JdeB.
2. JdeB returns the edited version (upload or paste).
3. Save edited version as `/tmp/pdp_draft_edited.html`.
4. Run diff:

```bash
diff -u /tmp/pdp_draft_original.html /tmp/pdp_draft_edited.html
```

5. Claude reads the unified diff output and re-enters Step 2 with the edits applied. The diff is the instruction set, not a suggestion.

**Loop:** After re-write, the draft returns to Step 3 (full audit) before re-delivery to Step 4.

---

## Step 6 — Publish

### Current state

`publish-pdp` EF publishes to Shopify via GraphQL, then `pdp_content` INSERT is done as a separate follow-on step in the same conversation.

### Required EF change

The `pdp_content` INSERT must move inside the `publish-pdp` EF execution — writing to Shopify and saving to `pdp_content` happen in the same function call. This closes the monitoring gap: if the EF succeeds, `pdp_content` is written; if the Shopify call fails, neither write happens.

### EF change specification

In the `publish-pdp` Edge Function TypeScript, after the successful Shopify `productUpdate` GraphQL mutation, add:

```typescript
// Determine next version number
const { data: latestVersion } = await supabase
    .from('pdp_content')
    .select('version')
    .eq('slug', slug)
    .order('version', { ascending: false })
    .limit(1)
    .single();

const nextVersion = latestVersion ? latestVersion.version + 1 : 1;

// Insert to pdp_content
const { error: pdpInsertError } = await supabase
    .from('pdp_content')
    .insert({
        slug:            slug,
        version:         nextVersion,
        status:          'published',
        body_html:       body_html,
        seo_title:       seo_title,
        seo_description: seo_description,
        published_at:    new Date().toISOString(),
        human_edited:    humanEdited ?? false,
        notes:           notes ?? null
    });

if (pdpInsertError) {
    // Log but do not fail — Shopify publish already succeeded.
    // EF Watchdog Pattern 2 detects missing pdp_content row on daily check.
    console.error('pdp_content insert failed:', pdpInsertError);
}
```

**Why not rollback on `pdp_content` failure:** The Shopify publish is the primary action. Rolling back a successful Shopify push via a second GraphQL call introduces more risk than the failure it prevents. Instead: log the error; the EF Watchdog Pattern 2 check detects the missing `pdp_content` row on its daily run and fires an alert.

### Updated PI trigger phrase

When this EF change ships, update the "Publish" trigger phrase (PI line 320) to:

> Call the `publish-pdp` Edge Function via `pg_net` to push the approved PDP + SEO metadata to Shopify. The EF saves to `pdp_content` in the same call — no separate `pdp_content` step needed.

### Post-publish: update `faq_bank.used_on_slugs`

```sql
UPDATE faq_bank
SET used_on_slugs = array_append(used_on_slugs, '[slug]')
WHERE id IN ('[faq_uuid_1]', '[faq_uuid_2]', '[faq_uuid_3]', '[faq_uuid_4]', '[faq_uuid_5]');
```

---

## PI Changes Required

These changes must ship in the same PI bump as this process. No earlier, no later.

**Remove from WHAT NOT TO DO (PI line 1096):**

> Do not publish a PDP or advice page and skip the post-publish schema verification step

**Modify "Publish" trigger phrase (PI line 320):** Remove the trailing sentence. Current wording ends with "Then run post-publish schema verification (see Publishing Pipeline)." Remove that sentence. Replace with the updated wording in Step 6 above.

The §"Post-publish schema verification — mandatory" section in PUBLISHING PIPELINE (PI lines 723–770) is retained as documentation of how to verify if needed, but is no longer a mandatory post-publish step.

---

## Test Branch Seed Data Requirements

Per the test branch process spec in Cosmo. Minimum required:

| Table | What | Why |
|---|---|---|
| `shopify_slugs` | 1 row for a real product slug | Pre-flight A1 and A3 queries need this to resolve |
| `species_reference` | Parent species row | FK dependency for `cultivar_reference` |
| `cultivar_reference` | ≥1 verified row for the test species | Pre-flight A2 passes; Step 1 data load has content |
| `governance_files` | Master rules + audit skill + verification hierarchy | Step 1 load |
| `faq_bank` | ≥5 approved rows for the test species | Pre-flight A3 passes; Step 3 FAQ count check passes |
| `pdp_content` | 0 rows for test slug | Tests version=1 branch of version logic in EF |

**Shopify dry-run:** The test branch must not hit the live Shopify store. Options: (a) stub the Shopify GraphQL call in the EF to return a mock success response, or (b) point the EF at a Shopify development store. Determine which is simpler before branch creation — this decision must precede build item (a).

**DataForSEO Step A3 in testing:** Use a real call against the live DataForSEO API (cost: $0.002). The account balance is sufficient. No sandbox or stub needed for this step.

---

## Build Order

Once this spec is approved, build in this order:

| # | Item | Dependency |
|---|---|---|
| (a) | EF change: `pdp_content` INSERT inside `publish-pdp` transaction | Dry-run decision must be made first |
| (b) | DataForSEO PAA call + response parsing for Step A3 | None |
| (c) | Deterministic structural audit script for Step 3 Amber checks | None |
| (d) | Pre-flight check SQL (v1: manual MCP call; v2: wrap in EF) | None |
| (e) | Edit diff automation — file save + diff command pattern | None |

Items (b)–(e) have no dependencies on each other and can proceed in any order once (a) is confirmed safe.

---

## Success Definition

A complete pipeline run is successful when all of the following are true:

- Pre-flight A1, A2, and A3 all passed (or were resolved before production began)
- PDP produced, Amber structural audit clean, qualitative review passed, JdeB approved
- `publish-pdp` EF returned 200
- `pdp_content` row exists with `status = 'published'` at the correct `slug` and `version`
- `faq_bank.used_on_slugs` updated for all FAQs included in the published PDP

---

## Revision Log

- 27 April 2026 (v0.2): AlsoAsked API (Pro subscription required) replaced throughout by DataForSEO organic SERP endpoint. Verified live 27 April 2026 at $0.002/call against existing subscription. No other changes from v0.1.
- 27 April 2026 (v0.1): Initial draft. Two process currency gaps resolved (P1 and P2 quarterly cadences defined). All schema details verified against live database. EF Watchdog delegation confirmed.
