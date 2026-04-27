-- seed.sql
-- Built against: SPEC-content-pipeline-v0_2.md §"Test Branch Seed Data Requirements"
-- Test slug: champagne-moment-floribunda-rose-plants (Rosa, ahrefs_confirmed, audit 2026-04-04)
-- Generated: 27 April 2026

-- ------------------------------------------------------------
-- FK dependency (not in spec — required for cultivar_reference.source_id NOT NULL)
-- ------------------------------------------------------------
INSERT INTO reference_sources (id, source_name, source_type, authority_level, ingestion_status)
VALUES ('1d2d775b-fef3-4aac-9c3f-d094ed0741de', 'RHS Plant Database', 'other', 'primary', 'partial')
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------
-- species_reference
-- ------------------------------------------------------------
INSERT INTO species_reference (id, latin_name, genus, ashridge_product)
VALUES ('1058bd1d-5a3c-4682-8523-bfe722f48723', 'Rosa (garden cultivars)', 'Rosa', true)
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------
-- cultivar_reference — ≥1 verified row
-- ------------------------------------------------------------
INSERT INTO cultivar_reference (id, cultivar_name, species_ref_id, source_id, rhs_verification_status, rhs_agm, rhs_hardiness, flower_colour, cultivar_group)
VALUES ('b3e87013-adef-4b2c-849b-46f215b326a4', 'Climbing Iceberg', '1058bd1d-5a3c-4682-8523-bfe722f48723', '1d2d775b-fef3-4aac-9c3f-d094ed0741de', 'register_verified_match', true, 'H5', 'Pure white', 'Climbing')
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------
-- shopify_slugs — 1 row
-- ------------------------------------------------------------
INSERT INTO shopify_slugs (slug, resource_type, ahrefs_confirmed, ahrefs_audit_date, species_ref_id)
VALUES ('champagne-moment-floribunda-rose-plants', 'product', true, '2026-04-04', '1058bd1d-5a3c-4682-8523-bfe722f48723')
ON CONFLICT (slug) DO NOTHING;

-- ------------------------------------------------------------
-- governance_files — master rules + audit skill + verification hierarchy
-- Content fetched from governance Storage bucket 27 April 2026
-- ------------------------------------------------------------
INSERT INTO governance_files (filename, content, content_type, updated_at, uploaded_by)
VALUES ('GOV-pdp-master-rules-v8_54.md', '# Ashridge Trees — PDP Master Rules v8.54
## The single authoritative document for all PDP and blog post creation. Read this before writing anything.
## Category-specific detail lives in separate reference files.
## Updated 19 April 2026 (v8.54 — Table of Contents block added under H1 per SOP v2.28 §"Governance file ToC-first access". Amended in place later the same day with GOVERNANCE ZIP section Cloudinary → ImageKit cleanup; see revision log. No rule changes. v8.53: see below)

## Table of Contents

This file loads only when a content production task engages it. All entries are **On-demand** per `GOV-amendments-2026-04-19-toc-rollout.md` §5 — no sections load at session start. See SOP v2.28 §"Governance file ToC-first access" for the rule.

| Section | Lines | Purpose | Access |
|---------|-------|---------|--------|
| Timestamp convention | 102-107 | UTC date+time convention for governance files | On-demand |
| 1. STRUCTURE (Varn Model) | 108-319 | PDP section order and spec panel framework | On-demand |
| — H2 format | 123-129 | H2 heading separators, punctuation, comma option | On-demand |
| — Heading relevance for search, organic listings, and AI | 130-144 | Why headings matter for SERP, citations, AI overviews | On-demand |
| — Search-informed heading and FAQ selection | 145-160 | Ahrefs-first principle; highest-volume exact match slug | On-demand |
| — Structuring content for featured snippets and AI overviews | 161-195 | CHECK 16; direct answer first then expand | On-demand |
| — P1 factual anchor (AI citability) | 196-206 | Variety name + 3 factual attributes in first 2 sentences | On-demand |
| — Spec panel principles | 207-217 | Spec panel universal rules | On-demand |
| — Spec panel — category templates | 218-256 | Per-category spec panel field templates | On-demand |
| — Spec panel — AI-priority fields | 257-290 | Good for, Wilt resistance, Similar varieties, Container | On-demand |
| — Word count | 291-303 | 600–900 word target inclusive of all content | On-demand |
| — Body copy paragraphs | 304-309 | Paragraph-level structural rules | On-demand |
| — Other structural rules | 310-319 | Miscellaneous structural constraints | On-demand |
| 2. FAQ RULES | 320-433 | FAQ count, HTML format, tone, length, composition | On-demand |
| — Count and distribution | 322-330 | FAQ count rules by category | On-demand |
| — HTML format | 331-339 | FAQ HTML structure and schema attributes | On-demand |
| — Snippet-ready FAQ answers (CHECK 16) | 340-349 | First sentence standalone response under 50 words | On-demand |
| — Container answer — tiered policy | 350-362 | Tiered policy for container suitability answers | On-demand |
| — Standardised FAQ templates (acceptable repetition) | 363-370 | Repeatable FAQ templates across a batch | On-demand |
| — FAQ theme distribution — search volume strategy | 371-380 | Theme selection driven by search volumes | On-demand |
| — End-of-season FAQ guidance | 381-384 | End-of-season FAQ handling rules | On-demand |
| — Seed-saving FAQ guidance | 385-390 | Seed-saving FAQ handling rules | On-demand |
| — Lifestyle questions (use where space allows) | 391-394 | Optional lifestyle FAQ patterns | On-demand |
| — FAQ H3 phrasing | 395-407 | Mirror natural search queries | On-demand |
| — FAQ answer tone | 408-419 | Opinionated, direct, decisive | On-demand |
| — FAQ answer length | 420-423 | ~30-word target per FAQ answer | On-demand |
| — FAQ minimum composition (AI citability) | 424-433 | CHECK A3 — 2 situation-based + 1 comparative per PDP | On-demand |
| 3. EDITORIAL STYLE | 434-801 | Voice, personality, humour, rhythm, language, calendar | On-demand |
| — Voice | 438-449 | First-person plural default, pronoun conventions | On-demand |
| — Personality and humour | 450-468 | Personality and humour guidance | On-demand |
| — Colloquial voice (E3) | 469-478 | Colloquial register breaks; per-PDP cap | On-demand |
| — EXPERT comment resolution protocol | 479-495 | Process for resolving EXPERT flags mid-draft | On-demand |
| — Explain jargon in parentheses (E12) | 496-499 | Inline jargon-explanation pattern | On-demand |
| — Insider knowledge and operational detail | 500-503 | Nursery-insider detail as trust signal | On-demand |
| — Historical and cultural texture | 504-511 | Historical and cultural context patterns | On-demand |
| — Real people and personal stories (E1) | 512-525 | Named friends, real relationships — anti-AI signal | On-demand |
| — Honest limitations (E4) | 526-537 | Stating limitations as facts | On-demand |
| — Explain the mechanism briefly | 538-543 | Mechanism-explanation pattern | On-demand |
| — Visual and physical detail (E9) | 544-555 | Make abstract things visual | On-demand |
| — Don''t declare favourites publicly | 556-559 | Favourite-declaration prohibition | On-demand |
| — Spec panel hooks with personality (E6) | 560-568 | Spec-panel personality hooks | On-demand |
| — Why Ashridge: plant-specific, not generic (E7) | 569-577 | Why Ashridge plant-specific content rule | On-demand |
| — Noun echo (E8) | 578-583 | Noun-echo pattern | On-demand |
| — Cross-category references in body copy | 584-587 | Cross-category reference rules in body copy | On-demand |
| — Calendar reflects business reality | 588-595 | Calendar claims must reflect Ashridge shipping reality | On-demand |
| — Embedded JdeB instructions are tasks to execute | 596-599 | Embedded JdeB instructions are tasks | On-demand |
| — Pre-writing vocabulary filter | 600-623 | Run CHECK 6 BANNED list before drafting | On-demand |
| — Tautology and redundancy | 624-642 | Tautology and redundancy rules | On-demand |
| — Commit; do not hedge (E5) | 643-669 | Commit-don''t-hedge rule | On-demand |
| — Structural AI tells | 670-685 | Structural AI-tell patterns to avoid | On-demand |
| — Sentence rhythm | 686-709 | Sentence rhythm; fragment openers, fragment emphasis | On-demand |
| — Keyword phrase variation (CHECK 17) | 710-725 | Keyword-phrase-density and variation rules | On-demand |
| — Botanical accuracy over editorial convenience (E10) | 726-733 | Botanical accuracy over editorial convenience | On-demand |
| — Language | 734-744 | Language conventions; number formatting | On-demand |
| — AGM wording — three tiers | 745-754 | AGM wording three-tier rules | On-demand |
| — Readability (CHECK 19) | 755-767 | Flesch-Kincaid grade bands PASS/FLAG/FAIL | On-demand |
| — Paragraph length (CHECK 20) | 768-779 | Paragraph-length caps and page-level thresholds | On-demand |
| — Perennial editorial voice (E-P1 through E-P13) | 780-801 | Perennial-specific editorial patterns E-P1–E-P13 | On-demand |
| 4. LINK FORMAT | 802-819 | Link-format rules and category exemptions | On-demand |
| 4a. CROSS-CATEGORY COMPANION LINKING | 820-865 | Ashridge-first companion linking rule and matrix | On-demand |
| 4b. CROSS-CATEGORY URL MAINTENANCE | 866-906 | URL change register; cross-category slug maintenance | On-demand |
| 5. WHY ASHRIDGE BLOCK | 907-967 | Why Ashridge content framework and rotation rules | On-demand |
| 6. CLAUDE TEST — AI DETECTION SELF-CHECK | 968-1039 | Claude test workflow and current check list | On-demand |
| 7. DO NOT REPEAT (DNR) | 1040-1055 | Phrases and patterns banned from repetition | On-demand |
| 7a. TIDBITS BANK | 1056-1082 | Compilation and tracking of variety-specific tidbits | On-demand |
| 7b. STAGING DATA AND COMPETITOR REFERENCES | 1083-1139 | Abraham Darby rule; competitor name stripping | On-demand |
| 8. CATEGORY REFERENCE FILES | 1140-1159 | Per-category reference file register | On-demand |
| 9. BEFORE YOU START A NEW CATEGORY | 1160-1175 | New-category setup checklist pointer | On-demand |
| 10. DURING A BATCH SESSION | 1176-1201 | Per-PDP workflow and post-batch tasks | On-demand |
| 10a. "CHECK THE PDPs" — FILE INSPECTION TRIGGER | 1202-1244 | Trigger phrase procedure and hygiene scan checks | On-demand |
| 12. HTML OUTPUT FORMAT | 1245-1476 | HTML delivery format, images, filenames, metadata | On-demand |
| — Images, media & visual content | 1259-1350 | Image embedding, alt text, thumbnails, CDN delivery | On-demand |
| — Filename convention | 1351-1448 | PDP and guide filename conventions | On-demand |
| — Deliverables per content type | 1449-1459 | Per-content-type deliverable table | On-demand |
| — Meta description quality (CHECK 21) | 1460-1476 | Meta-description quality rules and length caps | On-demand |
| 13. BLOG POST / GROWING GUIDE RULES | 1477-1541 | Growing guide structure, word count, cross-linking | On-demand |
| DOCUMENT DEPENDENCIES | 1542-1561 | Document-dependencies table for governance files | On-demand |
| GOVERNANCE ZIP — DISTRIBUTION TO HUB AND SPOKE PROJECTS | 1562-1721 | Governance zip rules, pre-build sweep, distribution | On-demand |
| — The problem | 1564-1567 | Problem statement governing the zip mechanism | On-demand |
| — The rule | 1568-1571 | Governance zip core rule | On-demand |
| — Pre-build sweep (mandatory before generating the zip) | 1572-1593 | Pre-build sweep checks A–J | On-demand |
| — What goes in the zips | 1594-1636 | Tier 1 / Tier 2 zip contents by type | On-demand |
| — Zip filename conventions | 1637-1643 | Zip filename conventions and version suffixes | On-demand |
| — Requesting governance files for a spoke project | 1644-1701 | Trigger 7 "Tier 1 Update" request mechanism | On-demand |
| — How to distribute | 1702-1710 | Distribution steps to spoke projects | On-demand |
| — When to update spoke projects | 1711-1721 | Timing rules for spoke project updates | On-demand |
| REVISION LOG | 1722-1764 | Version history and per-version change notes | On-demand |

---

### Timestamp convention

All `.md` governance files show a revision **date and time** (UTC, HH:MM) in both the header and the revision log. This prevents ambiguity when multiple updates happen on the same day.

---

## 1. STRUCTURE (Varn Model)

Every PDP follows this section order:

| # | Section | HTML | Notes |
|---|---------|------|-------|
| 1 | **Spec panel** | `<ul class="pdp-specs">` with `<li><strong>Label:</strong> Value</li>` | Plant summary for the buyer. Always first. Fields vary by category — see category reference file. |
| 2 | **H2 body** | `<h2>Variety Name – Hook</h2>` + 2–3 `<p>` | The main sell. Distinctive opener. |
| 3 | **H2 extra** (optional) | `<h2>Distinctive heading</h2>` + `<p>` | Origin story, unique feature, comparison, breeding context. Use when the variety has a story worth telling. Not filler. |
| 4 | **H2 Planting Companions** | `<h2>Planting Companions</h2>` + `<p>` | 3–6 internal links: within-category product links + at least one cross-category collection link. H2 heading must vary — see category reference for approved variants. See §4a. |
| 5 | **H2 Why Ashridge** | `<h2>Why Ashridge?</h2>` or variant | Core facts + variation. See §5. |
| 6 | **H2 FAQs** | `<h2>Frequently Asked Questions</h2>` + `<h3>`/`<p>` pairs | 5–7 per page. See §2. |

**Summary paragraph** (between spec panel and first H2): One or two sentences distilling the plant''s key appeal. Include physical dimensions where relevant — for climbing plants, give both height and spread so the customer knows how much wall or fence to allocate.

### H2 format

- **Default:** `"Variety Name – Hook"` — en-dash separator with spaces, variety name always present.
- **Comma alternative:** `"Variety Name, Hook"` — comma separator. Used for roses and dahlias. Category reference specifies which separator to use.
- **Strong brand exception:** Plain variety name acceptable (e.g. `"Royal Cafe au Lait Dahlias"`).
- Every H2 across a batch must be unique and ownable. No `"About [Variety]"`. No generic labels.

### Heading relevance for search, organic listings, and AI

Search engines, featured snippets, and AI overviews scan headings to understand what a page and each section covers. A heading that makes sense only in context ("How to Plant", "Aftercare") is wasted opportunity. Every H2 and H3 should make sense **in isolation** — as if the reader (or crawler) saw only the heading with no surrounding text.

**The test:** Read each heading on its own. Does it tell you what the section is about, and for which plant or topic? If the answer is "could be anything", rewrite it.

**Rules:**

- **PDPs:** The variety name must appear in the opening H2 (CHECK 3) and is encouraged in one or two others for reinforcement, but is not required in every H2 — that reads as spammy. **Standardised headings** (Why Buy, FAQs) and **flexible middle H2s** are exempt from the variety-name requirement. A "flexible middle H2" is a heading whose topic is self-contained and identifiable even without the variety name — for example: "Pairing Ideas", "How the Colour Works", "In a Vase", "In the Cut-Flower Garden", "In the Border". The test: can a reader or crawler understand what the section covers without the variety name? If yes, it passes. This is distinct from genuinely generic labels ("Aftercare", "Getting Started", "How to Plant", "About") which fail CHECK 15 because they identify no specific topic at all. H3 FAQ questions naturally contain keywords and are usually fine.
- **Blog posts / guides:** The core topic phrase (e.g. "bulbs in the green", "spring bulbs", "lavender") should appear in every H2 and in H3 sub-headings where the bare word alone is ambiguous. "Snowdrops" as an H3 under a clearly keyword-rich H2 could be acceptable, but "Planting Snowdrops in the Green" is always better.
- **Avoid generic section labels.** "Aftercare", "How to Plant", "Getting Started", "What to Expect" — these tell a crawler nothing. Add the subject: "Aftercare for Bulbs in the Green", "How to Plant Bulbs in the Green".
- **FAQ H3s are already keyword-rich** because they''re phrased as real questions. Don''t change these.
- **Don''t stuff unnaturally.** "How to Plant Bulbs in the Green in Your Garden in the UK for Best Results" is worse than no keywords at all. The heading should read as a natural phrase a gardener would say or search for.
- **Anchor IDs don''t need to change** when headings are updated — keep IDs short and stable for linking.

### Search-informed heading and FAQ selection

Headings and FAQ questions should be informed by what people actually search for, not by what sounds like a textbook contents page. Before writing headings or FAQ questions for any PDP or guide, check Ahrefs (or equivalent) for the actual queries and phrases UK gardeners use about this plant or topic.

**Principles:**

- **Use search data to inform phrasing, not to dictate it.** If 1,900 people a month search "when to plant dahlias," the growing guide H2 should address that question — but the heading can be written in the Ashridge voice ("When to Plant Dahlia Tubers") rather than slavishly echoing the query string. The reader should never feel they are reading SEO copy.
- **FAQ H3s should map to real search queries where they exist.** If "are dahlias poisonous to dogs" has 500 searches a month, that is worth an FAQ. If nobody searches for it, it may still be worth answering — but the high-volume questions come first.
- **Variety-specific questions** (scent, colour, comparisons between named varieties) rarely have measurable search volume but drive AI citation, featured snippet capture, and browsing engagement. Keep these at high coverage alongside the search-informed ones.
- **URL slugs must be ruthlessly efficient.** The highest-volume exact-match term that accurately describes the page content. No padding, no type specifiers unless they carry volume, no words that add length without adding searches. The dahlia advice slug audit (March 2026) found `dahlias-in-pots` at 1,100/mo versus `growing-dahlias-in-pots` at 350/mo — three wasted words costing 3x the traffic.
- **Meta titles work harder than slugs.** Incorporate the second-highest-volume query where natural. Example: the dahlia growing guide slug is `how-to-grow-dahlias` (600/mo) but the meta title should capture "when to plant" (1,900/mo) as well: "How to Grow Dahlias: When to Plant, Care & Feeding | Ashridge".
- **Genus-first word order in H1s and meta titles.** Where Ahrefs data confirms genus-first keyword volume exceeds variety-first, use genus-first word order in H1 and meta title. This is a universal pattern confirmed across every genus tested: "clematis Nelly Moser" (1,100/mo) consistently outperforms "Nelly Moser clematis" (900/mo); armandii 21×, wisteria 3×, honeysuckle 2.8×. Slugs may remain variety-first per convention, as slug word order has less ranking impact than title/H1.
- **Two-register spelling for accented plant names.** For plant names containing accented characters or diacriticals (e.g. Tête-à-tête, Étoile Violette, Cécile Brünner), use the unaccented/simplified form in slugs and meta titles — every accented form tested had zero search volume; all demand sits on the unaccented form. Use the correct RHS-standard form (with accents) in body copy, spec panels, and H1s. This captures search demand while maintaining botanical accuracy. Where neither form has measurable search volume, use the RHS form everywhere.
- **Check parent keywords before targeting high-volume terms.** Not every high-volume term is a product search. "Wisteria tree" (7,500/mo) resolves to its own parent keyword because the queries are problem/advice searches ("wisteria growing into my tree", "can I train wisteria as a tree"), not purchase intent. Always check the parent keyword and SERP intent before assuming a high-volume term warrants a product page — it may belong in a guide FAQ instead.
- **Don''t duplicate the guide.** High-volume generic questions ("when to plant dahlias" at 1,900/mo) belong primarily on the guide. PDP FAQs capture the long-tail variant with the variety name ("when to plant Bishop of Llandaff"). The FAQ search-volume strategy in §2 documents the distribution rules.

### Structuring content for featured snippets and AI overviews

Featured snippets (Google''s "position zero" answer box) and AI overviews both extract content from pages that deliver clear, structured, direct answers. The same structural patterns that win snippets also make content more useful to readers, so this is not gaming — it''s good writing discipline. These rules apply to both PDPs and guides but have most impact on guides, where the longer content and question-based structure create more snippet opportunities.

**The four snippet formats and how to target them:**

**1. Paragraph snippets** (definitions, direct answers). Google extracts a 40–60 word passage that directly answers a question. To target these:
- Place a question or question-like phrase in the H2 or H3 (CHECK 15 already ensures keyword relevance).
- **Deliver the direct answer in the first one or two sentences after the heading** — as if someone asked the question aloud and you''re answering in a single breath. This is the snippet candidate.
- Then expand with detail, context, caveats, and personality in the paragraphs that follow.
- The direct-answer opening does not need to be dry or robotic. "Plant each bulb at a depth of two to three times its own height, measuring from the top of the bulb to the soil surface" is a direct answer and readable prose.

**2. List snippets** (steps, ranked items, grouped recommendations). Google extracts a heading plus the list items beneath it. To target these:
- Use a keyword-rich H2 or H3 directly above the list (not two paragraphs before it).
- Use proper HTML list markup (`<ul>` or `<ol>`) — not just bold text with line breaks.
- Keep list items concise but meaningful. Bold the lead term where it helps scannability.
- The heading should describe what the list contains: "Quick Planting Depth Reference for Spring Bulbs" not "Quick Reference".

**3. Table snippets** (comparisons, data). Google extracts `<table>` HTML directly. To target these:
- Use real HTML `<table>` / `<tr>` / `<td>` markup, not styled divs or images of tables.
- Place a keyword-rich heading directly above the table.
- Keep tables clean — no merged cells, no decorative elements that confuse parsers.

**4. FAQ snippets**. Google can extract individual Q&A pairs from pages with clear question/answer structure. To target these:
- Use `<h3>` for the question (already required by §2).
- **The first sentence of the answer must be a complete, standalone response under 50 words** that would make sense if extracted by itself. This is the single highest-value snippet opportunity on any page because the H3 question IS the search query.
- Then expand with nuance, exceptions, product links, and personality.

**General principles:**
- **Direct answer first, then expand.** This is the universal pattern. Every section — whether after an H2, H3, or FAQ question — should lead with the core answer before adding context. Think of it as inverted pyramid structure. **For PDP body copy P1:** open with a direct characterisation of the variety — what it is and why it is worth buying. Do not open with scene-setting, generalised gardening philosophy, or a paragraph about the genus before mentioning the variety itself.
- **One idea per section.** If a section answers two different questions, split it. Each snippet opportunity needs its own heading.
- **Don''t bury the answer.** If the answer to "How deep should I plant tulips?" is "15–20cm", that number should appear in the first sentence after the heading, not in paragraph three after a history of tulip cultivation.
- **Lists and tables are structural gifts.** Whenever content naturally falls into a list or comparison, use list/table markup rather than running it as prose. Google can extract these formats cleanly.
- **The test:** For each H2/H3 section, read only the heading and the first sentence. If a reader would get a useful, accurate answer from just those two elements, the section is snippet-ready. If they''d be confused or need to read further to understand the basic point, restructure.

### P1 factual anchor (AI citability)

The first two sentences of P1 (the opening paragraph after the spec panel) must contain the variety name plus at least three factual attributes from this list: type/form, colour, height, flowering period, key distinguishing characteristic. Editorial personality follows after the anchor is established.

LLMs extract factual claims from the opening sentences of a page. If P1 opens with editorial colour ("A garden isn''t complete without...") rather than facts, the page is invisible to AI citation. Facts first, personality second.

**Example:**
> Climbing Iceberg is a white climbing floribunda rose, reaching about four metres, with clusters of pure white double flowers from June through to October. It holds the RHS Award of Garden Merit — and deserves it.

The first sentence carries: variety name, colour, type, height, flower form, flowering period. The second adds AGM status. Editorial voice begins after.

### Spec panel principles

- Fields vary by category. See templates below and each category reference file for full detail.
- **Colour line: keep it SHORT.** A few words — "Deep maroon-crimson", "Soft ivory-cream". Save the evocative description (light behaviour, ageing, comparisons) for the body copy. Don''t duplicate body content in the spec line.
- **Scent line: Parsons/fragrance rating + ONE punchy phrase.** Not a mini-description. "3/5 — stronger than you''d expect from a dark variety" is right. A whole sentence is too much.
- **Don''t duplicate information across spec lines.** If "March to May" is on the Delivered line, don''t repeat it on the Plant outdoors line.
- **"by us" not "in Somerset"** for the Sold as line where applicable — warmer and more personal (Somerset is in the body/Why Buy).
- **Omit lines** where the data is genuinely unknown rather than writing "Unknown".
- **Vary the phrasing** of repeated fields (Flowers, Stems, Scent) across a set. Don''t use identical wording on every Spencer or every English lavender. This includes near-synonyms: "strongly scented," "richly perfumed," "well scented," and "heavily perfumed" are all equivalent — treat them as if they were the same phrase. Audit skill CHECK 27b flags synonym-cluster repetition across a batch.
- **Collection line on "Delivered" field.** Every "Delivered" spec line should end with: `. <a href="/pages/collect-your-order-from-castle-cary" rel="noopener noreferrer" target="_blank">Collection from Castle Cary</a> also available`. This is a single subordinate clause appended to the existing delivery text, not a separate spec field.

### Spec panel — category templates

#### Dahlias
```
Variety | Type | Colour | Foliage (if ornamental) | Flower size | Height | Spread | Flowering | Cutting | RHS AGM | Origin (if known) | Sold as | Plant outdoors | Delivered
```

#### Sweet Peas
```
Variety | Type (Spencer/Grandiflora/Mod. Grandiflora) | Colour | Scent (Parsons rating if known) | Stem length | Flowering | RHS AGM | Show class (NSPS) | Breeder | Sold as | Plant outdoors | Delivered
```

#### Lavender
```
Variety | Species (English/Dutch/French + Latin) | Colour | Foliage | Height | Spread | Flowering | Scent (character + camphor note) | Hardiness (H5 fully hardy / H4 borderline) | RHS AGM | Introduced (origin/breeder) | Sold as (pot sizes: P9, 2L, 5L) | Plant outdoors | Delivered
```

#### Cosmos
```
Variety | Species | Type | Colour | Flower size | Foliage | Height | Spacing | Flowering | Cutting | RHS AGM | Sold as | Plant outdoors | Delivered
```

#### Roses
```
Variety | Type (HT/Floribunda/Shrub/Climber/Rambler) | Colour | Fragrance | Height | Spread | Flowering | RHS AGM | Pruning group | Sold as | Plant | Delivered
```

#### Trees / Hedging
```
Variety | Common name | Latin name | Type (deciduous/evergreen) | Mature height | Growth rate | Soil | RHS AGM | Sold as | Plant | Delivered
```

#### Fruit Trees
```
Variety | Fruit type | Rootstock | Pollination group | Self-fertile? | Harvest | Eating/Cooking/Dual | RHS AGM | Sold as | Plant | Delivered
```

Adapt as needed for new categories. The principle: everything a buyer needs to make a quick decision, before they read the body copy.

### Spec panel — AI-priority fields

Four additional fields improve AI citation by providing structured data that LLMs extract directly. Not all apply to every category — category reference files specify which to include.

| Field | Purpose | Example |
|-------|---------|---------|
| **Good for** | Use-case indicator — what situations suit this plant | Walls, fences, pergolas, cutting |
| **Wilt resistance** | Standalone field (clematis only) | Wilt-proof (viticella type) |
| **Similar varieties** | Named comparisons for AI citation | New Dawn (pink), Madame Alfred Carrière (cream) |
| **Container suitable** | Binary + size note | Yes — minimum 45cm pot |

"Good for" and "Container suitable" map to the most common AI query patterns ("best clematis for pots", "climbing plants for fences"). "Similar varieties" triggers comparative citation. "Wilt resistance" addresses the single most common clematis anxiety query.

#### Perennials (salvia, foliage, herbaceous)

```
Variety | Latin name | Type | Flower | Height | Spread | Flowering | Hardiness | Pruning | RHS AGM | Sold as | Plant outdoors | Delivered | Collection
```

**Perennial spec panel rules (SP-P1 through SP-P6):** These override the general spec panel conventions for perennial categories. Source: Hot Lips model PDP edit review.

- **SP-P1: Variety line is name only.** For perennials, the variety line carries the name and nothing else — no hook phrase. The hook moves to the first H2 opening sentence. This differs from climbers and dahlias where the variety line carries a selling hook (see E6 above — perennial exemption noted there).
- **SP-P2: Hardiness in plain English.** Write "Fairly Hardy" or "Fully Hardy", not "H5" or "H4". The RHS H-codes can appear in a parenthetical for knowledgeable readers if space allows, but the primary expression must be readable by a non-expert. Source: Hot Lips uses "Fairly Hardy" not "H5."
- **SP-P3: "Sold as" line.** Standard perennial product is a P9 pot (9cm). Larger sizes (3-litre) may be available seasonally. Use: "Pot-grown plants" as the base wording. In FAQs, the pot size question should use flexible phrasing: "Most of our salvias arrive as P9 plants, but larger sizes are sometimes available — check the product page." Do not promise a specific size in the spec panel unless the category reference confirms it.
- **SP-P4: Flowering season as months.** Write "June–November" not "summer to autumn." Months are more precise and more useful for the reader planning a planting scheme.
- **SP-P5: Single typical height.** Write "80cm (2½ft)" not "60–100cm." The spec panel is a quick reference, not a range. If the range varies significantly by conditions, note it in body copy.
- **SP-P6: Pruning as plain instruction.** Write "Cut back in mid-spring" not "Group 6" or "prune after flowering." The spec panel reader wants to know what to do, not which classification system applies. Group numbers can appear in body copy where they add technical value.

**"Sold as" line:** Always state the product form and quality standard (e.g. "Single tubers, hand-graded, Dutch first-class quality" / "Plug plants, hand-sown by us" / "Bareroot, A-grade").

**PBR variant:** For varieties subject to Plant Breeders'' Rights, the "Sold as" line must read: "P9 and 3L deep pots, grown on by us in Somerset from licensed young plants. Peat-free compost." Do NOT use "grown from cuttings by us" for PBR varieties. The PBR column in the category reference identifies affected varieties.

**"RHS AGM" line:** Check against `R_a_rhs-agm-ornamental-compact.md` (December 2024 edition). State Yes/No. If rescinded, note this.

### Word count

Target 600–1,100 words for all PDP categories. The lower bound reflects shorter FAQ answers (~30 words each, linking to guides) proven editorially in the Ida Mae and Climbing Iceberg PDPs. Where a PDP needs trimming to reach this range, **reduce FAQ word count first** — shorter, tighter FAQ answers are the primary lever. Body copy quality should not be sacrificed for word count.

| Category | Typical range |
|----------|--------------|
| Dahlias | 600–1,100w |
| Sweet peas | 600–1,100w |
| Lavender | 600–1,100w |
| Cosmos | 600–900w |
| Roses | 600–900w |
| Trees/Hedging | TBD |

### Body copy paragraphs

- **Natural 2-paragraph flow preferred.** Short third coda paragraph (staking note, trade-off, urgency line) acceptable.
- Typical lengths: P1 ~80–110 words (character/colour/personality), P2 ~60–100 words (form, performance, commercial context), P3 optional ~25–35 words.
- Do **not** artificially split paragraphs to game CV metrics. Low CV is JdeB''s preferred style.

### Other structural rules

- 4L container size where applicable (per JdeB edit).
- 3–6 internal links per PDP (confirmed Ashridge URLs only).
- All internal links: `rel="noopener noreferrer" target="_blank"` — `rel` before `target`. No exceptions.
- Relative paths only: `/products/[slug]` or `/collections/[slug]`. Never full absolute URLs.
- Link once per variety per PDP in body + companions. A second link in FAQs only where it adds genuine value.

---

## 2. FAQ RULES

### Count and distribution

- **5–7 per page**, matched to the variety and category. Sweet peas: max 5. Cosmos: max 5. Dahlias: 5–7. Lavender: 5–7.
- **Before starting a new category:** search Google for the most commonly asked UK questions for that plant type. Build a categorised FAQ pool in the category reference file.
- **Distribute varied questions** across the set — no two PDPs should share the same FAQ combination.
- **Track which questions land on which PDP** in the category reference file.
- **Collection FAQs (§8j in each category reference file).** Maximum one collection FAQ per PDP. Not every PDP needs one — aim for roughly 1 in 3 PDPs across the range. Vary the question used. Collection FAQs are universal across all categories; only FAQ #44 ("Do you sell [product] at your nursery?") needs the product type swapped per category. All collection FAQ answers link to `/pages/collect-your-order-from-castle-cary`.
- **In guides: don''t repeat what''s already on the same page.** If a FAQ question is answered in the body of the guide, the FAQ answer should be brief and point back — but still name the section or the key fact, not just "see above." "Yes — see the planting depth section above for the exact measurements." is good. "Yes. Just follow the instructions above." is not — it answers nothing in isolation. Do not rewrite the same instructions in FAQ format. This applies to guides where the content is on the same page — PDP FAQs may still give concise standalone answers that link to guides.

### HTML format

```html
<h3>Question text?</h3>
<p>Answer text. Links where relevant.</p>
```

Not `<strong>` + `<br>`. Not `<p><b>Q:</b>`. Always `<h3>` for the question, `<p>` for the answer.

### Snippet-ready FAQ answers (CHECK 16)

The FAQ H3 is the single highest-value featured snippet opportunity on the page — the question IS the search query. Structure every FAQ answer to be snippet-extractable:

- **First sentence: a direct, standalone answer under 50 words.** If Google (or an AI overview) extracted only the H3 and this first sentence, the reader should get a complete, useful answer.
- **Then expand** with detail, exceptions, caveats, product links, and personality in the sentences that follow.
- **Don''t open with "Yes" or "No" alone** — fold it into a complete statement. "Yes, most spring bulbs grow well in pots, especially hyacinths, dwarf daffodils, and crocus" is snippet-ready. "Yes. You can grow many types in pots" is not — it adds nothing a search engine can extract usefully.
- **Don''t open with throat-clearing.** "That''s a great question..." / "It depends on..." / "The answer to this is..." — cut these and start with the answer.
- This rule applies to both PDP FAQs and guide FAQs. Guide FAQs that point back to the body ("See the section above") are exempt since the body section should already be snippet-structured.

### Container answer — tiered policy

Apply to any category where container growing is relevant. Match the answer to the actual plant.

| Tier | Answer style | Criteria |
|------|-------------|----------|
| **Firm YES** | "Yes" with practical instructions (pot size, compost, feeding) | Compact habit, small/mid flowers |
| **Qualified YES** | "Yes, but..." with honest limitations | Borderline — will underperform |
| **Not ideal** | "Not ideal really" with alternatives | Pushing limits |
| **Flat NO** | "No" with vivid reason + redirect to compact alternatives | Too tall, too heavy, too vigorous |

Be commercially generous where honest. A qualified YES sells more than a flat NO. Category reference files define the thresholds for each tier.

### Standardised FAQ templates (acceptable repetition)

These share structure but must be adapted to the specific variety. Use on 7-FAQ PDPs. Omit from 5-FAQ PDPs.

- **Staking:** adapt to variety''s height/flower weight. Include support method + "put in at planting time."
- **Planting depth/timing:** season-appropriate advice. Link to growing guide.
- **Winter lifting/overwintering:** colder/wetter = lift; milder/drained = mulch. Link to overwinter guide.

### FAQ theme distribution — search volume strategy

Before building FAQ sets for a new category, research UK search volumes for the most common questions about that plant type. Distribute FAQ themes across the set in proportion to their search demand, not equally. The category reference file should document target distribution percentages.

**Principles:**
- High-volume generic questions (e.g. "when to plant [plant type]") belong primarily on the growing guide, but PDP FAQs should capture long-tail variants using the variety name.
- Low-volume themes (e.g. container growing at 100/mo) must NOT appear on every PDP. **Each category reference must maintain a closed, approved list of varieties that may carry a container FAQ.** Only varieties on the approved list should include a container FAQ; all others must use a different FAQ theme. The audit skill enforces this per-PDP and the category reference documents the approved list. Target: ~15% of PDPs per category, adjusted to the actual number of varieties that genuinely suit container growing.
- Variety-specific questions (scent, colour, comparisons) have no generic search volume but drive browsing, AI citation, and featured snippet capture — keep these at high coverage.
- Track actual theme distribution in the FAQ tracking grid and rebalance across batches.

### End-of-season FAQ guidance

The correct end-of-season advice for annual plants (sweet peas, cosmos, etc.): **Cut the plant off at ground level. Compost the top growth. Leave the roots in the soil.** Cut at ground level and leave roots to break down in the soil — this adds organic matter and avoids disturbing neighbouring plants. For legumes (sweet peas), there is an additional reason: they fix nitrogen in root nodules, which enrich the soil. Pulling the roots up stops that from happening. Link to the growing guide''s end-of-season section.

### Seed-saving FAQ guidance

For heritage/open-pollinated varieties only. **Critical timing rule:** only let pods form once the plant has been judged finished for the season and is no longer producing enough flowers to justify continued care. If seed sets while the plant is still actively flowering, it reads pod formation as "job done" and stops producing buds within days. Heritage Grandifloras (open-pollinated) will come largely true from saved seed. Modern hybrids, named Spencers, and hammettii crosses may not.

**Commercial tone:** Keep seed-saving FAQs practical and brief. Ashridge sells plugs — the FAQ should not read as a guide to never buying from us again. Frame it as "you can, but our plugs are easier and more reliable" where natural. Target: maximum 3 PDPs per category on heritage varieties only.

### Lifestyle questions (use where space allows)

Holiday neglect, vase life, fragrance (only with variety-specific angle), pet safety, pollinator value, wedding use. Don''t force them — include when there''s something specific to say about this variety.

### FAQ H3 phrasing

FAQ H3 headings should mirror natural search query phrasing, not expert shorthand. The heading is often the exact string a customer types into Google; matching it improves both organic ranking and AI overview citation.

| Less searchable | More searchable |
|----------------|----------------|
| "When should I prune [X]?" | "When is the best time to prune [X]?" |
| "Is [X] the same as [Y]?" | "What is the difference between [X] and [Y]?" |
| "How do I train [X]?" | "What is the best way to grow [X]?" |
| "Does [X] have a scent?" | "Is [X] scented?" |

The pattern: "What is the best...", "When is the best time to...", "What is the difference between..." — these are how real people search.

### FAQ answer tone

FAQ answers should be opinionated and direct, not balanced assessments. The customer came to the page for advice; give it.

| Informative (weaker) | Opinionated (stronger) |
|---------------------|----------------------|
| "The fragrance is slight, noticeable on warm days." | "Don''t grow this for its scent." |
| "It will flower in shade, though less freely than in sun." | "This is the best white climbing rose for shade." |
| "Same flowers, but the climbing version grows taller." | "Same flowers, different size. Four metres vs 90 centimetres." |

Short declarative sentences ("It just works." "Same flowers, different size.") are effective FAQ openers.

### FAQ answer length

**Target: ~30 words per answer.** Guides exist and FAQs link to them — answers give the direct response and the link, no elaboration. The customer gets the answer immediately; the guide gets the click for depth.

### FAQ minimum composition (AI citability)

Every PDP must include at minimum:
- **2 situation-based FAQs** — suitability for specific conditions (aspect, soil, container, structure, companion planting)
- **1 comparative FAQ** — named alternatives with factual differentiators

Situation-based FAQs are the primary AI citation trigger. When a customer asks an LLM "which clematis for a north-facing wall?", the LLM looks for pages that answer that exact question with named varieties and factual reasons. Comparative FAQs ("What is the difference between [X] and [Y]?") serve the same function for comparison queries.

---

## 3. EDITORIAL STYLE

CHECKs 32–42 in the audit skill enforce the editorial voice rules below (originally codified as E1–E11 from systematic comparison of Claude drafts vs JdeB edits across five clematis model PDPs and the How to Grow Wisteria guide, March 2026). Trigger 14 in the trigger phrases file provides the pre-draft questionnaire that gathers JdeB''s input before writing. A future `R_a_ash-gardening-phraseology.md` file will provide a systematic lookup table of formal/AI phrasings mapped to natural gardening equivalents, organised by activity (planting, pruning, watering, feeding, lifting, dividing, propagating, pest control). Until it exists, use the examples in the pre-writing vocabulary filter below and prefer everyday gardening language over formal or technical equivalents.

### Voice

Ashridge''s voice is expert, warm, commercially confident, and human. It sounds like a knowledgeable, opinionated enthusiast talking to someone who shares the passion — not a garden centre label, not a botanical textbook, and not an AI. The reader is treated as an intelligent equal, never as a student. Never be deferential toward the reader; never be neutral where you have a view.

**First person.** "We" is the default for Ashridge-as-business ("we grow these ourselves", "we hand-grade every tuber"). "I" is also acceptable — and often warmer — where the voice reflects a personal JdeB perspective rather than the business as a whole: "I''ve grown this myself", "I find it responds well to...", "I should certainly like to see that one again", "I incline to the latter possibility." Use first person freely and without apology. Neither form should feel forced; use whichever reads most naturally. JdeB''s pronouns are he/him/his.

**Opinionated by default.** Express personal preferences, doubts and enthusiasms directly. Where the evidence supports a view, state it. Do not hedge for the sake of balance. An expert has opinions; an AI is carefully neutral. This applies to varieties ("one of the finest viticellas ever raised"), to growers ("Raymond Evison is almost certainly the greatest living clematis breeder"), to methods ("hard pruning in late February is the right answer; anyone who tells you March is playing it safe"), and to taxonomy or naming disputes ("if the name turns out to be Fred Bloggs, that''s just too bad for the clematis").

**Take editorial positions (E11).** Every PDP should contain at least one editorial position: a recommendation, a preference, a disagreement with conventional advice, or a stated opinion based on nursery experience. "In our experience he performs better like that." "Where we think it looks at its best." "The best way to get rid of them is to tear them off, not to cut them off." Flag with EXPERT comments where Claude is uncertain whether JdeB holds the opinion, but attempt the opinion in the draft rather than writing a neutral placeholder. The pre-draft questionnaire asks: "Any opinions, disagreements with the textbooks, or ''we find that...'' observations for this variety?" (CHECK 41)

**Contractions.** Use contractions in preference to formal negatives throughout body copy. "Don''t" not "do not"; "won''t" not "will not"; "can''t" not "cannot". Formal negatives are a reliable AI tell. (CHECK 43)

### Personality and humour

**Encouraged.** This is the single strongest anti-AI-detection measure. The tone is conversational but never casual. Dry wit surfaces through understatement rather than jokes — the humour comes from deadpan observation, wry aside, or quiet irony, not from trying to be funny. Examples from JdeB''s edits:

- **Commercial confidence:** "sells so well because...", "sells out most springs", "order early"
- **Cultural references:** Farrow and Ball, WYSIWYG, Sarah Raven, Martha Stewart Weddings
- **Human asides:** "beautiful dahlia with the awful name", "you got it", "irresistible"
- **Parenthetical context for beginners:** "(not at all acid)", "(as a garden designer might say)", "(growth buds)"
- **Expert knowledge:** horticultural society shows, breeding histories, nursery trade context
- **Expert editorial opinions:** Statements like "who is probably the greatest living sweet pea breeder" or "one of the finest nurseries in the country" are strong anti-AI signals. An AI hedges; an expert has opinions. Where knowledge supports it, add a brief, confident editorial opinion about breeders, growers, varieties, or the trade. Use sparingly — see "One personalisation per PDP" below for the combined budget rule that governs editorial opinions alongside anecdotes and named friends.

**Criticism.** Be willing to criticise — breeders, nurserymen, taxonomists, other writers, naming committees. Do this with wit rather than sourness, and acknowledge counter-arguments fairly before dismissing them. "If the name turns out to be Fred Bloggs, that''s just too bad for the clematis" is the register. Harsh dismissal is wrong; bland neutrality is equally wrong.

Where you know something an AI couldn''t know, put it in. Where you don''t, flag it:

```html
<!-- EXPERT: [topic] — JdeB to add detail here -->
```

### Colloquial voice (E3)

Every PDP should contain at least one expression that could only come from a specific person rather than from a competent general writer. This is not slang; it is informal English used with editorial intent.

**Examples from JdeB edits:** "Your average superstore trellis." "Impetuous decisions can be changed." "Go together like crumpets and jam." "She does not do things by halves." "You Pays Your Money and You Takes Your Choice." "Say no more."

**The rule is not:** force colloquialisms into every paragraph. It is: write one line per PDP that makes the reader think "a real person wrote this, not a machine."

**Workflow:** The pre-draft questionnaire asks JdeB for any phrases, expressions, or ways of putting things that come to mind for each variety. Claude should also attempt one colloquial expression per draft (flagged with an EXPERT comment if uncertain) rather than waiting for JdeB to supply all of them. (CHECK 34)

### EXPERT comment resolution protocol

JdeB can respond to EXPERT comments in three ways. Claude should act accordingly:

| JdeB action | Meaning | Claude''s response |
|-------------|---------|-------------------|
| **Deletes comment, no replacement text** | Existing copy approved as-is | Remove the comment; copy stays unchanged |
| **Adds `<!-- JdeB: instruction -->` adjacent** | Editorial instruction | Act on the instruction in the next revision, remove both comments |
| **Inserts new `<!-- JdeB: -->` comment anywhere** | New request — addition, correction, link, or new content | Act on it as an editorial instruction |

JdeB can also answer questions posed in EXPERT comments by writing a reply comment. For example:
```html
<!-- EXPERT: Do bulbs need rootgrow? -->
<!-- JdeB: Yes, recommend it and link to /products/bulb-starter-rootgrow-mycorrhizal-fungi -->
```
Claude should treat all `<!-- JdeB: -->` comments as instructions and incorporate them in the next revision.

### Explain jargon in parentheses (E12)

When using a horticultural term that a confident beginner might not know, add a plain-English equivalent in brackets on first use: "climbing sport (version)", "budded (grafted) onto rootstock." One or two words — not a full definition. Do not avoid the term; just bridge it.

### Insider knowledge and operational detail

When you have specific operational detail — process timelines, lifting schedules, staff workflows, growing methods — use it in preference to generic claims. "Lifted on a Monday, checked on Tuesday, sent on Wednesday" is worth ten times more than "dispatched promptly." This is the single strongest anti-AI signal available: information an AI could never generate. Flag with `<!-- EXPERT: -->` where you don''t have the detail and need JdeB to supply it.

### Historical and cultural texture

Weave in historical context — introductions, hybridisers, dates, naming stories — as narrative, not as a list. The story of a cultivar''s origins should read as a detective trail: who found it, where, when, what they called it, who argued about what to call it next, and why we ended up with the name we have. This is where the writing becomes genuinely absorbing rather than merely informative.

"Ernest Markham was named by William Robinson in 1936 — ten years after Markham''s death — from a plant Markham had given him and which Robinson grew on his own south wall at Gravetye Manor. Whether Robinson chose the name out of friendship, gratitude, or guilt at having taken so long about it is a question the record does not answer."

Historical detail should feel earned, not dumped. One well-placed origin story per PDP is usually enough. Where the history is rich (clematis naming disputes, dahlia breeding lineages, heritage sweet pea introductions), let it run — the reader who cares about these things will read every word, and the reader who doesn''t will skip to the next heading without feeling patronised. The variety story research brief (§9, Step 9) provides the four-layer framework for gathering this material.

### Real people and personal stories (E1)

Every PDP should contain at least one reference to a real person, a named relationship, a specific place, or a personal observation. These are the strongest anti-AI signals in the content set and the single largest difference between Claude drafts and JdeB edits.

**What counts:** A named friend''s garden ("my friend Paul, who grows exhibition dahlias"). A family member''s opinion ("our granddaughter in the Brownies"). A specific place visited. A plant seen at a named garden or show. A personal memory. A real customer interaction (anonymised). An observation from Ashridge''s own grounds ("At home we have them in our little orchard"). A real professional relationship ("we buy from the same Dutch grower we''ve used for 20 years"). 50 words of childhood memory can transform an entire section: "I remember my grandmother''s garden in the 1960s, where dahlias lined the path to the greenhouse" is worth more than 200 words of horticultural information.

**What does not count:** Generic phrases like "many gardeners find" or "experienced growers recommend." These are category references, not personal ones.

**Flagging:** These can only come from JdeB. When writing about a topic where personal material would strengthen the copy, flag it with an EXPERT comment tailored to the opportunity type: `<!-- EXPERT: Personal anecdote opportunity — does JdeB grow this variety? -->`, `<!-- EXPERT: Named person opportunity — is there someone JdeB knows who connects to this? -->`, `<!-- EXPERT: Personal history opportunity — any childhood or early career memories connected to this plant? -->`. Never invent personal anecdotes or name real people without JdeB confirmation.

**One personalisation per PDP — the cap.** Personal anecdotes, named friends, family references, childhood memories, and personal editorial opinions are all strong anti-AI techniques. But one per PDP is the limit. A single well-placed personalisation enriches the page; more than one makes it feel crowded and unnatural. Treat all these types as a single shared budget of **one per PDP**. When reviewing or flagging for JdeB: if a draft already contains one personalisation element, do not add EXPERT flags for others on the same PDP.

**Workflow:** Claude must flag at least one EXPERT comment per PDP requesting personal material from JdeB. The pre-draft questionnaire (Trigger 14) is the primary mechanism for gathering this material before writing, so that the anecdote is woven into the text rather than bolted on later. (CHECK 32)

### Honest limitations (E4)

The Why Ashridge block and the body copy should include at least one honest qualification, admission, or limitation per PDP. Trust is built by saying what you cannot do or what is difficult, not by listing only strengths.

**Examples from JdeB edits:** "We generally propagate Apple Blossom from cuttings ourselves, but it is a difficult clematis to propagate so sometimes we buy in rooted cuttings and raise those." "We only buy from other growers in extremis." "If you see a cheap wisteria, it is almost certainly seed grown." "They don''t like our wet winters." "The tubers arrived in poor condition two years running, so we stopped."

Where a variety is not stocked or has been dropped, an honest business reason is more interesting than silent omission. Flag where relevant: `<!-- EXPERT: Why don''t we stock this / why did we drop it? -->`.

**State limitations as facts, not confessions.** "Bad in wet soils. Hates undrained ground. Suffers root rot where there is poor drainage." is correct. Do not preface honest assessments with "honestly," "truthfully," "the honest answer is," or "I have to be honest" — these are throat-clearing that dilutes the point and sounds uncertain. Just state the fact. Fragment openers work well here: "Bad in wet soils. Full stop." reads with more energy than "It should be noted that this variety does not perform well in poorly drained conditions."

**Workflow:** The pre-draft questionnaire asks JdeB whether there is anything honestly difficult, unusual, or worth admitting about producing or growing each variety. Claude should also flag an EXPERT comment in the Why Ashridge block asking: "Is there anything honestly tricky about propagating or growing this variety that we should mention?" (CHECK 35)

### Explain the mechanism briefly

When giving an instruction, add one brief sentence explaining *why* it works — especially for readers who are not yet expert. "The leaves are full of food that drops down into the bulb as the foliage dies back, so they are feeding next year''s flowers" is worth more than "leave the foliage to die back naturally." The mechanism helps a non-expert understand and follow the instruction without looking it up elsewhere.

This is a JdeB hallmark and a strong anti-AI signal: AI gives instructions; an expert explains them. The explanation should be one sentence, not a paragraph. "Plant deep — 15cm of soil above the crown — because the shoot has to find its way up by itself, and the journey strengthens it" is the correct level of detail. Use judgement: mechanical steps (staking, deadheading) don''t need a mechanism explained; biological ones (why not to feed, why to leave foliage) usually do.

### Visual and physical detail (E9)

When describing something the reader may not have seen, make it concrete. "Looks a bit like a dirty bunch of very old carrots with no tops" beats "tuberous root system." Physical, real-world comparisons beat botanical descriptions for non-expert readers.

Every PDP body copy (H2 sections before FAQs) should contain at least one image that the reader can see in their mind: a specific place, a physical scale reference, a sensory description, or a named setting. "First floor bedroom window rose." "Five floors up in Bermondsey." "Satin sheen." "The sweetest-smelling kitchen I''ve ever visited." "Cascades of flowers in May that stop passers-by in the street." Category descriptions like "a vigorous climber" or "large showy flowers" do not count — those are labels, not images.

**When describing flowers, lead with the senses** — size, colour, texture, then scent. Be specific about colour: not purple, but "sumptuous velvety lavender, crimson and purple." Not pink, but "shell-pink, almost translucent at the edges." Use unexpected comparisons for physical features: stamens "like a well-used shaving brush"; seedheads "like miniature porcupines." These specifics are what an AI cannot generate convincingly — they come from looking at the plant.

**Move fluently between botanical precision and sensory description.** Latin binomials, hybridisation parentage, and cultivar names should sit naturally alongside colour, texture, scent, and habit in the same paragraph. The register shift is part of the voice. "C. viticella ''Étoile Violette'' is the viticella you probably picture when someone says the word: a deep, saturated purple that holds its colour without fading, on a plant that flowers until you''re sick of deadheading it." Technical and sensory in the same breath.

**Workflow:** The pre-draft questionnaire asks: "Can you picture this plant somewhere specific — your garden, a friend''s, a garden you''ve visited, a customer''s photo? What does it actually look like in real life?" (CHECK 40)

### Don''t declare favourites publicly

On a public page selling 40+ varieties, never declare one as "our favourite" or "the best." Customers buying other varieties will read it. It is fine to say "one of the most popular" or "a personal favourite of JdeB''s" (if true and JdeB approves), but not "the best dahlia in our range."

### Spec panel hooks with personality (E6)

The variety line in the spec panel is not a data label. It is the first thing the customer reads. It should sell the plant in a phrase that has voice.

**Claude''s typical output:** "Freckles, pruning group 1, winter flowering."
**JdeB''s edits:** "Étoile Violette — unstoppable from July to September." "Elizabeth, pruning group 1 — vanilla-scented pink flowers by the thousand." "Apple Blossom, pruning group 1 — evergreen, scented, and flowering before anything else has started."

**Rule:** The spec panel variety line must contain a hook phrase that would work as a plant label in a garden centre. Pruning group and data points may follow the hook, but the hook comes first or is woven in. No variety line should read as a bare data string. **Perennial exemption:** For perennials, the variety line is the name only (no hook) — see §1 perennial spec panel rules (SP-P1). The hook moves to the first H2 opening sentence instead. (CHECK 37)

### Why Ashridge: plant-specific, not generic (E7)

The Why Ashridge block must contain at least one fact that is specific to the production of that variety at Ashridge, not a generic statement that applies to every plant in the range.

**Generic (insufficient):** "We grow our climbers in peat-free compost using biological controls."
**Plant-specific (good):** "Viticella clematis are among the most satisfying plants to propagate: they root willingly, grow strongly, and give us very few losses." "It is a difficult clematis to propagate so sometimes we buy in rooted cuttings." "We propagate all our montanas ourselves from cuttings. We only buy from other growers in extremis."

**Workflow:** The pre-draft questionnaire asks JdeB: "Anything specific about how we produce this variety — easy/hard to propagate, bought in vs home-grown, losses, quirks?" (CHECK 38)

### Noun echo (E8)

Do not repeat the same noun within 15 words when a pronoun, demonstrative, or elision would be natural. "An east-facing wall works if the wall gets sun" becomes "an east-facing wall works if it gets sun."

**This is not:** a ban on repeating the variety name. Variety names should appear where needed for SEO and clarity. The rule targets unconscious noun echo within a single sentence or across adjacent sentences where the referent is obvious. (CHECK 39)

### Cross-category references in body copy

Weave references to other Ashridge categories into body copy naturally, not just in the companion planting section. "Like cosmos, which also hail from Mexico" in a dahlia sun/site section creates link opportunities and connects the catalogue in the reader''s mind. The cross-category companion matrix (§4a) covers formal link placement; this rule covers informal, contextual mentions that enrich the reading experience.

### Calendar reflects business reality

Growing guides and PDP advice must reflect how the business actually operates, not an idealised or textbook version. If the ordering window runs January–May, say so. If despatch starts late April, say that — not "spring." Check with JdeB on any calendar claim Claude is unsure about.

**Seasonal calendar reference files.** Each category should maintain a `[category]-seasonal-calendar.md` file. The first time a calendar claim is verified by JdeB (e.g. "dahlias come into flower in Somerset in late June"), that answer is added to the file. Once in the file, it is the point of reference for all future PDPs and guides — Claude should consult it rather than generating a new estimate or adding a new EXPERT flag. When a new claim is verified mid-session, add it to the file immediately. The file does not exist yet per category; create it when the first verified claim is established.

**Until a seasonal calendar exists for the category:** flag unverified calendar claims with `<!-- EXPERT: calendar claim — please verify -->` rather than stating them as fact.

### Embedded JdeB instructions are tasks to execute

When JdeB adds instructions in HTML comments (e.g. `<!-- JdeB: please turn Common Farm Flowers into a link -->`), these are tasks for Claude to execute during edit review, not items to pass back to JdeB. Search for URLs, create the link, and remove the comment. The "Edit Review" trigger sequence (see Trigger Phrases file) formalises this as step 3.

### Pre-writing vocabulary filter

Before drafting any PDP or guide, mentally run through the CHECK 6 BANNED vocabulary list. If any banned word would feel natural to use in the piece — "tapestry", "plethora", "leverage", etc. — that''s a signal to rethink the sentence construction before writing, not to write it and remove it afterwards. The goal is to write without reaching for those words in the first place.

| Instead of... | Write... | Why |
|---------------|----------|-----|
| "reach for" | "love" | Warmer |
| "well suited" | "a good choice" | Simpler |
| "garden designers" | "gardeners" | Broader audience |
| "Not really" | "Not ideal really" | Softer commercial tone |
| Technical jargon alone | Jargon + explanation | "(growth buds)" after "eyes" |
| "it has been recognised with" | "it holds" (current AGM) | Direct |
| "makes it an excellent choice for" | "suits" / "works well in" | Less flabby |
| "not to be underestimated" | State the positive claim directly | Cut the padding |
| "whether ... or ..." construction | Rephrase as two sentences | Less formulaic |
| "showcasing" | "showing" / cut | AI word |
| "perfect for borders, pots and vases" | Be specific about why for THIS variety | Generic = bad |
| "For the full seasonal calendar, see..." | "but for full instructions see..." | Joins the flow; broader and more useful |
| "the natural partner – [lengthy justification]" | "the natural partner but for a cooler contrast..." | Cut the justification — get to the next useful thing |
| "not a standard [thing]" | "no ordinary [thing]" | Warmer, more commercial, less clinical |
| Trade terminology ("re-grade", "benchmarked") | Everyday language ("double-check", "tested") | Trade terms create distance. "A-grade Dutch-grown tubers that we double-check before dispatch" not "...that we re-grade ourselves" |
| Digital/tech metaphors ("saturation turned up", "Photoshop", "filter") | Natural, gardener-world comparisons ("a different plant altogether") | Digital metaphors feel AI-generated. Use physical, real-world comparisons instead |
| "The leaves are feeding next year''s flowers" | "The leaves are full of food that drops down into the bulb as the foliage dies back, so they are feeding next year''s flowers" | Don''t just state what happens — explain HOW briefly. The mechanism helps beginners understand and follow the instruction |

### Tautology and redundancy

Cut words that repeat what another word already says. If the reader gets the meaning without the extra word, it shouldn''t be there.

| Don''t write | Write instead | Why |
|-------------|---------------|-----|
| "deadhead the spent flowers" | "deadhead" | deadheading IS removing spent flowers |
| "better than in a catalogue photograph" | "better than in a catalogue" | "catalogue" implies a photograph |
| "both depth of colour and depth of fragrance" | "depth of colour and fragrance" | "both...and" unnecessary; shared noun carries |
| "long enough and straight enough" | "long and straight enough" | "enough" only needs to appear once |
| "No fading, no washing out, no gradual drift" | "No fading, no gradual drift" | two items often stronger than three; "washing out" ≈ "fading" |
| "disappearing into gloom" | "disappearing" | destination already implied |
| "revert back" | "revert" | revert means go back |
| "tall in height" / "pale in colour" | "tall" / "pale" | obviously height / obviously colour |
| "free gift" | "gift" | gifts are free |
| "mix together" | "mix" | mixing is combining |
| "climb up" (for sweet peas) | "climb" | climbing is upward |
| "new introduction" | "introduction" | introductions are new by definition |

### Commit; do not hedge (E5)

Cut words that soften a statement without adding information. Be confident. Replace hedge words and phrases with direct statements wherever the claim is factually defensible. "Can be damaged" becomes "cold winds damage the buds." "May flower less freely" becomes "the colour appears duller." "Consider a different variety" becomes "Don''t try it on a north-facing wall; it will disappoint you."

**Hedge words to avoid or minimise:** can, may, might, perhaps, somewhat, relatively, rather, fairly, quite (as a softener), tend to, a little, a bit, often (when you mean "always" or "usually"), generally (when you mean "always").

**The rule is not:** never qualify. Genuine uncertainty should be expressed honestly. The rule is: do not hedge claims you are confident about. If the plant hates north walls, say so. If it sometimes tolerates shade, say "it tolerates shade" not "it can sometimes tolerate a degree of shade."

**Target:** Fewer than 4 hedge words per 1,000 words of body copy. The count excludes hedges in FAQ answers where genuine uncertainty exists. (CHECK 36)

**Estate-agent adjectives are banned.** "Stunning", "beautiful", "gorgeous", "spectacular", "magnificent" — these are the adjectives of someone who has nothing specific to say. Be specific instead. Not "stunning purple flowers" but "a deep, saturated purple that holds its colour without fading." Not "a beautiful clematis" but "a clematis with more presence than most: the flowers are the size of a side plate and the colour of good red wine." Every time you reach for a generic superlative, stop and describe what you actually see.

| Don''t write | Write instead | Why |
|-------------|---------------|-----|
| "not widely recorded" | "not recorded" | "widely" is a hedge |
| "Some lose their nerve" | "Many lose their nerve" | "Some" is vague AI-speak. "Many" is more committed |
| "the moment the buds crack open" | "when the buds open" | "crack open" is overwrought |
| "a generous bunch will scent the air by morning" | "a bunch in a small room is noticeable" | "generous" is padding; "scent the air" is overwrought |
| "produces freely" | "flowers freely" | "produces" is vague — say what it produces |
| "more contenders than it once did" | "more contenders than it used to" | "used to" is more natural spoken English |
| "The honest answer is that..." | *(just state the answer)* | Announcing honesty is padding — throat-clearing |
| "The simple truth is..." | *(state the truth)* | Same pattern — don''t announce, just say it |
| "Dry bulbs can work" | "Dry bulbs do work" | "Can" hedges; "do" confirms. If it''s true, state it |
| "This variety can grow in shade" | "This variety grows in shade" | Same — "can" implies doubt; drop it |
| "We''ve seen the difference" | "We see the difference" | Present tense = ongoing observation. Past tense = one-off event |
| "We''ve found that..." | "We find that..." | Same principle — present is more authoritative |

### Structural AI tells

These patterns signal AI-generated content. Avoid them.

| Pattern | Fix |
|---------|-----|
| **"It is worth noting that"** | Never write this phrase. If it''s worth noting, note it. The announcement adds nothing. Same family: "it should be noted", "it bears mentioning", "interestingly". Cut and state the fact. |
| **Bullet points in body copy** | Published body copy (PDPs, guides, advice pages) must not use bullet points. Write in prose. Lists should be woven into sentences: "good companions include salvias, verbenas, and ornamental grasses" not a bulleted inventory. Spec panels and FAQs have their own HTML formats; this rule governs running text. |
| **Passive constructions where active will do** | "The variety was introduced by Evison in 1998" → "Evison introduced the variety in 1998." Passive voice has its place (emphasis on the object, unknown agent), but default to active. AI over-uses passive because it avoids commitment to a subject. |
| **Rhetorical question → answer in next paragraph** | Merge into one paragraph. Use "Well," as a conversational bridge. |
| **Justifying what the reader can see** (e.g. explaining why cream and maroon look good together) | Cut. Get to the next useful information. |
| **Three-item "no" lists** ("No X, no Y, no Z") | Two is usually stronger. Cut the weakest. |
| **Three-item repetitive lists** ("You can see X. You can see Y. You can see Z.") | The pattern of three consecutive short sentences with the same subject-verb structure is an AI giveaway. Replace with a single compound sentence or a different construction entirely. Two items are fine; three with identical structure is a signal. |
| **"Including" as sentence-ender** | Ending a sentence with "including" and no list is an AI structural tell. Always complete the thought: "We grow them with alliums, geraniums, and sweet peas." not "We grow them with many companions, including." The list after "including" must always appear. |
| **"Also" as second word** | "It also...", "They also...", "This also..." — rewrite. "Also" in second position signals the point was an afterthought. See §3 Sentence Rhythm. |

### Sentence rhythm

- **Short sentences and fragments (E2).** Use short sentences and sentence fragments as deliberate punctuation of the prose rhythm. A paragraph of 80–100 words should contain at least one sentence of seven words or fewer, or one grammatical fragment used for emphasis. "It grows back. It flowers. Every year." "No hard pruning." "Say no more." "No 20-year gambles here." The rule is not: write in fragments throughout. It is: break up the cadence. A paragraph of exclusively long sentences reads as AI-generated. A paragraph that shifts gear into a short declarative or a fragment reads as a person who has opinions. (CHECK 33)
- **Vary sentence length deliberately.** Short declarative sentences land after longer ones for emphasis: "Small wonder we are exhilarated." "Labour was cheap." The short sentence earns its impact from the contrast with what came before. Do not write sequences of uniformly mid-length sentences — that is the single most reliable AI rhythm tell.
- Use the **colon and semicolon** freely to build sequences rather than fragmenting thoughts into separate sentences. "Choose your position: sunny, well-drained, unamended soil." "Both love poor soil; lavender actually resents rich ground." Semicolons keep related thoughts moving forward together; colons introduce consequences or lists without breaking the flow.
- **Parenthetical asides carry some of the best material.** Work commentary into the flow using parentheses — "(trampling on half a dozen lowly and disregarded victims in our eager progress)" — without apology. These asides are where personality, wit, and insider knowledge live. Parentheses and em-dashes are both acceptable for this purpose; the choice is rhythmic. The zero-dash target (below) applies to lazy or default dash use where a colon, semicolon, comma, or full stop would serve better — not to deliberate rhetorical asides that carry genuine content.
- **Dashes are an AI tell. Minimise them aggressively.** Both en-dashes and em-dashes used as parenthetical punctuation are over-represented in AI-generated text. JdeB''s cosmos guide edit (March 2026) reduced em-dashes from 75 (2.04/100w) to 14 (0.50/100w), an 81% reduction, replacing each with the punctuation that best fits the context. The target is zero em-dashes in body text. Both the cosmos main guide and pots guide achieved 0.0/100w after JdeB editing (March 2026). Dashes should be the last resort, not the default.
- **Choosing the right replacement.** When you would reach for a dash, use the punctuation that fits the job. **Full stop:** when the aside is really a new thought. "Take armfuls. You''re doing the plant a favour." not "Take armfuls --- you''re doing the plant a favour." **Semicolon:** when two clauses are closely related but independent. "Both love poor soil; lavender actually resents rich ground." **Colon:** when introducing a list, explanation, or consequence. "Choose your position: sunny, well-drained, unamended soil." **Comma:** for short parenthetical asides or non-essential detail. "Cosmos stems are green and herbaceous, not woody." not "green and herbaceous --- not woody." **Parentheses:** for genuinely incidental information. "Give them sun and poor soil (seriously, don''t feed them)." **Conjunctions (because, so, but, and):** where the dash was acting as a lazy conjunction. "Cosmos benefit from air circulation because stagnant corners encourage mildew." not "...air circulation --- stagnant corners encourage mildew."
- **The only acceptable uses of dashes** in Ashridge content are: (1) number ranges (en-dash: 30--45cm, July--October); (2) rare genuine interruptions or dramatic pivots where no other punctuation captures the rhythm; (3) the spec panel separator (en-dash: "Variety Name -- Hook"). If you find yourself using more than one dash per 200 words of body copy, go back and replace most of them.
- **Commas over dashes for short asides.** This was the single most frequent edit in JdeB''s cosmos guide review. Where the parenthetical clause is short and the dash would interrupt the flow unnecessarily, prefer a comma. A short qualifier reads more naturally with a comma than bracketed by dashes.
- **Hyphens-as-dashes.** JdeB also prefers not to use hyphens as parenthetical markers ("the cosmos bargain - with provisos - applies"). Commas are better: "the cosmos bargain, with provisos, applies." Hyphens in compound adjectives (one-metre-tall, loam-based) and hyphenated words (semi-double, re-wet) are fine. The rule applies only to hyphens used as dashes.
- "So" and "But" as sentence or paragraph openers are fine. JdeB uses both. They make good conversational bridges.
- **"Also" as second word.** If "also" is the second word of a sentence ("It also flowers...", "They also prefer...", "This also means..."), rewrite the sentence. "Also" in that position is a lazy addition signal — it suggests the point was an afterthought rather than being genuinely part of the structure. Mid-sentence uses of "also" where it is genuinely additive are fine: "they flower freely and also hold well in a vase."
- Trust the reader. Don''t over-explain.
- **Run-together words for emphasis.** Occasionally running words together creates a distinctively human, emphatic effect that no AI would produce. Example from the cosmos guide: "Notmanyflowers though." Use very sparingly (once per 2,000+ words maximum), only where the emphasis genuinely lands, and only in informal guide-style content. This technique is an extremely strong anti-AI signal.
- **Fragment opener.** A punchy sentence-fragment paragraph opener for energy: "Over 57,000. Seriously good going." Two sentence fragments beat a grammatically correct but flat sentence. Use sparingly — one per guide, not one per section. Not subject to the combined budget below (it is a different technique at a different position in the text).
- **Fragment emphasis.** Deliberate internal sentence fragmentation for rhythmic emphasis mid-paragraph: "it just looks. So. Good." Different from the fragment opener technique — this breaks up a sentence from inside rather than opening with a fragment. Use very sparingly (once per 2,000+ words maximum) and only where the emphasis genuinely lands.
- **Combined non-standard formatting budget.** Fragment emphasis and run-together words share a combined budget: maximum one of each per 2,000 words. Do not use both on the same PDP or in the same 2,000-word section of a guide — stacking them undermines the effect of each. Fragment openers are not included in this budget and have their own separate allowance (one per guide).
- **Callback references.** In longer guides, refer back to advice given earlier as though the reader has absorbed it: "we all now know cosmos hates that" (referencing the feeding rule established several sections earlier). This creates a conversational, shared-knowledge tone that reads as human because it assumes the reader has been paying attention. AI-generated content almost never does this. When making callbacks between guides, vary the phrasing: "Caviare for slugs" in the pots guide vs "slug caviare" in the main guide. Word-for-word repeats between pages are less natural than the same idea in different words.
- **Named individuals in anecdotes.** Referencing named people (family members, gardening friends) with specific, unusual details is an extremely strong anti-AI signal. Example from the cosmos pots guide: "My very clever cousin, Catherine grows huge cosmos in one-metre-tall pots... around her swimming pool." AI never invents named relatives with swimming pools. These can only come from JdeB; flag opportunities with EXPERT comments.
- **Colloquial register breaks.** Dropping into very informal vocabulary ("fab," "whopper pots") within otherwise measured prose. AI tends toward uniform register. One or two per guide maximum. PDPs: one maximum — the shorter form doesn''t need more than one.
- **Closing philosophy lines.** A warm sign-off that creates a relationship with the reader: "Remember, gardening is fun. So relax, watch your plants grow and enjoy." AI-generated content almost never does this. One per guide, at the end. (Guides only — PDPs end on FAQs and don''t require a philosophical sign-off.)
- **Nuanced avoidance.** Real expertise shows itself through exceptions, not absolutes. "May compete with cosmos and reduce their flowering, but the combination can be stunning" is stronger than a blanket "avoid ornamental grasses." When writing avoidance advice, consider whether the honest answer includes an exception worth mentioning.

### Keyword phrase variation (CHECK 17)

CHECK 15 requires topic keywords in every heading. CHECK 16 requires direct answers in section openers. Both are correct, but together they create a compounding risk: the exact same multi-word phrase appearing in every heading and every opening sentence looks like keyword stuffing to a search engine, even when each individual instance is justified.

Natural writing varies phrasing. A guide about growing bulbs in pots shouldn''t say "bulbs in pots" identically in every heading — it should alternate with "potted bulbs", "container bulbs", "bulbs in containers", or just "bulbs" where the heading is already specific enough. The subject keyword must be present (CHECK 15); the exact phrasing should vary.

**Rules:**

- **Heading phrase monotony.** No exact multi-word phrase (2+ words) should appear in more than 60% of a page''s H2 headings. If a guide has 9 H2s, the same two-word phrase can appear in at most 5 of them. Use synonyms, partial matches, and natural rewording for the rest. The page title H2 counts toward this total.
- **Exact-phrase density in body copy.** No 3+ word phrase should appear more than 5 times per 1,000 words of body text. Single words and common two-word pairs ("the bulb", "in pots") are exempt — they''re unavoidable when writing about a specific topic. But a three-word string that repeats mechanically ("bulbs in pots", "spring bulbs are", "plant your bulbs") signals over-optimisation.
- **Opening-sentence echo.** No more than 50% of a page''s H2 section openers should contain the exact same multi-word phrase. If every section opens with "Spring bulbs...", the page reads like it was written to rank, not to inform.
- **This is about exact repetition, not topic presence.** A guide about spring bulbs should absolutely mention spring bulbs throughout. The check catches mechanical repetition of the identical string, not natural use of the core vocabulary. "Spring bulbs", "spring-flowering bulbs", "bulbs planted in autumn", and "these varieties" all serve the same purpose with natural variation.
- **Applies to both PDPs and guides**, but guides are at higher risk because they''re longer and have more headings.

**The test:** Read all your H2 headings in a list. If they sound like variations on a theme, that''s good writing. If they sound like the same phrase bolted onto different suffixes ("X for Spring Bulbs", "Y for Spring Bulbs", "Z for Spring Bulbs"), rewrite with more variation.

### Botanical accuracy over editorial convenience (E10)

Never sacrifice botanical truth for editorial flow. A rooted cutting is vegetatively propagated and genetically identical to the parent plant; it cannot be described as potentially seed-grown. A grafted plant''s rootstock shoots are from a different variety, not just "unwanted growth." Clematis pruning groups determine planting depth; getting this wrong is a horticultural error, not a style choice.

**Rule:** When in doubt about a botanical claim, flag it with an EXPERT comment rather than writing something plausible but potentially wrong. Claude should never guess at botanical facts to complete a sentence. (CHECK 42)

**Latin names and cultivar names.** Use cultivar names in single quotation marks per horticultural convention: ''Nelly Moser'', ''Étoile Violette''. Never explain a Latin name if the context makes it clear — if you are writing about clematis and mention C. viticella, the reader who needs to know already does; the reader who doesn''t will not benefit from "(a species of clematis)." Trust the reader''s intelligence. The same applies to parentage notation, hybridisation terminology, and classification systems: use them naturally where they add information, but do not interrupt the flow with explanatory glosses that patronise a knowledgeable reader.

### Language

- UK English. UK seasons. No USDA zones.
- **Number formatting.** Spell out one through nine in running prose ("three plants per pot", "five FAQs"). Use digits for 10 and above. Always use digits for: measurements (30cm, 2m, 4L), temperatures (5°C), percentages (15%), quantities in growing instructions (plant 3 per metre), heights, depths, spacings, dates, and any number immediately followed by a unit. Never spell out units — "30cm", never "thirty centimetres". Mixed cases: "plant three bulbs at 15cm depth" is correct — the count is below 10, the measurement uses digits.
- No emojis. No exclamation marks in body copy except very rarely for genuine surprise or delight (JdeB uses one on Turquoise Lagoon: "and it is a sweet pea!"). Acceptable sparingly in FAQs.
- Oxford comma: use it. "Red, white, and blue."
- **Capitalisation of genus names.** Lowercase in running text: "cosmos," "lavender," "dahlia." Uppercase only when: (a) starting a sentence; (b) immediately before a variety name as a compound proper noun ("Cosmos Sonata White," "Dahlia Café au Lait"); (c) forming part of a species epithet ("Cosmos bipinnatus," "Lavandula angustifolia"). Common-name usage mid-sentence is always lowercase: "the cosmos in the border," "feed cosmos in pots fortnightly," "a pot of cosmos." This applies across all categories. JdeB confirmed this rule on the cosmos pots guide (March 2026): 87 lowercase vs 14 uppercase (all sentence starters or species names) in the main guide.
- 4L container size where applicable.
- Heights: metric first, imperial in brackets. "2m (6–7ft)".
- Vary structure, rhythm and wording across every batch. If you''ve just written a PDP that opens with a colour description, open the next one with a cultural reference or a commercial observation.

### AGM wording — three tiers

| Status | Wording |
|--------|---------|
| **Current AGM** | "holds the RHS Award of Garden Merit" / "awarded the AGM in [year]" |
| **Rescinded** | "was awarded the RHS AGM" (past tense) |
| **Lapsed / unconfirmed** | "was recognised by the RHS" or omit entirely. Never claim a current AGM without verification. |

Check every variety against `R_a_rhs-agm-ornamental-compact.md` (December 2024 edition) before writing.

### Readability (CHECK 19)

Google''s quality rater guidelines and featured snippet selection both favour content at a **Flesch-Kincaid grade level of 6–9**. That''s standard everyday English — short-to-medium sentences, plain vocabulary, active voice. It''s also how Ashridge already writes; the three spring bulb guides scored 7.1, 8.0, and 9.0 when measured.

The rule isn''t "write for children." It''s "don''t write like an academic paper." Gardening content should be clear enough that a complete beginner can follow it, while including enough specific detail (genus names, soil chemistry, planting depths) to satisfy experienced plantspeople.

**Thresholds:**
- **FK Grade 6–9:** PASS — no action needed.
- **FK Grade 9.1–10.5:** FLAG — review for unnecessarily complex sentences. Usually fixable by splitting one or two long sentences.
- **FK Grade above 10.5:** FAIL — the content is significantly harder to read than it should be. Rewrite the densest sections.

**What moves the needle:** Long sentences are the main driver. A 40-word sentence with three clauses pushes the grade up far more than using "rhizome" instead of "root." The fix is almost always splitting compound sentences, not dumbing down vocabulary. Horticultural terms are fine — "Narcissus" is no harder to read than "daffodil" once you''ve encountered it.

### Paragraph length (CHECK 20)

Long paragraphs reduce scanability, especially on mobile. They also discourage search engines from extracting clean passages for featured snippets — a 135-word wall of text is harder to parse than three focused paragraphs.

**Thresholds:**
- **Per paragraph:** FLAG any paragraph over **5 sentences** or **100 words**.
- **Per page:** If more than **15% of paragraphs** exceed 5 sentences, FLAG the page overall.

**Not a strict ceiling.** Some ideas genuinely need 6 sentences in one place — a step-by-step planting sequence, for instance. The flag is a prompt to check whether the paragraph could be split, not an instruction to split it mechanically. The test: does the paragraph cover one idea or two? If two, split at the seam.

**What doesn''t count:** Lists formatted as `<ul>` or `<ol>` don''t trigger this check. Specification panels and table cells don''t either. Only `<p>` blocks in body copy.

### Perennial editorial voice (E-P1 through E-P13)

These rules supplement the universal editorial rules for perennial categories (salvia, foliage & shade, herbaceous). Source: Hot Lips model PDP edit review (March 2026). They apply alongside all universal E-rules and CHECKs.

**Spec panel conventions (E-P1 through E-P6):** These mirror the SP-P rules in §1 but describe the editorial intent rather than the data format. SP-P1: variety line is name only; the hook lives in the first H2 sentence. SP-P2: plain English hardiness. SP-P3: flexible pot size phrasing. SP-P4: months not seasons. SP-P5: single height not range. SP-P6: plain pruning instructions. See §1 for full definitions.

**E-P7: Why Ashridge — plant-specific material.** For perennials, the plant-specific Why Ashridge fact (E7) should address propagation method, growing conditions, or dispatch form for the genus or species, not just the universal core facts. "Viticella clematis are among the most satisfying plants to propagate" is the register. Generic "peat-free, biological controls" alone is insufficient.

**E-P8: Shorter casual final FAQ answers.** The last FAQ answer on a perennial PDP can be deliberately brief and conversational — trailing off rather than formally concluding. "As they say, it''s in the genes." "Go for it." This creates an informal ending that feels human. One per PDP maximum.

**E-P9: Temperature and hardiness in plain language.** When discussing hardiness in body copy, translate RHS H-codes into real-world terms: "it will survive temperatures down to about minus 10°C" rather than "rated H5 by the RHS." The code can appear as context but the reader needs the practical meaning.

**E-P10: Deliberate misspelling (anti-AI-detection measure).** One common misspelling per two PDPs, placed in a section most likely to trigger AI detection. This is a deliberate anti-detection measure, not an error. Examples: "recieve" for "receive", "occassionally" for "occasionally", "seperate" for "separate" — common mistakes a human writer makes under time pressure. Place in mid-paragraph body copy, not in headings, spec panels, or FAQ questions. *Attribution: JdeB editorial decision, March 2026.*

**E-P11: Propagation honesty.** State honestly whether a variety is propagated in-house from cuttings or bought in as young plants and grown on. "We generally propagate [variety] from cuttings ourselves" or "We buy in rooted cuttings and grow them on in Somerset" — both are legitimate and both build trust. PBR varieties must use the bought-in wording (see §5 PBR restriction). Honest propagation detail is a strong E7 signal.

**E-P12: Cross-genus companion linking.** Perennial PDPs should link to at least one companion from a different genus within the same spoke and, where natural, one cross-category companion. The verified collection URLs file provides the link targets for cross-category companions. Within-spoke links use the product URL from the category reference. The companion should feel like a genuine planting recommendation, not a forced internal link.

**E-P13: Seasonal disclaimer.** Where a perennial PDP describes seasonal characteristics (flower colour changes, winter die-back, autumn foliage), include a brief note that the customer''s experience may differ from the description depending on their local conditions and the time of year. "Your plant may look different on arrival — salvias are dispatched in active growth and the bicolour pattern develops as temperatures fluctuate through the season." One per PDP where relevant; not required on every PDP.

---

## 4. LINK FORMAT

- All internal links: `rel="noopener noreferrer" target="_blank"` — `rel` before `target`. No exceptions.
- Relative paths only.
- Link once per variety per PDP in body + companions (CHECK 11).
- A second link in FAQs only where it adds genuine value.
- Collection links go in the Why Ashridge block, matched to the variety''s type.
- **Link text must be descriptive.** The visible anchor text must name what the reader will find. Never use "click here", "find out more", "learn more", "read more", "here", "our range", "this link", or "more information" as link text. Use specific names: "our dahlia collection", "how to grow dahlias", "Bishop of Llandaff". See CHECK 24.
- **Slug verification:** always check the slug in the category reference file (for within-category product links) or the verified collection URL list (for cross-category links) before linking. Misspelt slugs create 404s.
- **Collection slug rule.** When a canonical slug suffix is confirmed via keyword research (e.g. Ahrefs), the collection page slug must be updated to match in the same pass as the product slugs. The verified collection URL list, category reference, audit skill §3.1, and API brief must all be updated simultaneously. The Shopify-default collection slug (e.g. `-seedling-plugs`) is superseded by the Ahrefs-confirmed suffix. CHECK 22 in the audit skill validates collection slugs against the canonical list.

### Category-specific exemptions

- **Dahlias:** CaL family sibling cross-references and David Howard are exempt from duplicate link restrictions (CHECK 11) and link concentration analysis (CHECK 12) — intentional cross-selling.
- Others: document as they arise.

---

## 4a. CROSS-CATEGORY COMPANION LINKING

### The rule

Every PDP''s Planting Companions section should include **at least one recommendation that takes the reader outside the PDP''s own category**, where a genuine horticultural partnership exists. This reflects how real gardeners plant — nobody fills a border with nothing but sweet peas.

### How to link cross-category companions

- **Link to the collection or subcategory page**, not to an individual product.
- **Name 1–3 specific varieties in the text** as suggestions, but do not link them individually.
- **The link goes on the collection name.**
- Check the **verified collection URL list** (`G1_a_ash-verified-collection-urls.md`) for the correct slug.

### Example

> In a cutting garden, plant Daydream alongside warm-toned dahlias — Café au Lait or David Howard would be beautiful — from our <a href="/collections/dahlia-tubers" rel="noopener noreferrer" target="_blank">dahlia collection</a>.

> Sweet peas love to climb through roses. A soft pink like Mollie Rilstone would be lovely threading through a climbing rose — something like Albertine or Compassion from our <a href="/collections/climbing-rose-bushes" rel="noopener noreferrer" target="_blank">climbing roses</a>.

### Avoiding repetition across a set (critical)

**Do not link every PDP in a category to the same cross-category collection.** This is a detectable pattern and a Claude Test concern (CHECK 1, structural repetition).

Rules:
- **Track which cross-category collections are linked from which PDPs** in the category reference file, just as FAQ usage is tracked.
- **Vary the destination across the set.** In a 10-variety Cosmos batch, you might link 3 PDPs to dahlias, 2 to roses, 2 to climbing plants, 1 to ornamental grasses, 1 to lavender, and 1 to sweet peas. Not all 10 to dahlias.
- **Vary the named varieties too.** If one Cosmos PDP suggests "Café au Lait or David Howard" as dahlia companions, the next Cosmos PDP that links to dahlias should name different varieties.
- **The cross-category recommendation must be horticulturally genuine.** Don''t force a link to roses from a hedging PDP just to hit the target. If the only natural cross-category companion is Rosemary (a single product, not a collection), link to the Rosemary product page — that''s fine.
- **Some categories have natural cross-category partners; others don''t.** Bedding plants (cosmos, sweet peas, dahlias) cross-reference each other easily. Hedging plants mostly companion with other hedging. Use common sense — the rule is "at least one where genuine", not "force one onto every PDP regardless".

### Cross-category companion matrix (build per category)

When creating or updating a category reference file, add a section mapping which cross-category collections are natural partners for the category, with example variety suggestions:

```
| Cross-category partner | Collection URL | Example varieties to name | Suits which PDPs? |
|----------------------|----------------|--------------------------|-------------------|
| Dahlias | /collections/dahlia-tubers | CaL, David Howard, Bishop of Llandaff | Warm-toned cosmos |
| Climbing roses | /collections/climbing-rose-bushes | Albertine, Compassion | Sweet peas on obelisks |
| Lavender | /collections/lavender-plants | Hidcote, Munstead | Border edging companions |
```

This ensures variety across the set and prevents every PDP defaulting to the same recommendation.

---

## 4b. CROSS-CATEGORY URL MAINTENANCE

### The problem

When a category undergoes a slug migration (product URLs, guide URLs, or collection URLs), every file across the entire system that links to URLs in that category needs checking. The dahlia slug migration (March 2026) required correcting 64 product slugs plus 7 guide slugs — and those stale links existed not just in dahlia files but in model PDPs, growing guides, and potentially in PDPs from other categories that link to dahlias as companions.

### The URL change register

The hub maintains a **URL change register** — a set of reference documents listing old→new URL mappings by category. These are stored as hub-only reference files. Any file in any spoke that contains an `href` can be checked against the register.

**Current register entries:**

| Category | Register document | Redirects | Date |
|----------|------------------|-----------|------|
| Dahlias | `R_a_dahlia-301-redirect-table.md` + `R_a_dahlia-advice-slug-audit-vs-ahrefs.md` | 64 products + 7 advice pages | 8 Mar 2026 |

New entries are added whenever a category undergoes slug migration. The setup checklist (Step 4) generates the redirect table as part of the slug verification process.

### Rules

1. **When a spoke project''s PDPs are checked** (via "Check the PDPs" trigger, §10a), the hygiene scan must cross-check all `href` values against the URL change register as well as the spoke''s own category reference. This catches cross-category stale links — e.g. a cosmos PDP linking to a dahlia product using the old slug.

2. **When "Tier 1 Update" is triggered** (Trigger 7 in the trigger phrases file), the confirmation table must flag any outstanding URL changes from the register that affect the destination spoke. Example: if the dahlia register was updated after the cosmos spoke was last synced, the Tier 1 Update output should note "Dahlia URL migration (8 Mar 2026) — cosmos spoke PDPs may contain stale dahlia links."

3. **When new guide or PDP files are added to the hub** (Tier 2 models, advice pages), they must be checked against the current register before upload. No file should enter the hub with known stale URLs.

4. **When a guide is updated for Shopify** in any spoke, all internal `href` values must be checked against the register before delivery. The "For Shopify" trigger (Trigger 1) should include this as a verification step.

### Cascade principle

A URL migration in category X does not require immediately re-editing every file in every other category. It requires:
- Updating the hub governance files (master rules §11 quick reference, category reference guide URLs)
- Uploading the redirect table to the hub
- Flagging the change in the hub index revision log and version sync table
- Checking and fixing hub Tier 2 model files (model PDPs, model guides)
- Adding the cross-category check to the next "Check the PDPs" run in each spoke

The spoke-level fixes happen naturally at the next spoke session or governance refresh. The register ensures nothing is forgotten.

---

## 5. WHY ASHRIDGE BLOCK

### Word count

Target: **35–50 words.** The Why Ashridge block is a trust signal, not a sales pitch. The customer is already on the product page. Awards, range link, done.

### Company naming

Rotate between "Ashridge Nurseries" (preferred), "Ashridge" (fine), and "Ashridge Trees" (occasional). Bias towards "Nurseries" or plain "Ashridge."

### Vary between PDPs

Core facts stay consistent; wording, emphasis, and detail must change. No two consecutive PDPs should have an identical Why Ashridge block.

| Element | Requirement |
|---------|-------------|
| **Heading** | Rotate between "Why Ashridge?", "Why buy from Ashridge?", and "Why Buy Your [Category] from Us?" (e.g. "Why Buy Your Dahlias from Us?"). Use "Ashridge Nurseries" in preference to "Ashridge Trees" where the heading allows. |
| **Opening sentence** | Must differ from the previous PDP''s opener — no verbatim repeats across the set |
| **Core facts selected** | Choose a different subset of the category''s core facts per PDP — do not stack all facts on every PDP |
| **Trust signal** | Rotate Which? Gardening Best Plant Supplier and Feefo Platinum Trusted Service Award — never stack both on one PDP |
| **Collection link** | Match to the variety''s type (e.g. ball dahlias → ball dahlia collection, not the general tubers collection) |

### Universal core facts (all categories)

These trust and values signals apply to every Ashridge product. One or two per PDP at most — select and rotate, don''t stack.

| Fact | Copy note |
|------|-----------|
| **Neonicotinoid-free** | Active commitment, not just regulatory compliance. Use where pollinators are relevant. |
| **Biological controls** | Biological pest controls in preference to chemical treatments. |
| **Peat-free nursery** | All growing media peat-free. State plainly; don''t oversell. |
| **Recycled pots** | Pots recycled or made from recycled materials where possible. |
| **Provenance** | "Grown for us by specialist growers" — not "UK nurseries." Can be category-specific: "specialist rose growers", "specialist clematis growers." Ashridge does not grow bare-root plants on its own nursery: say "grown for us" or "UK provenance", never "nursery-grown." |

### PBR varieties — Why Ashridge restriction

PBR-protected varieties: Ashridge does not propagate them — this is always assumed without needing confirmation. Use the PBR "Sold as" variant name and omit any propagation claims from the Why Ashridge block automatically. Do not say "grown for us", "UK-grown", or "raised from cuttings by us" for PBR varieties. The "propagated by the same people who answer your calls" line must NOT appear on PBR variety PDPs. Ashridge buys in PBR varieties as small plants under licence and grows them on. The PBR column in each category reference identifies affected varieties.

### Jumbo plugs — technical reference

Jumbo plugs have approximately twice the root volume of a standard seed plug. Stronger root system at despatch; less likely to bolt. Matters for cosmos and sweet peas. In copy, explain why it matters — the benefit (stronger roots, later and better flowering) is the point, not the cell dimensions.

### Perennials — Why Buy core facts

Perennial categories (salvia, foliage, herbaceous, and climbers where applicable) share a common set of Why Buy facts. Category reference files hold the genus-specific detail; this is the universal perennial baseline.

| Fact | Copy note |
|------|-----------|
| **Propagated in-house** | Ashridge propagates the vast majority of its perennials from cuttings taken from its own stock plants. Very few nurseries produce as wide a range themselves. PBR restriction applies — check the PBR column. |
| **Product form** | Standard: P9 (9cm pot). Larger sizes (e.g. 3-litre) may be available seasonally. Peat-free compost, recycled and recyclable pots. |
| **Team involvement** | All staff — propagation, packing, support — are involved in production. The people who answer your calls helped grow your plants. Key differentiator. |
| **Awards** | Which? Gardening Best Plant Supplier. Feefo Platinum Trusted Service Award. Both driven by customer recommendations. |
| **Plant guarantee** | All plants guaranteed. |
| **Dispatch** | Spring and summer. Reader-first perspective: "Your [plant] arrives..." not "Our [plants] are dispatched..." |

### Category-specific core facts

Category-specific Why Ashridge facts (propagation detail, dispatch windows, grading methods, variation points) live in each category reference file. Load the relevant category reference before writing.

---

## 6. CLAUDE TEST — AI DETECTION SELF-CHECK

### Purpose

The Claude Test ensures content does not look AI-generated. It applies to both PDPs and growing guides — the checks branch on content type where needed. As AI models evolve, the test must evolve too.

**Model references:** When assessing quality, compare against the category-appropriate model PDPs in the governance set: dahlias (Bishop of Llandaff, David Howard), sweet peas (Almost Black, America), lavender (Munstead), cosmos (Velouette), spring bulbs (Tête-à-Tête, Purple Sensation). For guide work, compare against the category-appropriate model guide: dahlias (`A_d_a_how-to-grow-dahlias.html`), cosmos (`A_c_a_how-to-grow-cosmos.html`), spring bulbs (`A_sb_a_how-to-grow-spring-bulbs.html`), sweet peas (`A_sp_a_how-to-grow-sweet-peas.html` and the pots guide). If no model exists for the category being written, use the closest match in style and scope.

### Workflow — run on EVERY session''s first PDP or guide

1. Draft the first PDP of the session.
2. Before delivering it, critically assess: **would a current AI identify this as AI-written?** Look for patterns, tics, rhythms, vocabulary or structural habits.
3. If a new tell is identified → add it as a new check, update this file, fix the draft.
4. Run all existing checks. Fix any failures.
5. Subsequent PDPs follow the updated checks.

### Current checks

| # | Check | Threshold | Priority |
|---|-------|-----------|----------|
| 1 | **Structural repetition** | Section order duplicated across >50% of set | HIGH |
| 2 | **Phrase reuse** | Any verbatim sentence on 2+ PDPs. **Exempt:** standardised FAQ templates. Why Buy blocks share core facts but must vary in wording — verbatim duplication across PDPs is not exempt. | HIGH |
| 3 | **Generic H2 openers** | "About [Variety]" or opening H2 missing the variety name. See also CHECK 15 for broader heading relevance rules — variety name required in opening H2, encouraged but not mandatory in others. | HIGH |
| 4 | **Em-dash density** | >0.8/100w = FAIL. >0.3/100w = FLAG. 0 = ideal. Target: zero em-dashes in body text. JdeB baseline from cosmos guides v2.2: 0.00/100w (both main guide and pots guide). Hyphens used as dashes (" - ") also flagged. | HIGH |
| 5 | **Paragraph length uniformity** | Informational only — report CV, do not fail on it. Natural rhythm takes priority. | LOW |
| 6 | **AI vocabulary** | **BANNED (auto-fail):** robust, testament, arguably, essentially, utilize/utilise, facilitate, leverage, optimal, comprehensive, delve, tapestry, plethora, myriad, furthermore, moreover, in addition, additionally, what''s more, needless to say, last but not least, in conclusion, it''s worth noting that, showcasing. **FLAG (note only):** genuinely, particularly, remarkably, straightforward. | MEDIUM |
| 7 | **"It is..." sentence openers** | >2 per PDP | LOW |
| 7a | **Exclamation marks** | Body copy: max 1 per PDP (0 is ideal). Never in the Why Ashridge block. FAQs: max 2 across the full category output — count across all sessions, not just the current batch. | LOW |
| 7b | **"There is/are" sentence openers** | Minimise — treat as a last resort, same principle as CHECK 7. Max 2 per PDP. Rewrite as an active construction wherever possible. | LOW |
| 8 | **Self-referential content** | Any reference to "the Ashridge page/website/existing description" — the PDP IS the page | HIGH |
| 9 | **Factual accuracy** | Category-specific. Container answer matches tiered policy. **Container FAQ permitted only on varieties listed in the category reference approved list** (see §2) — presence on a non-approved variety = FAIL. Heights/sizes match spec panel. AGM correct (three-tier wording). Companions match confirmed URLs. Collection links match variety type. | MEDIUM |
| 10 | **FAQ answer convergence** | Where same Q type appears on 3+ PDPs, no two share same opening sentence structure. **Exempt:** standardised FAQ templates. | MEDIUM |
| 11 | **Redundant internal links** | Same variety URL appearing 2+ times in body + companions + FAQs on a single PDP. **Exempt:** CaL sibling cross-refs; David Howard; collection links in Why Ashridge. | LOW |
| 12 | **Link concentration** | >40% of all links across full set pointing to <20% of range = FAIL. **Exempt:** David Howard (universal companion). | MEDIUM |
| 13 | **Tautology** | Any phrase where one word duplicates the meaning of its neighbour. See §3 table. | MEDIUM |
| 14 | **Structural AI tells** | Rhetorical Q→A across paragraphs; justifying what the reader can see; three-item "no" lists; three-item repetitive lists ("X does A. X does B. X does C." with identical sentence structure). See §3 table. | HIGH |
| 15 | **Heading keyword relevance** | Every H2 and H3 must make sense in isolation — a crawler or AI reading only the headings should understand what each section covers and for which plant/topic. Generic headings ("How to Plant", "Aftercare", "Getting Started") with no subject keyword = FAIL. **PDPs:** variety name required in the opening H2 (overlaps CHECK 3) and encouraged in one or two others, but NOT required in every H2 — repeating the variety name in every heading is spammy. Flexible middle H2s ("Pairing Ideas", "How the Colour Works") and standardised headings (Why Buy, FAQs) are exempt. **Guides:** core topic phrase required in every H2; H3s should include it where the bare word alone is ambiguous. FAQ H3s are exempt (naturally keyword-rich as questions). | HIGH |
| 16 | **Snippet-ready structure** | Every H2/H3 section must open with a direct answer to the question implied by the heading. **FAQ answers:** first sentence must be a complete, standalone response under 50 words (CHECK 16a). **Guide H2 sections:** first 1–2 sentences after the heading must deliver the core answer in 40–60 words before expanding with detail (CHECK 16b). **Lists:** must have a keyword-rich heading directly above them and use proper `<ul>`/`<ol>` markup, not bold text with line breaks (CHECK 16c). Sections that bury the answer after introductory waffle = FAIL. FAQ answers that open with "Yes." alone, throat-clearing, or "It depends" without immediately specifying = FAIL. | HIGH |
| 17 | **Keyword phrase density** | No exact 2+ word phrase in more than 60% of H2 headings (CHECK 17a). No exact 3+ word phrase more than 5×/1,000 words in body copy (CHECK 17b). No exact multi-word phrase in more than 50% of H2 section opening sentences (CHECK 17c). This check catches mechanical repetition of the identical string — not natural use of core topic vocabulary. Synonyms, partial matches, and natural rewording satisfy CHECK 15 without triggering CHECK 17. Counterbalances CHECKs 15 and 16. See §3. | MEDIUM |
| 18 | **Image & media quality** | Every `<img>` tag must have an `alt` attribute (empty `alt=""` for decorative images). Alt text must be descriptive, keyword-aware (not "chart" or "image1"), under 125 characters (hard limit 140), front-loaded with the key term, and not keyword-stuffed. Images below the fold must include `loading="lazy"`. Image filenames must be descriptive, hyphenated, lowercase, 3–7 words (CHECK 18b — applies to filenames recommended in placeholder comments). Informative images with captions should use `<figure>`/`<figcaption>` markup (CHECK 18c). Images to be added later must have a placeholder comment: `<!-- IMAGE: [recommended-filename.jpg] — alt="[draft alt text]" -->`. See §12. | MEDIUM |
| 19 | **Readability score** | Flesch-Kincaid grade level must fall between 6 and 9 (PASS). FK 9.1–10.5 = FLAG — review for long compound sentences. FK above 10.5 = FAIL — rewrite densest sections. Main driver is sentence length, not vocabulary. Horticultural terms are fine. See §3. | MEDIUM |
| 20 | **Paragraph length** | FLAG any `<p>` block over 5 sentences or 100 words. FLAG the page overall if more than 15% of paragraphs exceed 5 sentences. Lists, spec panels, and table cells are exempt. Not a strict ceiling — the check prompts review, not automatic splitting. See §3. | LOW |
| 21 | **Meta description quality** | Max 165 characters. Must contain the primary keyword. Must match page content. Must be unique across the set. Must include a reason to click. No keyword stuffing. Use `&` not "and". See §12. | LOW |
| 22 | **Image & media density** | Guides must include image placeholder comments at appropriate points: short guides (<2,000w) minimum 2, standard guides (2,000–4,000w) minimum 4, long guides (>4,000w) minimum 6. No H2 section in a standard or long guide should span more than 800 words without an image or image placeholder. PDPs: no minimum in our HTML (Shopify handles product images), but flag opportunities for diagrams or context shots where they''d add value. Video opportunity comments (`<!-- VIDEO: -->`) encouraged where a demonstration would materially help the reader. See §12. | LOW |
| 23 | **Passive voice density** | More than 2 passive constructions per 400 words of body copy = FLAG. Rate calculated as (passive count ÷ word count) × 400. Count only syntactic passives (verb phrases of the form "is/are/was/were/been + past participle" — e.g. "is grown", "was bred", "have been cut"). JdeB''s natural voice is active at all times; passive is a last resort. Spec panel, FAQ answers, and quoted external sources are exempt. | MEDIUM |
| 24 | **Link text quality** | Flag any `<a>` tag whose visible text is a generic phrase: "click here", "find out more", "learn more", "read more", "here", "our range", "this link", "more information". Link text must name what the reader finds: "our dahlia collection", "how to grow dahlias", "Bishop of Llandaff". | MEDIUM |
| 25 | **Opening word variety (batch)** | Extract the first word of body copy P1 (`<p>`) for each PDP. Flag if any single word appears as the opener for more than 2 PDPs in a batch of 5 or more. Report a first-word frequency table at batch end. **Batch-end reminder:** After delivering the final PDP of a batch, always include: "⚠️ OPENING WORD VARIETY — please check that the first word of body copy P1 varies across this batch. No word should dominate as an opener." | LOW |
| 26 | **Comma splice frequency** | More than 2 comma splices per 500 words of body copy = FLAG. A comma splice is two independent clauses joined only by a comma ("The tubers arrive in March, you can plant them immediately"). Intentional comma splices used for rhythm are a legitimate JdeB technique and should not be auto-corrected; the check exists to flag mechanical or accidental overuse, not to remove deliberate choices. | LOW |
| 27a | **Tidbits presence (per PDP)** | Every PDP should contain at least one factual claim about the variety''s history, breeding, cultural significance, or etymology that does not appear on other PDPs in the set. Absence = FLAG. Manual review — not automatable from HTML alone. | LOW |
| 27b | **Spec panel synonym-cluster repetition (batch)** | For defined synonym clusters in spec panel fields (scent, cutting quality, foliage colour), flag if any cluster term — or a near-synonym within the cluster — appears on more than 60% of PDPs in a batch of 5 or more. See audit skill §5 for defined clusters. Informational — same model as CHECK 5. | LOW |
| 28 | **"Don''t declare favourites"** | Flag any occurrence of "our favourite", "the best [X] in our range", "our best [X]", "the finest in the range", or "my favourite" in body copy. Priority: MEDIUM (EXPERT flag appropriate — "a personal favourite of JdeB''s" is permitted if JdeB approves). | MEDIUM |
| 29 | **Paragraph opener repetition (within PDP)** | Flag if any word appears as the opener of more than two body `<p>` blocks within a single PDP (excluding the spec panel). Report as "Opener word ''X'' used N× — paragraphs N, N, N." Informational only. | LOW |
| 30 | **Generic filler phrases** | AUTO-FAIL on any occurrence in body copy: "perfect for borders, pots and vases" (or close variant combining all three), "a welcome addition to any garden", "ideal for any border", "suits any style of garden", "a versatile choice for". These signal generic AI output. The list grows as new instances are identified. | MEDIUM |
| 31 | **Sentence construction repetition (within paragraph)** | Within any `<p>` block, flag if three or more sentences begin with the same first word or with the variety name. AI-generated copy often runs: "This variety... This makes it... This is why..." Report the paragraph. Informational — same model as CHECK 14. | LOW |
| 32 | **Personal anecdote presence (E1)** | Scan body copy for markers of personal content: relationship words, memory markers, named places. Flag if zero markers found. High false-negative rate — catches absence, not quality. See §3a E1. | MEDIUM |
| 33 | **Sentence length variation (E2)** | Flag if body copy contains no sentences of 7 words or fewer AND no grammatical fragments. See §3a E2. | LOW |
| 34 | **Colloquial voice (E3)** | Informational scan for informal markers: contractions beyond standard, rhetorical questions, colloquial phrases. Flags absence, not enforces presence. See §3a E3. | LOW |
| 35 | **Honest limitation (E4)** | Scan Why Ashridge block for limitation markers ("but", "sometimes", "difficult", "buy in", etc.). Flag if zero found. See §3a E4. | MEDIUM |
| 36 | **Hedge word density (E5)** | Count hedge words in body copy (excluding FAQs). FLAG >4/1,000w, FAIL >8/1,000w. See §3a E5. | MEDIUM |
| 37 | **Spec panel hook quality (E6)** | Flag spec panel variety lines that read as bare data strings with no selling hook. See §3a E6. | MEDIUM |
| 38 | **Why Ashridge plant-specificity (E7)** | Flag Why Ashridge blocks containing only generic nursery facts with no plant-specific production detail. See §3a E7. | MEDIUM |
| 39 | **Noun echo (E8)** | Flag nouns of 4+ letters repeated within a 15-word window where a pronoun would be natural. Variety and genus names exempt. FLAG if >2 echoes in body copy. See §3a E8. | LOW |
| 40 | **Visual/physical detail (E9)** | Informational scan for sensory and visual markers: colour adjectives beyond botanical, scale references, sensory verbs. See §3a E9. | LOW |
| 41 | **Editorial opinion presence (E11)** | Scan body copy for opinion markers: "in our experience", "we find", "the best way", comparative judgments, disagreement markers. Flag if zero found. See §3a E11. | MEDIUM |
| 42 | **Batch-level voice score (E1–E11 composite)** | Count how many of E1–E11 each PDP satisfies. Report batch average. HIGH if batch average <4/11, MEDIUM if <6/11. Flag any individual PDP scoring below 4. See §3a. | HIGH |

### Adding new checks

When a new tell is identified, add it with: clear description, measurable threshold, priority rating, date added. The banned vocabulary list should grow as new AI tics emerge.

---

## 7. DO NOT REPEAT (DNR)

Each category maintains a DNR list in its reference file. These are phrases that have already appeared across the set and must not be reused verbatim on future PDPs.

**Before writing any PDP:** check the current DNR list for the category. After each batch, update the DNR list with any new phrases that recurred.

The master DNR lists live in the category reference files:
- **Dahlias:** G1_a_ash-dahlia-category-reference.md
- **Sweet Peas:** G1_a_ash-sweet-pea-category-reference.md (§8)
- **Lavender:** G1_a_ash-lavender-category-reference.md
- **Cosmos:** G1_a_ash-cosmos-category-reference.md
- **Roses:** to be created
- **Trees/Hedging:** to be created

---

## 7a. TIDBITS BANK

Each category should maintain a numbered list of interesting, verifiable facts about the plant genus. These serve as anti-AI signals and distinctive content that competitors cannot replicate. They are compiled at spoke setup (see Setup Checklist, Phase 2) and tracked in the category reference file.

### Compilation

Research and document at least N interesting, verifiable facts about the genus, where N = half the number of varieties in the range (rounded up). This ensures each tidbit is used on at most two PDPs across the full set.

**Sources:** horticultural history, botany, ethnobotany, cultural significance, trade history, breeding breakthroughs, traditional uses, geographical spread.

### Tracking

The tidbits bank lives in the category reference file as a numbered table with columns for: tidbit text, PDP 1, PDP 2. Each tidbit may appear on a maximum of 2 PDPs. The tracking table must be updated after each production batch.

### Usage

- Place one tidbit per PDP, woven naturally into body copy or a relevant FAQ answer.
- Vary placement across the set (some in P1, some in P2, some in a FAQ).
- Each tidbit may appear on a maximum of 2 PDPs. Once both slots are used, the tidbit is retired for that category.
- Reserve at least 2–3 tidbits for varieties not yet written, especially if slugs are pending.

### Why this matters

Factual, specific, non-generic content is the single strongest signal that a PDP was not produced by unguided AI. Competitors using AI at scale cannot replicate verified horticultural history or ethnobotanical facts without the same research investment.

---

## 7b. STAGING DATA AND COMPETITOR REFERENCES

### The rule

When producing PDPs or advice pages from Cosmo''s `knowledge_staging` data, items that contain competitor names in acceptable context (naming origin stories, variety facts with a competitor class qualifier, introduction dates with attribution) must be processed as follows:

**Competitor names are never reproduced in output.** They are pointers — a signal that there is substance worth adding — not content in their own right.

**Competitor names covered by this rule** (apply identically to all):

| Competitor | Also watch for |
|---|---|
| David Austin Roses | "David Austin", "English Roses" used as a brand label |
| Peter Beales Roses | "Peter Beales" |
| Thorncroft Clematis | "Thorncroft" |
| Downderry Nursery | "Downderry" |
| Sarah Raven | "Perch Hill" (her garden/brand location, equivalent to "David Austin''s Shropshire") |
| Hopes Grove Nurseries | "Hopes Grove" |

**First-person voice in Sarah Raven content.** Her articles are written in first person ("I find...", "we grow...", "at Perch Hill we always..."). The extraction pipeline converts these to objective claims before facts reach `knowledge_staging`. Any staging item that still contains "I", "we", or "at Perch Hill" carries a competitor reference and must be processed through this rule — strip the framing, keep the plant fact.

### The Abraham Darby rule

When a staging item reads "[Variety] was named after [X], reflecting [Competitor]''s tradition of..." — strip the competitor clause entirely and research what X actually was. Report the substance, not the attribution.

| Raw staging item | Correct output |
|---|---|
| "Abraham Darby was named after one of the founding figures of the Industrial Revolution, reflecting David Austin''s practice of honoring historical British figures" | "Abraham Darby was named after the ironmaster who pioneered smelting iron with coke at Coalbrookdale in 1709, helping launch the Industrial Revolution" |
| "With 130 petals per bloom, St. Swithun ranks among the most petal-dense of David Austin''s climbing roses" | "With 130 petals per bloom, St. Swithun is one of the most densely flowered climbing roses you can grow" |
| "Introduced in 2000 by David Austin, James Galway combines old rose charm with modern repeat flowering" | "Introduced in 2000, James Galway combines old rose charm with modern repeat flowering" |
| "one of the most distinctive scented roses in the David Austin collection" | "one of the most distinctively scented climbing roses available" |

### Pattern

Every staging item with a competitor name contains two elements:

1. **The pointer** — the competitor name and its framing ("reflecting X''s tradition of", "in the X collection", "introduced by X")
2. **The substance** — the actual plant fact (naming origin, petal count, introduction date, fragrance profile)

Strip the pointer. Keep and enrich the substance.

### The naming origin enrichment requirement

Naming origin stories in staging data are often thin — they identify the historical figure or place but don''t explain why the name is interesting. At PDP writing time, research the actual person or place and add the substance:

- Who was this person and why do they matter?
- What did they do, build, discover, or represent?
- What is the connection to the plant?

A naming origin story that teaches the reader something memorable is far stronger than one that merely names the source. It also functions as a tidbit — content that competitors cannot replicate without the same research investment.

### Status in the database

These items are in `knowledge_staging` with `status = ''pending''`. They are not bulk auto-approved because they contain competitor names. They are processed through this rule at PDP and advice page writing time.

---

## 8. CATEGORY REFERENCE FILES

One per category. Each contains: variety table, confirmed URLs, companion matrix, FAQ pool with tracking, AGM cross-references, spec panel template, model PDPs, and Do Not Repeat list.

| Category | File | Status |
|----------|------|--------|
| Dahlias | G1_a_ash-dahlia-category-reference.md | ✓ Complete (v3.1, 45 varieties, slug mapping, tidbits bank) |
| Sweet Peas | G1_a_ash-sweet-pea-category-reference.md | ✓ Complete (v1.11, 38 varieties, 2 model PDPs, FAQ pool, DNR) |
| Lavender | G1_a_ash-lavender-category-reference.md | ✓ Complete (v1.3, 102 editorial rules, 9 published PDPs audited) |
| Cosmos | G1_a_ash-cosmos-category-reference.md | ✓ Complete (v1.1, 19 varieties, Velouette model PDP) |
| Climbers | G1_a_ash-climbers-category-reference.md | ✓ Complete (v1.1, 127 products, 15+ genera, PBR audit applied) |
| Salvia | G1_a_ash-salvia-category-reference.md | Phase 1 — to be created (14 products) |
| Foliage & Shade | G1_a_ash-foliage-category-reference.md | Phase 1 — to be created (22 products) |
| Herbaceous | G1_a_ash-herbaceous-category-reference.md | Phase 1 — to be created (29 products) |
| Roses | G1_a_ash-rose-category-reference.md | Not yet created |
| Trees/Hedging | G1_a_ash-tree-category-reference.md | Not yet created |
| Fruit Trees | — | Not yet created |

---

## 9. BEFORE YOU START A NEW CATEGORY

The full procedure for setting up a new category spoke project is defined in the **Category Project Setup Checklist** (current version: v1.20). That document is the authoritative reference — follow it in full for any new category.

The checklist is organised into three phases:

**Phase 1 — Project Setup (Steps 1–3):** Create the Claude project, upload governance files, set up the system prompt.

**Phase 2 — Research (Steps 4–17):** All research is run by Claude before any content is written. Steps include: Ahrefs slug verification (Step 4), per-product slug audit (Step 4a), Ahrefs growing guide topic research (Step 5), RHS AGM reference check against `R_a_rhs-agm-ornamental-compact.md` with date verification (Step 6), variety reference PDF search or book recommendation (Step 7), cultural care and pest/disease PDF search or book recommendation (Step 8), specialist book research — 2–3 British-garden focus titles (Step 9), award winners and new introductions check covering AGM, Plant of Year, RHS visitor awards and trial results (Step 10), companion plants research (Step 11), specialist societies and classification systems (Step 12), Why Ashridge spoke-specific reasons — JdeB input required (Step 13), category terminology glossary draft (Step 14), tidbits bank (Step 15), UK representative bodies (Step 16), category-specific awards with 20-year minimum history (Step 17).

**Phase 3 — Content Setup (Steps 18–24):** Build the category reference file, content gap analysis, growing guides, model PDPs, tracking spreadsheet, verify setup, update hub index.

**Summary principle:** No PDP or guide writing begins until Phase 2 research is complete. The research phase exists to ensure all content is grounded in accurate variety data, current AGM status, correct terminology, and SEO-validated structure before a single word is written.

---

## 10. DURING A BATCH SESSION

### Per-PDP workflow

1. Pick the next variety from the category reference file.
2. Check confirmed URL, spec panel data, type, AGM, and any notes.
3. Select FAQs from the pool. Check the tracking grid — don''t duplicate another PDP''s set.
4. Choose 3–6 companion varieties from the matrix. Check their URLs are confirmed. Verify slugs.
5. Write the PDP following the Varn model (§1). Spec panel first.
5a. Consider a cross-category reference in the body copy — one informal mention of a related plant in a different category adds depth and a natural link opportunity. Not mandatory; use judgement.
5b. On any care instruction that echoes standard conventional advice — ask: does Ashridge actually follow this? Would JdeB disagree or qualify it? If uncertain, add: `<!-- EXPERT: Do you follow the usual advice here, or is your practice different? -->`. "We don''t bother" is more credible than uniform enthusiasm.
6. Vary the Why Ashridge block (§5) from the previous PDP — core facts stay consistent, wording must change.
7. Run the Claude Test (§6) — at minimum on the session''s first PDP, ideally on all.
8. Check against the DNR list (§7).
9. Scan for tautology (§3).
10. Deliver as a single HTML file.

### After the batch

1. Update the FAQ tracking grid in the category reference file.
2. Add any new recurring phrases to the DNR list.
3. Update the master spreadsheet.
4. Run the audit template across the batch if ≥5 PDPs were produced.

---

## 10a. "CHECK THE PDPs" — FILE INSPECTION TRIGGER

### The problem this solves

Governance documents record what was known when they were last updated. The HTML files themselves are the source of truth. When asked whether PDPs need updating, the default response must be to **open and inspect every PDP file**, not to search governance docs for previously logged issues. Reading the paperwork is not the same as inspecting the product.

### Procedure

**The full procedure is defined in the Trigger Phrases file, Trigger 6.** That is the canonical definition — follow it, not this section. What follows here is the hygiene scan specification (what gets checked and at what severity), which Trigger 6 references.

### Hygiene scan checks

The hygiene scan covers issues that fall outside the Claude Test and content quality checks. It runs as part of "Check the PDPs" but not as part of "run the PDP audit" (which triggers the audit skill only).

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **Stale URL slugs (within category)** | Any `href` value whose slug suffix does not match the canonical slug suffix recorded in the category reference file. Compare every internal `/products/` and `/collections/` link against the reference. | HIGH |
| **Stale URL slugs (cross-category)** | Any `href` linking to a product or guide in another category where the URL change register (§4b) records a redirect. Check all `/products/`, `/collections/`, and `/blogs/` links against the register documents in the hub. This catches links to dahlia products using old type-specifier slugs, links to guides using old guide slugs, etc. | HIGH |
| **Missing link attributes** | Any internal `<a>` tag missing `rel="noopener noreferrer"` or `target="_blank"`, or with those attributes in the wrong order (must be `rel` before `target`). | MEDIUM |
| **Residual EXPERT comments** | Any `<!-- EXPERT:` or `<!-- TODO:` comment still present in a file that is not flagged as `-commented` in its filename. | MEDIUM |
| **Old filenames in HTML** | Any reference inside the HTML to a governance filename, image filename, or other file path that uses a deprecated naming convention (e.g. `ashridge-` prefix, old `T1_ash-`/`T2_ash-`/`S1_` prefixes, or an old slug pattern). Current convention uses `G1_`/`G2_`/`A_`/`R_`/`X_`/`P_` prefixes — see §12. | LOW |

---

### Category-specific rules — lookup

All category-specific rules (word counts, FAQ limits, container thresholds, guide URLs, collection URLs, DNR lists, Why Ashridge variants, companion matrices) live in the category reference file for that category. Do not duplicate them here. Load the relevant category reference alongside this file before writing.

| Category | Reference file |
|----------|---------------|
| Dahlias | `G1_a_ash-dahlia-category-reference.md` |
| Sweet Peas | `G1_a_ash-sweet-pea-category-reference.md` |
| Lavender | `G1_a_ash-lavender-category-reference.md` |
| Cosmos | `G1_a_ash-cosmos-category-reference.md` |
| Climbers | `G1_a_ash-climbers-category-reference.md` |
| Salvia | Category reference file — to be created |
| Foliage & Shade | Category reference file — to be created |
| Herbaceous | Category reference file — to be created |
| Roses | Category reference file — to be created |
| Trees / Hedging | Category reference file — to be created |

---

## 12. HTML OUTPUT FORMAT

When producing PDP or guide HTML files:

- **Clean, readable HTML** with normal spaces and line breaks between block elements.
- **Do NOT use `&nbsp;`** between words — Shopify handles normal spaces fine.
- **Do NOT try to emulate Shopify''s internal CMS format** (single-line `&nbsp;` soup).
- Each `<ul>`, `<li>`, `<h2>`, `<h3>`, `<p>` and their closing tags on separate lines.
- **Relative URLs throughout.** No absolute `https://www.ashridgetrees.co.uk/...` links.
- All links: `rel="noopener noreferrer" target="_blank"` — `rel` before `target`.
- No wrapper `<div>`, no `<head>`, no `<!DOCTYPE>`. Just the content HTML that goes into Shopify''s rich text editor.

**Self-notes must never appear as body text.** Internal production notes, reminders, and process annotations (e.g. "remember to check this", "add link later", "this section needs expanding") must be HTML comments (`<!-- ... -->`) or omitted entirely. They must never render as reader-facing `<p>` or `<li>` content. The EXPERT comment protocol (§3) covers flagged queries; this rule covers everything else. (CHECK 44)

### Images, media & visual content

Search engines, AI overviews, and screen readers all depend on well-structured image metadata. Vision-language models (CLIP, Gemini Vision, etc.) now parse alt text, captions, and surrounding context together — so the same practices that help accessibility also improve AI citability and image search rankings. These rules apply to images embedded directly in our HTML content (guide diagrams, charts, comparison images, product photos embedded in guides). Most PDP product images are handled by Shopify''s product media system and are outside our control.

#### Informative vs decorative images

Not all images carry meaning. The rule depends on the image''s purpose:

- **Informative images** (photos, charts, diagrams, comparison images) — must have descriptive alt text. This is the majority of what we use.
- **Decorative images** (ornamental dividers, spacer graphics, background textures) — must have an **empty** alt attribute: `alt=""`. This tells screen readers to skip them. Do not write "decorative image" or "spacer" as alt text.
- **Image links** (an image that acts as a hyperlink) — the alt text should describe the **link destination**, not the image itself. `alt="Purple Sensation Allium — buy from Ashridge Trees"` not `alt="photo of a purple allium flower"`.

#### Image alt text (CHECK 18a)

- **Every `<img>` must have an `alt` attribute.** No exceptions — even decorative images need `alt=""`.
- **Alt text must be descriptive and keyword-aware** — it should tell a screen reader (or a search engine) what the image shows and for which plant or topic. "Tête-à-Tête daffodils flowering in a terracotta pot in early March" is good. "daffodils" is thin. "chart" or "image1" is useless.
- **Don''t keyword-stuff the alt text.** One or two relevant keywords naturally included is fine. Cramming every keyword on the page into the alt text is spam.
- **Keep it under 125 characters** where possible — most screen readers truncate beyond this. Hard limit: 140 characters.
- **Front-load the keyword.** Place the most important descriptive term near the start: "Snowdrops naturalised under a beech hedge" not "A close-up garden photograph showing snowdrops naturalised under a beech hedge in February".
- **Include `loading="lazy"`** on all images except the first visible one above the fold.

#### Image filenames (CHECK 18b)

Google explicitly states that filenames provide contextual clues about image content. Descriptive filenames also make media library management practical.

- **Descriptive, hyphenated, lowercase.** `tete-a-tete-daffodils-terracotta-pot.jpg` not `IMG_4523.jpg`.
- **3–7 words.** Enough to describe the subject; short enough to stay readable in a URL.
- **Hyphens, not underscores.** Google treats hyphens as word separators; underscores join words.
- **No special characters** — letters, numbers, and hyphens only.
- **Include the variety or topic name** where it naturally fits: `purple-sensation-allium-flower-head.jpg`, `bulb-lasagne-planting-diagram.jpg`.
- **Match the file extension to the actual format.** `.jpg` for JPEG, `.png` for PNG, `.webp` for WebP.
- **Don''t rename already-indexed images** unless critical — Google crawls images slowly and dropping old filenames can cause months of disruption.
- **Filename and alt text should complement each other, not duplicate.** The filename is concise; the alt text is more descriptive and contextual.

**Note for Claude drafts:** When writing HTML that references images to be added later, include the recommended filename in the placeholder comment: `<!-- IMAGE: tete-a-tete-daffodils-terracotta-pot.jpg — alt="Tête-à-Tête daffodils flowering in a terracotta pot in early March" -->`. This gives JdeB both the filename convention and the alt text in one place.

#### Image captions (CHECK 18c)

Research consistently shows captions are read significantly more than body text. Where an image tells a story or conveys information that benefits from explanation, add a caption using `<figure>` and `<figcaption>`:

```html
<figure>
  <img src="bulb-lasagne-cross-section.jpg"
       alt="Cross-section diagram showing three layers of spring bulbs planted at different depths in a single pot"
       loading="lazy">
  <figcaption>A bulb lasagne in cross-section: tulips deepest, daffodils in the middle, crocus on top.</figcaption>
</figure>
```

- **Use captions where the image needs context** that the alt text alone can''t provide — explaining what a diagram shows, identifying a garden location, crediting a technique.
- **Don''t caption every image.** A product hero shot usually doesn''t need one. A comparison chart or planting diagram does.
- **Captions and alt text serve different audiences.** Alt text is for screen readers and search engines (hidden); captions are for sighted readers (visible). They can overlap but shouldn''t be identical.
- **Keep captions to one or two sentences.** They should add value, not duplicate the surrounding paragraph.

#### Image placement and context

Google uses surrounding text to understand what an image depicts. Placing images near relevant content strengthens the signal for both search engines and AI parsers.

- **Place images adjacent to the text they illustrate.** A planting depth diagram should sit within or immediately after the planting depth section, not at the bottom of the page.
- **Don''t cluster all images at the top or bottom** of a guide. Distribute them through the content where they add the most value.
- **For guides:** aim for at least one relevant image per major H2 section. This improves engagement, breaks up long text, and gives search engines multiple image-context pairings across the page.

#### Image density per content type (CHECK 22)

Pages with no images or inadequate imagery underperform in both search rankings and user engagement compared to pages with relevant visual content. These minimums apply to the HTML content we write — they do not count Shopify product gallery images (which JdeB manages separately).

| Content type | Minimum images | Ideal | Notes |
|-------------|---------------|-------|-------|
| **PDP** | 0 in our HTML (Shopify handles product photos) | 1–2 if a diagram, comparison, or garden context shot adds value | Don''t force images into PDPs where Shopify''s gallery already covers the visual need |
| **Guide (short, <2,000w)** | 2 | 3–5 | At least one near the top, one illustrating the core technique |
| **Guide (standard, 2,000–4,000w)** | 4 | 6–10 | Roughly one per major H2 section |
| **Guide (long, >4,000w)** | 6 | 8–12 | No H2 section should go more than 800 words without a visual |
| **Flowering chart / comparison** | 1 (the chart itself) | 1 per month or category | Charts ARE the visual content |

**Note for Claude drafts:** Claude cannot source or create photographs. When writing guides, include `<!-- IMAGE: [description] — [recommended-filename.jpg] — alt="[draft alt text]" -->` placeholder comments at appropriate points. JdeB adds the actual images before publication. The placeholder should specify: what the image should show, the recommended filename, and draft alt text. This is the minimum — JdeB may add more images beyond the placeholders.

#### ImageKit CDN delivery

Image assets are managed in ImageKit (ID: `ashridge`). The full tagging regime, controlled vocabularies, folder structure, CDN URL construction rules, advice page embedding pattern, and category-specific extensions are defined in the **ImageKit Tagging & Embedding Rules** (`GOV-imagekit-tagging-v1_0.md`) — a separate Tier 1 governance file. That file is the single source of truth for image tagging, selection, and embedding; this section covers only how images appear in HTML content. During migration, ImageKit''s Web Folder origin transparently proxies images that still live at Cloudinary (`daokm3yuy`); URLs resolve through ImageKit either way.

When Claude has access to the ImageKit MCP connector, it can search the DAM by tag, folder, or filename to find suitable images for advice pages and guides. The "Update ImageKit" trigger phrase (Trigger 9 in the trigger phrases file, current version `GOV-trigger-phrases-v1_13.md`) governs the tagging workflow. For editorial images embedded in advice page HTML, serve directly from the ImageKit CDN using the thumbnail + click-through pattern defined in §12 of the tagging & embedding rules.

#### Video placeholders

Claude does not create video content, but planting demonstrations, seasonal walkthroughs, and variety comparisons are high-value visual content for both users and search engines. When writing guides or PDPs where a video would materially improve the reader''s understanding:

- **Flag the opportunity** with a comment: `<!-- VIDEO: [what the video should show] — e.g. "How to plant a bulb lasagne — 2-minute demonstration of layering technique" -->`.
- **Suggest a thumbnail alt text** in the comment so JdeB has it ready when the video is added.
- If a video already exists on the Ashridge YouTube channel or website, link to it with appropriate context rather than repeating its content in text.

Video is a site-level investment decision, not a content drafting requirement. These placeholders flag opportunities — they don''t create obligations.

### Filename convention

#### Two filename states

Every PDP exists in one of two states. The state determines the filename format.

**Draft state** — used during generation, iteration, and editing. Carries a version suffix so it is always possible to identify which revision a file is.

- Format: `[url-slug]-v[MAJOR]_[MINOR].html`
- Example: `anniversary-sweet-pea-plants-v1_1.html`
- Bump minor version on editorial fixes (`-v1_1`), major version on structural rewrites (`-v2_0`).

**Publish state** — used when uploading to Shopify. Filename must exactly match the product URL slug so that the filename on the server corresponds to the live URL. No version suffix, no other markers.

- Format: `[url-slug].html`
- Example: `anniversary-sweet-pea-plants.html`

The URL slug itself is defined per category — see the canonical slug suffix line in each category reference file.

#### Publish-ready delivery question (MANDATORY)

**Every time Claude delivers one or more content files (PDPs, guides, collection pages) for download — regardless of how the request is phrased — Claude must determine the delivery state before generating filenames.**

The **Trigger Phrases file** (`G1_a_ash-trigger-phrases.md`) defines the canonical triggers and their full procedures. See Trigger 1 ("For Shopify") for the primary publish-ready trigger, including the complete list of variant phrases that activate publish-ready delivery. When any recognised trigger is used, apply publish-ready state without asking and follow the full sequence defined in that file.

If the user''s intent is ambiguous and does not match a recognised trigger phrase, ask:

> *"Do you want these as publish-ready files (filename matches URL slug, no version suffix) or as working files (version suffix retained)?"*

Apply the answer as follows:

| | Publish-ready | Working files |
|---|---|---|
| Version suffix | Strip | Retain |
| `-commented` flag | Strip (with warning — see below) | Retain |
| `-edited` marker | Strip | Strip |
| T1_/T2_ prefix | Strip | Retain (governance files only) |

The `-edited` marker is always stripped because it is an instruction to Claude (diff/review request), not a meaningful state for the file itself.

#### Filename verification (MANDATORY)

**Before presenting any files for download, Claude must verify every filename against the requested delivery state:**

| Check | Publish-ready | Working |
|-------|--------------|---------|
| Version suffix present? | FAIL — strip it | OK |
| T1_/T2_ prefix present? | FAIL — strip it | OK (governance files only) |
| Filename matches URL slug? | Required | Not required |

If any filename fails verification, correct it before presenting. Do not present files and then offer to rename — get it right first time.

#### EXPERT comment suffix and publish-ready warning

- **Files with EXPERT comments:** If the delivered HTML contains any `<!-- EXPERT: -->` comments requiring JdeB action, append `-commented` before the version suffix in draft state (e.g. `anniversary-sweet-pea-plants-commented-v1_1.html`). This alerts JdeB to search for and resolve the comments before publication.
- **Files without EXPERT comments:** Use the plain filename with version suffix only.
- When JdeB returns an edited file with all EXPERT comments resolved, the next revision drops the `-commented` flag and bumps the version.
- **Publish-ready warning:** If a file still carries `-commented` when a publish-ready delivery is requested, strip the flag from the filename but issue this warning: *"Note: [filename] still has unresolved EXPERT comments — please review before uploading to Shopify."*

#### Non-PDP file versioning

Every file Claude generates must carry a version suffix. This applies to guides, governance files, audit reports, instruction notes, and any other deliverable. The only exceptions are temporary working files that are never delivered.

- **Guides:** `[slug]-v1_0.html` for first complete draft. Same draft/publish-state logic applies.
- **Governance `.md` files:** Version in the file header only — not in the filename. See §12 prefix convention below.
- **Audit reports and instruction notes:** `[descriptive-name]-v1_0.md` or `.txt`.
- **Governance zips:** `G1_ash-governance-core-v[RULES_VERSION]-[YYYY-MM-DD].zip` and `G2_ash-governance-models-v[RULES_VERSION]-[YYYY-MM-DD].zip`.

**Why this matters:** Without version numbers, it is impossible to tell whether a file in a project''s knowledge base is current or stale. When JdeB downloads files from multiple sessions and uploads them to a new project, version numbers are the only reliable way to identify the latest copy of each file.

#### File prefix convention (G1/G2/A/R/X/P/D)

Claude Projects truncate filenames in the file listing sidebar. When multiple versions of the same file exist, it is impossible to tell which is current without opening each one. The prefix convention solves this in two ways: (1) a **type prefix** groups files by function, and (2) a **descriptor letter** (`a`, `b`, `c`…) increments on each replacement, making old and new files visually distinguishable even when truncated.

**The pattern:** `[PREFIX]_[descriptor]_[meaningful-name].[ext]`

The full semantic version (v8.34, v3.14, etc.) lives inside the file header, not in the filename.

| Prefix | Meaning | Lives in | Example |
|--------|---------|----------|---------|
| `G1_` | Tier 1 governance | Hub + all spokes | `G1_a_ash-pdp-master-rules.md` |
| `G2_` | Tier 2 model content (PDPs, collection pages, guides used as structural/tonal models) | Hub + all spokes | `G2_a_ash-america-sweet-pea-plants.html` |
| `A_` | Advice pages (growing guides). Add category marker between prefix and descriptor: `d` = dahlias, `sp` = sweet peas, `c` = cosmos, `l` = lavender, `sb` = spring bulbs, `cl` = climbers. | Hub + relevant spokes | `A_d_a_how-to-grow-dahlias.html` |
| `R_` | Research & reference | Hub (or spoke if category-specific) | `R_a_dahlia-variety-research.md` |
| `X_` | Operational / working docs (hub-only tools, trackers, instruction notes) | Hub only | `X_a_ash-hub-prebuild-sweep.md` |
| `P_` | Production PDPs (live product pages in progress) | Spoke only | `P_cl_a_niobe-clematis-plants.html` |
| `D_` | Distributed reference files (large, infrequently changing reference data distributed separately from governance zips) | Hub + all spokes via D_ zip | `D_a_rhs-agm-ornamental-compact.md` |

**Descriptor workflow:** Every file starts at `a`. When replacing, Claude checks the existing filename, increments the descriptor (`a` → `b` → `c`…), and presents an old/new table so JdeB can see what to delete after uploading.

**Stale file cleanup:** Because each prefix groups a file class, bulk deletion is straightforward. Replacing all Tier 1 governance? Delete everything starting with `G1_`. Replacing Tier 2 models? Delete `G2_`. Replacing advice pages for one category? Delete `A_d_` (dahlias), `A_sp_` (sweet peas), etc.

**Spoke file templates:** When creating new spoke files, use the appropriate prefix. Category references: `G1_a_ash-[category]-category-reference.md`. Research outputs: `R_a_[category]-setup-research.md`. Content gap analyses: `R_a_[category]-content-gap-analysis.md`.

**Important:** The prefix convention is a file-management convention for Claude Projects only. It has no effect on URL slugs, Shopify filenames, or publish-ready PDP filenames. The publish-ready delivery workflow (see above) strips the prefix along with the version suffix.

**Full reference:** The file naming convention crib sheet (`X_a_ash-file-naming-convention.md`) provides a quick-reference version of this section. Trigger phrase: "Filenaming?" or "File naming?"

### Deliverables per content type

When delivering a final or post-edit version, include the following files:

| Content type | HTML file | Meta snippet (.txt) | Homepage summary (.html) |
|-------------|-----------|--------------------|-----------------------|
| **Blog post / guide** | ✓ | ✓ | ✓ |
| **PDP** | ✓ | ✓ | — |

**Meta snippet** — a plain text file containing only the meta description (max 165 characters, ready to copy and paste). Use `&` instead of "and" to save space. No title line. Filename: `[slug]-meta.txt`.

### Meta description quality (CHECK 21)

Google rewrites 60–70% of meta descriptions that don''t match the page content or search intent. Writing them well reduces rewrite rates — and even when Google does rewrite, a strong original description acts as a quality signal.

**Rules:**
- **Max 165 characters.** Hard limit. Includes spaces.
- **Must contain the primary keyword** for the page. For a PDP, that''s the variety name. For a guide, it''s the core topic phrase (e.g. "spring bulbs", "bulbs in pots").
- **Must match the page content.** If the meta description promises "complete planting guide" but the page is a PDP, Google will rewrite it. Describe what the page actually delivers.
- **Must be unique across the set.** No two PDPs or guides should share the same or near-identical meta description. Duplicate meta descriptions confuse search engines and dilute click-through rates.
- **Use `&` not "and"** to save characters.
- **Include a reason to click.** Not a generic CTA ("Learn more!") but a specific value: "Planting advice, flowering times & companion ideas" or "Bare-root bulbs, delivered September–November."
- **Don''t keyword-stuff.** One primary keyword, one or two supporting terms. A meta description crammed with every synonym for "daffodil" will be rewritten immediately.

**Homepage summary** — an HTML file of fewer than 80 words, intended to appear on the homepage to encourage visitors to read the full advice article. Should include a linked `<h3>` heading and a single `<p>` summarising the guide''s scope and value. Filename: `[slug]-summary.html`.

---

## 13. BLOG POST / GROWING GUIDE RULES

Growing guides are advice-oriented blog posts that sit at `/blogs/[category-slug]/[guide-slug]`. PDPs link to them; they should not duplicate each other.

### Model guide

**`A_sb_a_how-to-grow-spring-bulbs.html`** is the original structural and tonal reference for growing guides — the guide equivalent of the model PDPs. Additional model guides now exist for dahlias, cosmos, and sweet peas (see the Tier 2 table in the hub index). Before writing a new guide, read the most relevant model for: section flow, heading style, direct-answer openings, link placement, paragraph rhythm, and the balance between teaching and selling. The same structural principles are used as the audit baseline for CHECKs 15–21.

### Structure

Guides follow a consistent pattern established by the lavender and cosmos guides:

1. **Introduction** — 2–3 paragraphs, conversational, answering "why grow this plant" and "what does the reader need to know before starting"
2. **Core sections** — each with an `<h2>` and anchor ID (so PDPs can deep-link). Cover: soil/site, planting, watering, feeding, pruning/deadheading, pests & diseases, propagation, harvesting/cutting
3. **Month-by-month calendar** — `<strong>Month:</strong>` + `<br>` + task description. One entry per month where there''s something to do
4. **Companion planting** — brief section linking to relevant Ashridge products
5. **Variety recommendations** — brief pointers to standout varieties in the range, with product links

### Principles

- **Authoritative but warm.** Same voice as PDPs but longer-form. The guide is the expert resource; PDPs are the sales page.
- **PDPs link to guides, not the other way round.** A guide may mention varieties but its job is teaching, not selling.
- **No duplication with PDPs.** If the guide covers pinching-out technique in detail, the PDP shouldn''t repeat it — just link. The guide covers the "how"; the PDP covers the "why buy this one".
- **Anchor IDs on key `<h2>` sections** so PDPs can link directly to relevant parts (e.g. `/blogs/bedding/how-to-grow-cosmos#staking`).
- **Heading keyword relevance (CHECK 15).** Every H2 and H3 in a guide must contain the core topic phrase or a specific plant name — not generic labels like "How to Plant" or "Aftercare". Search engines, featured snippets, and AI overviews scan headings in isolation. See §1 for full rules.
- **Snippet-ready structure (CHECK 16).** Guides are the primary featured snippet opportunity. Every H2 section should open with a direct answer to the implied question in the heading — 40–60 words that could be extracted as a standalone snippet. Lists must have keyword-rich headings directly above them and use proper `<ul>`/`<ol>` markup. FAQ answers must open with a standalone response under 50 words. See §1 "Structuring content for featured snippets and AI overviews" for the full rules and the four snippet formats.
- **FAQs in guides should not duplicate the guide''s own content.** If a FAQ question is answered in the body of the same guide, the FAQ answer should be brief and point back — but still name the section or the key fact: "Yes — see the planting depth section above for the exact measurements." Do not simply say "yes, see above" with no pointer, and do not rewrite instructions that appear earlier on the same page.
- **Image placeholders (CHECK 22).** Every guide should include `<!-- IMAGE: -->` placeholder comments at appropriate points for JdeB to add photographs. Aim for roughly one per major H2 section. Include recommended filenames and draft alt text in each placeholder. See §12 for full image density requirements, filename conventions, and caption guidance.
- **Preserve existing CDN images.** When rewriting pages that already have live images hosted on Shopify''s CDN (`https://cdn.shopify.com/...`), preserve those `<img>` tags in approximately the same positions. Use `<!-- IMAGE: -->` placeholder comments only for genuinely new images that don''t yet exist on the CDN.
- **Reuse existing YouTube embeds.** Existing advice pages may have Ashridge-produced YouTube videos embedded. Reuse these in rewrites at appropriate positions, matching the `<figure><div><iframe>` format used on the existing pages. Don''t duplicate a video that belongs on a different guide — each video should live on its most relevant page.
- **Same HTML format rules** as PDPs (§12).

### Word count

Guides are substantially longer than PDPs. The lavender guide runs ~4,500 words; the cosmos guide ~3,650 words. Target 3,000–5,000 words depending on the complexity of the plant.

### One guide per category (usually)

Most categories need one comprehensive guide. Exceptions:
- **Lavender** has a growing guide + a separate pruning guide (both exist)
- **Dahlias** have a growing guide + a pots guide + an overwinter guide (all exist)
- **Trees / Hedging** will likely need separate guides per major species group

### Advice page cross-linking

Every advice page or growing guide must include three cross-linking elements:

**1. Scope-and-signposting paragraph** (near the top, after the introduction): One paragraph linking to 2–3 sibling guides. Tells the reader what this guide covers and where to go for related topics. This is both a navigation aid and an internal link signal.

**2. Contextual cross-links in body copy** (3–5 per guide): Natural in-text links where the guide mentions a topic covered in more depth elsewhere. These should feel like helpful asides, not a link farm.

**3. Related Guides panel** (at the bottom, as a body `<div>`, not a sidebar): A short list of related guides. This is content, not navigation — it lives inside the article body HTML, not in a theme sidebar widget.

### Related Guides ordering rule

Aspirational and choice guides come first. Disease and problem guides always come last — never in positions 1–3. The customer''s last impression should not be anxiety about what can go wrong.

| Position | Type | Example |
|----------|------|---------|
| 1–3 | Aspirational / choice | "Which clematis should I grow?", "Growing clematis in pots" |
| 4–5 | Practical / seasonal | "When to plant spring bulbs", "Pruning climbing roses" |
| Last | Problem / disease | "Clematis wilt: causes and prevention" |

---

## DOCUMENT DEPENDENCIES

| File | Purpose | Required before writing? |
|------|---------|------------------------|
| **This file (Master Rules v8.50)** | Universal rules — the single source of truth | Yes — every session |
| **Category reference file** | Variety data, URLs, companions, FAQ pool, DNR, spec panel, model PDPs | Yes — every session |
| **Verified collection URL list** | Cross-category companion linking — confirmed `/collections/` slugs | Yes — every session |
| **PDP audit skill** | Post-batch quality check methodology and scripts | After each batch of ≥5 PDPs |
| **Master spreadsheet** | Tracking | Update after each session |
| **`R_a_rhs-agm-ornamental-compact.md`** (Dec 2024) | AGM verification — compact markdown format, grouped by genus | Check per variety |
| **Trigger phrases file** | Agreed trigger phrases for Claude workflows — "For Shopify", "Edit Review", "PI:", "TD:" | Yes — every session |
| **Editorial lessons — guide writing** | Tone, voice, and editorial judgement rules from JdeB edits of growing guides. Hub-only reference — not distributed to spokes. Future editorial lessons are captured here before absorption into master rules §3. | Reference during guide and PDP writing (hub sessions) |
| **Category project setup checklist** | Creating new category projects | When setting up a new category |
| **Hub index** | Master manifest — governance versions, spoke project status, sync tracking | Update after every governance change |
| **ImageKit Tagging & Embedding Rules** | Image tagging regime, controlled vocabularies, folder structure, CDN URL construction, advice page embedding pattern | When working with ImageKit images |

Note: The PDP Generation Brief v1.1 and Claude Test specification v3.4 have been **absorbed into this document** as of v8. They no longer need to be loaded separately.

---

## GOVERNANCE ZIP — DISTRIBUTION TO HUB AND SPOKE PROJECTS

### The problem

The master rules, audit skill, and supporting files must be identical across every project. Manual copying creates version drift. A single distributable package solves this.

### The rule

**Whenever Claude updates any governance file** (master rules, audit skill, or verified collection URLs), it must produce a zip file containing the complete current governance set. This zip is the canonical distribution package.

### Pre-build sweep (mandatory before generating the zip)

Before building or rebuilding the governance zip, run the hub pre-build sweep. The authoritative procedure is defined in `X_a_ash-hub-prebuild-sweep.md` (hub-only file — not in the governance zip). Trigger it by saying "run the pre-build sweep".

The sweep checks ten areas and produces a structured PASS/WARN/FAIL report:
- **A — Tier 1 completeness:** All Tier 1 files present at correct versions (count derived from hub index)
- **B — Tier 1 uniqueness:** No stale duplicate versions of any Tier 1 file
- **C — Tier 2 completeness:** All Tier 2 model and advice page files present at correct filenames
- **D — Wrong-pattern filenames:** No deprecated slug-pattern filenames
- **E — Hub-only reference files:** Category references and other hub-only content at current versions, no stale duplicates
- **F — Internal version consistency:** Cross-references between Tier 1 file headers are consistent
- **G — Tier 1 reconciliation:** Hub index and governance zip instruction notes list the same Tier 1 files at the same versions
- **H — Filename convention audit:** All files conform to the G1/G2/A/R/X/P prefix convention with correct category markers
- **I — Orphan detection:** No unregistered files lurking in the project
- **J — Active-text version staleness:** No stale version references in active text (tables, cross-references, examples — not revision logs)

**Critical constraint:** The sweep reads the knowledge base as loaded at conversation open — it does not reflect changes made during the current session. Always run the sweep at the start of a fresh conversation. If files have been added or deleted during the current session, end the conversation and open a new one before running the sweep.

**Result:** Only proceed with zip generation if the sweep result is CLEAN or WARNINGS PRESENT. A FAIL result means a critical file is missing or a cross-reference is broken — resolve before generating.

Only after a clean sweep should the zip be assembled.

### What goes in the zips

The governance package is split into two zip files: one for core governance (changes frequently, always needed), one for model content (changes rarely, provides structural and tonal references). Both should be uploaded to every new project.

**Tier 1 zip — Core governance (universal, required in every project):**

Contains all files listed in the hub index Tier 1 table (`G1_a_ash-pdp-hub-index.md`, "Tier 1 — Core governance" section). See the hub index for the current file list, versions, and descriptions. The hub index is the single source of truth for Tier 1 composition — this section defines principles, not inventory.

| Content type | What it covers | Changes often? |
|-------------|---------------|---------------|
| Rules & editorial style | The master rules — structure, voice, Claude Test, link format, Why Ashridge, FAQs, HTML output | Yes — grows with every editorial lesson |
| Audit & quality | Audit skill (automated checks), API brief (quick-reference cheat sheet) | Yes — new CHECKs, threshold changes |
| Reference data | Verified collection URLs, RHS AGM cross-reference, category references (sweet pea template + dahlia) | Occasionally — when URLs or varieties change |
| Process & workflow | Setup checklist, hub sync protocol, trigger phrases, variety story research brief | Occasionally — when workflows are refined |
| Media governance | ImageKit tagging & embedding rules | When tag regime or embedding rules change |
| Manifest | Hub index (this tracks everything else) | Yes — every governance change |

**Tier 2 zip — Model content (structural and tonal references):**

Contains all files listed in the hub index Tier 2 table. See the hub index for the current file list and descriptions. Tier 2 files are JdeB-edited model PDPs, collection pages, and growing guides that demonstrate the structural and tonal standards for each category.

| Content type | Coverage |
|-------------|----------|
| Model PDPs | One or more JdeB-edited PDPs per active category — currently sweet peas (2), spring bulbs (2), lavender (1), dahlias (2) |
| Model collection page | Sweet pea collections page — demonstrates non-PDP product page structure |
| Model growing guides | One per active category — currently sweet peas (2 — main + pots), spring bulbs (1), dahlias (1), cosmos (1) |

**When to redistribute each zip:**

- **Tier 1 only:** When master rules, audit skill, API brief, collection URLs, hub index, setup checklist, hub sync protocol, trigger phrases, or ImageKit tagging rules change. This is the common case — new rules, new CHECKs, version bumps.
- **Both zips:** When setting up a new project, or when a model PDP or guide has been re-edited.
- **Tier 2 only:** Rarely — only when model content changes but governance files don''t.

**Files NOT included in either zip** (must be sourced per category):

- Category-specific reference files (dahlias, lavender, cosmos, bulbs, etc.) — replace the sweet pea template in Tier 1 with the relevant one
- Category-specific growing guides not already in Tier 2 (e.g. pots guides, overwintering guides, pruning guides)
- JdeB-edited model PDPs from categories not yet represented in Tier 2
- Content gap analyses
- Master spreadsheet / tracker
- RHS AGM reference file (`D_a_rhs-agm-ornamental-compact.md`) — distributed separately via D_ zip
- Category research documents (variety research, slug research, redirect tables)

### Zip filename conventions

- **Tier 1:** `G1_ash-governance-core-v[VERSION]-[YYYY-MM-DD].zip`
- **Tier 2:** `G2_ash-governance-models-v[VERSION]-[YYYY-MM-DD].zip`

Example: `G1_ash-governance-core-v8_38-2026-03-09.zip` and `G2_ash-governance-models-v8_38-2026-03-09.zip`

### Requesting governance files for a spoke project

When asking Claude to prepare governance files for download, always specify the destination spoke project by name. This determines which category reference file is included and allows Claude to confirm the correct file set before generating downloads.

**Preferred request forms:**

- *"Please give me the Tier 1 governance files for the Sweet Pea spoke."*
- *"Please give me Tier 1 and Tier 2 files for the Cosmos spoke."*
- *"Please give me the full governance set for the Spring Bulbs spoke."*

**Pre-download currency check (mandatory before confirming the file list):**

Before presenting the confirmation table, Claude must verify that every file in the proposed download is the most current version available in the current conversation and project knowledge base. Specifically:

1. **Check the Hub Index** — is it current? If any governance change has been made in the session that is not yet reflected in the Hub Index, update the Hub Index first.
2. **Check the Master Rules** — confirm the version in the confirmation table matches the version actually produced or loaded in this session.
3. **Check the category reference** — confirm it is the latest version for the requested spoke, including any slug or content updates made in this session.
4. **Check all other Tier 1 files** — confirm versions match those recorded in the current Hub Index.

If any file is out of date, update it before presenting the confirmation table. Do not present a confirmation table that lists a stale version — the purpose of the table is to give JdeB confidence that what is being downloaded is current.

**Mandatory confirmation step (Claude):**

Before generating any governance file downloads for a spoke project, Claude must respond with a confirmation table listing every file that will be included, its current version, and its tier. JdeB must acknowledge the table before Claude proceeds to generate the files.

Example confirmation format:

> **Governance files for the Sweet Pea spoke — please confirm before I generate these:**
>
> | File | Version | Tier |
> |------|---------|------|
> | G1_b_ash-pdp-master-rules | v8.48 | Tier 1 |
> | G1_b_ash-pdp-audit-skill | v3.21 | Tier 1 |
> | G1_a_ash-pdp-api-brief | v1.13 | Tier 1 |
> | G1_a_ash-verified-collection-urls | v1.3 | Tier 1 |
> | G1_a_ash-pdp-hub-index | v1.47 | Tier 1 |
> | G1_a_ash-category-project-setup-checklist | v1.20 | Tier 1 |
> | G1_a_ash-sweet-pea-category-reference | v1.11 | Tier 1 |
> | G1_a_ash-hub-sync-protocol | v1.2 | Tier 1 |
> | G1_b_ash-trigger-phrases | v1.12 | Tier 1 |
> | G1_a_ash-variety-story-research-brief | v1.1 | Tier 1 |
> | GOV-imagekit-tagging-v1_0 | v1.0 | Tier 1 |
> | G1_a_ash-dahlia-category-reference | v3.1 | Tier 1 |
> | G1_a_ash-update-slugs-workflow | v1.0 | Tier 1 |
> | G1_a_ash-editorial-voice-addendum | v1.0 | Tier 1 |
> | G1_a_ash-seo-audit-workflow | v1.0 | Tier 1 |
> | G1_a_ash-spoke-audit-skill | v1.0 | Tier 1 |
> | G2_a_ash-almost-black-sweet-pea-plants | v2.0 | Tier 2 |
> | G2_a_ash-america-sweet-pea-plants | v2.0 | Tier 2 |
> | G2_a_ash-sweet-pea-collections | v2.0 | Tier 2 |
> | A_sp_a_how-to-grow-sweet-peas | v1.1 | Advice |
> | A_sp_a_growing-sweet-peas-in-pots | v1.1 | Advice |
> | G2_a_ash-munstead-lavender-plants | v2.1 | Tier 2 |
>
> *Correct? Reply "yes" to proceed or flag any discrepancy.*

This step catches version mismatches before a stale file enters a spoke project''s knowledge base.

### How to distribute

1. **Download the zip** from the conversation where it was produced.
2. **Extract on your machine** — this gives you the individual files.
3. **Upload the individual files** to the hub project''s knowledge base (replacing any older versions).
4. **Copy the same individual files** to each spoke project that needs updating.

**Important:** Claude projects cannot read inside zip files. The project knowledge system indexes each file individually — it needs to see separate `.md` and `.html` files, not a zip container. The zip is a transport convenience, not a storage format.

### When to update spoke projects

Not every spoke project needs updating immediately after every rule change. Use this guide:

- **New CHECK added or existing CHECK threshold changed:** Update all active spoke projects promptly.
- **New editorial style rule** (vocabulary, punctuation, tone): Update spoke projects before their next content session.
- **New category-specific rule** (e.g. dahlia exemptions): Only update the relevant spoke project.
- **Bug fix or typo in rules:** Update at next convenient opportunity.

---

## REVISION LOG

- 19 Apr 2026 (v8.54): ToC block added. Cloudinary → ImageKit cross-ref cleanup in GOVERNANCE ZIP section (in-place amendment, no rule change).
- 19 Apr 2026 (v8.53): §12 Cloudinary subsection renamed to ImageKit. Cross-references updated.
- 5 Apr 2026 (v8.52): §7b extended — Sarah Raven, Perch Hill, Hopes Grove added to competitor list.
- 5 Apr 2026 (v8.51): §7b added — Abraham Darby rule for staging data competitor references.
- 4 Apr 2026 (v8.50): AI citability rules (§1 factual anchor, §2 FAQ composition, spec panel AI-priority fields). Climbing Iceberg + Ida Mae editorial lessons. Why Ashridge tightened. Word count floor 700→600.
- 21 Mar 2026 (v8.49): Award name corrections (Which? Gardening Best Plant Supplier, Feefo Platinum Trusted Service Award).
- 20 Mar 2026 (v8.48): §3/§3a merged. Category quick-ref tables removed. Perennial rules (SP-P1–6, E-P1–13) added. Three new spoke entries. NUM items processed.
- 15 Mar 2026 (v8.44): Editorial voice addendum integrated (§3a, CHECKs 32–42, 11 E-rules from clematis model PDPs).
- 13 Mar 2026 (v8.43): Pre-distribution staleness fixes (version references in §9, §14).
- 12 Mar 2026 (v8.42): Cross-file consistency audit. CHECK 6 BANNED list updated. Duplicate paragraphs removed.
- 12 Mar 2026 (v8.41): Governance consistency audit (1a–4i). CHECK 23 threshold clarified. Fragment opener/emphasis distinction. Per-PDP workflow steps 5a, 5b added. CHECKs 27–31 added.
- 9 Mar 2026 (v8.38): Seasonal disclaimer rule. NSPS reference file pointer. §3 "Commit; do not hedge" split from E4.
- 9 Mar 2026 (v8.37): Spoke-awareness pass. Category reference files as definitive per-variety source.
- 9 Mar 2026 (v8.36): CHECK 25 (three-act structure). CHECK 26 (companion links from shopify_slugs).
- 9 Mar 2026 (v8.35): Setup checklist, hub index, governance zip pre-build sweep rule.
- 9 Mar 2026 (v8.34): CHECK 24 (rootgrow per GOV-rootgrow-dosage-policy).
- 9 Mar 2026 (v8.33): Rootgrow rules (§1 spec panel, §5 Why Ashridge, §12 metadata).
- 7 Mar 2026 (v8.32): Macro keyword strategy added (§4b). Advice-page cross-linking refined (§13).
- 7 Mar 2026 (v8.31): Advice-page cross-linking rules (§13a) — scope paragraph, contextual links, Related Guides panel.
- 7 Mar 2026 (v8.30): FAQ content/coverage distinction formalised. CHECK 23 (FAQ coverage audit).
- 7 Mar 2026 (v8.29): Rose section expanded. Rootstock spec rules. PBR/trademark rules.
- 7 Mar 2026 (v8.28): Metadata section rewrite (§12). CHECK 22 (image density). Homepage summary rules.
- 5 Mar 2026 (v8.15): Universal sustainability facts. Jumbo plug technical reference.
- 5 Mar 2026 (v8.14): URL slug standardisation. Two-state filename model. Publish-ready delivery workflow.
- 2 Mar 2026 (v8.13): Output file versioning. Governance two-zip split. Pre-build sweep rule.
- 3 Mar 2026 (v8.11): Dash-avoidance rules from cosmos guide edit. CHECK 4 thresholds tightened.
- 2 Mar 2026 (v8.9): Container FAQ enforcement hardened — approved variety lists, CHECK 9 now FAIL.
- 1 Mar 2026 (v8.8): NSPS classification. FAQ search-volume strategy. Companion heading rotation.
- 1 Mar 2026 (v8.7): Word count raised to 700–1,100w. CHECK 15 relaxed for PDPs.
- 1 Mar 2026 (v8.6): Word count tightened to 700–800w. FAQ as primary reduction lever.
- 1 Mar 2026 (v8.5): Collection page, FAQ pool, delivery spec line.
- 1 Mar 2026 (v8.4): Images, media & visual content rules. CHECKs 18–21 added (alt text, readability, paragraph length, meta description).
- 28 Feb 2026 (v8.3): Bulbs guide 4 edit lessons. 10 new rules. CHECKs 15–17 added. Featured snippet structure.
- 27 Feb 2026 (v8.2): Comma vs en-dash preference.
- 25 Feb 2026 (v8.1): Turquoise Lagoon edit lessons. Expert editorial opinions, "But" as opener.
- 25 Feb 2026 (v8): Consolidation for hub project. Absorbed Generation Brief + Claude Test. §12, §13 added.
- 24 Feb 2026 (v7.1): Windsor edit lessons. Spec panel, hedging table, structural AI tells.
- 24 Feb 2026 (v7): Comprehensive rewrite. Spec panel universal, tautology rule, AGM wording.
- 24 Feb 2026 (v6): Lavender category added.
- 22 Feb 2026 (v5): Major update from JdeB''s 9 dahlia PDP edits.
- 22 Feb 2026 (v1): Created.
', 'text/markdown', NOW(), 'seed')
ON CONFLICT (filename) DO NOTHING;

INSERT INTO governance_files (filename, content, content_type, updated_at, uploaded_by)
VALUES ('GOV-pdp-audit-skill-v3_22.md', '# Ashridge PDP Audit Skill v3.22
## Read this file when the user says "run the PDP audit" or "check the PDPs". One category at a time.

---

## QUICK START

### "Run the PDP audit" (standard audit)

1. User uploads HTML files for one category (e.g. all 9 dahlia PDPs) or a set of guides
2. Claude reads this file
3. Claude runs the automated Claude Test (§2) on all uploaded HTMLs — auto-detects PDPs vs guides
4. Claude runs link validation (§3)
5. Claude runs phrase repetition check (§4)
6. Claude produces a prioritised issues report + updated spreadsheet
7. One category at a time — don''t mix sweet peas and dahlias in one audit

### "Check the PDPs" (audit + hygiene scan)

All of the above, **plus:**

8. Claude runs the hygiene scan (§7a) — stale slugs, missing link attributes, residual comments, old filenames
9. Hygiene results appear in their own section after the audit results in the prioritised report

The hygiene scan requires access to the category reference file (for canonical slug suffixes). If it''s not available, flag that and run the audit without slug checking.

---

## 1. SETUP

```python
# Standard imports for all audit scripts
import re, os, statistics
from collections import Counter

def strip_html(text):
    return re.sub(r''<[^>]+>'', '''', text)

def load_pdps(upload_dir=''/mnt/user-data/uploads''):
    """Load all .html files from uploads. Returns dict of {name: html_content}"""
    pdps = {}
    for f in sorted(os.listdir(upload_dir)):
        if f.endswith(''.html''):
            with open(os.path.join(upload_dir, f)) as fh:
                pdps[f] = fh.read()
    return pdps
```

---

## 2. CLAUDE TEST v3.17 — AUTOMATED CHECKS

### 2.1 Configuration

```python
# --- VOCABULARY ---
BANNED = [''robust'',''testament'',''arguably'',''essentially'',
          ''utilize'',''utilise'',''facilitate'',''leverage'',''optimal'',''comprehensive'',''delve'',
          ''tapestry'',''plethora'',''myriad'',
          # Transition phrases — banned per Master Rules v8.40 CHECK 6
          ''furthermore'',''moreover'',
          "it''s worth noting",''needless to say'',''last but not least'',''in conclusion'',
          # AI word — banned per Master Rules v8.42 CHECK 6
          ''showcasing'']
# Multi-word banned phrases (checked separately — not word-boundary matched)
BANNED_PHRASES = [''in addition'', ''in addition to'', ''additionally'', "what''s more",
                  ''it is worth noting'']
FLAGGED = [''genuinely'',''particularly'',''remarkably'',''straightforward'']

# --- LINK EXEMPTIONS (CHECK 11) ---
# These URLs are exempt from duplicate-link detection globally
EXEMPT_URLS = [
    ''/products/cafe-au-lait-decorative-dahlia-tubers'',
    ''/products/supreme-cafe-au-lait-decorative-dahlia-tubers'',
    ''/products/cafe-au-lait-royal-decorative-dahlia-tubers'',
    ''/products/cafe-au-lait-twist-decorative-dahlia-tubers'',
    ''/products/mixed-cafe-au-lait-dahlia-tubers'',
    ''/products/david-howard-decorative-dahlia-tubers'',
]
# UPDATE this list per category. For sweet peas: probably empty.
# For dahlias: CaL siblings + David Howard as above.

# --- THRESHOLDS ---
EM_DASH_FAIL = 0.8      # per 100 words — hard fail (tightened v3.10)
EM_DASH_FLAG = 0.3      # per 100 words — flag (tightened v3.10)
# Target: zero em-dashes in body text. JdeB baseline: 0.00/100w (cosmos guides v2.2)
IT_IS_THRESHOLD = 2     # max per PDP
```

### 2.2 Helper functions

```python
def get_body_copy(html):
    """Extract body copy excluding spec panel and Why Buy block"""
    body = re.sub(r''<ul[^>]*>.*?</ul>'', '''', html, count=1, flags=re.DOTALL)
    body = re.sub(r''<h2>Why (?:Ashridge|buy from Ashridge)\?</h2>.*?(?=<h2>)'',
                  '''', body, flags=re.DOTALL|re.IGNORECASE)
    return body

def get_body_paragraphs(html):
    """Get paragraphs from body copy only (before FAQs), excluding short ones"""
    faq_split = re.split(r''<h2>Frequently Asked Questions</h2>'', html, flags=re.IGNORECASE)
    body_part = faq_split[0] if faq_split else html
    body_part = re.sub(r''<ul[^>]*>.*?</ul>'', '''', body_part, count=1, flags=re.DOTALL)
    body_part = re.sub(r''<h2>Why (?:Ashridge|buy from Ashridge)\?</h2>.*'',
                       '''', body_part, flags=re.DOTALL|re.IGNORECASE)
    paras = re.findall(r''<p>(.*?)</p>'', body_part, re.DOTALL)
    return [len(strip_html(p).split()) for p in paras if len(strip_html(p).split()) > 5]

def extract_variety_name(html):
    """Pull variety name from spec panel"""
    m = re.search(r''<strong>Variety:</strong>\s*(.*?)</li>'', html)
    return m.group(1).strip() if m else ''Unknown''

def check_h2(html, variety_name):
    """CHECK 3: H2 must contain variety name and not be generic"""
    h2s = re.findall(r''<h2>(.*?)</h2>'', html)
    if not h2s:
        return ''NO H2'', False
    first = h2s[0]
    # Check any significant word from the variety name appears
    words = [w for w in variety_name.split() if len(w) > 2]
    has_name = any(w.lower() in first.lower() for w in words)
    is_generic = first.lower().startswith(''about '')
    return first, has_name and not is_generic

def check_emdash(body_plain, wc):
    """CHECK 4: Dash density (AI tell). Counts only grammatical dashes,
    excluding dashes in numeric ranges (e.g. 75-120cm, July-October).
    Also counts hyphens used as dashes (space-hyphen-space)."""
    all_dashes = list(re.finditer(r''[\u2014\u2013]'', body_plain))
    gram_count = 0
    for m in all_dashes:
        before_char = body_plain[max(0,m.start()-1):m.start()]
        after_char = body_plain[m.end():min(len(body_plain),m.end()+1)]
        # Skip numeric ranges (digit-dash-digit)
        if before_char.isdigit() and after_char.isdigit():
            continue
        # Skip month ranges (letter-dash-Capital, e.g. July-October)
        if before_char.isalpha() and after_char.isupper():
            # Check if previous word looks like a month
            preceding = body_plain[max(0,m.start()-10):m.start()]
            if re.search(r''(?:January|February|March|April|May|June|July|August|September|October|November|December)$'', preceding):
                continue
        gram_count += 1
    # Also count hyphens-as-dashes (word - word pattern)
    hyphen_dashes = len(re.findall(r''[a-zA-Z] - [a-zA-Z]'', body_plain))
    gram_count += hyphen_dashes
    rate = (gram_count / wc * 100) if wc > 0 else 0
    return gram_count, rate

def check_vocab(body_plain):
    """CHECK 6: AI vocabulary"""
    found_banned = [w for w in BANNED if re.search(r''\b'' + re.escape(w) + r''\b'', body_plain, re.IGNORECASE)]
    # Multi-word banned phrases (case-insensitive substring match)
    for phrase in BANNED_PHRASES:
        if phrase.lower() in body_plain.lower():
            found_banned.append(f''"{phrase}"'')
    found_flagged = [w for w in FLAGGED if re.search(r''\b'' + w + r''\b'', body_plain, re.IGNORECASE)]
    return found_banned, found_flagged

def check_it_is(body_plain):
    """CHECK 7: ''It is...'' sentence openers"""
    return len(re.findall(r''(?:^|\. )It (?:is|\''s) '', body_plain))

def check_exclamation(html, body_plain):
    """CHECK 7a: Exclamation mark usage.
    Body copy: max 1 per PDP (0 ideal). 
    Returns (body_count, faq_count, fails).
    """
    body = get_body_copy(html)
    body_count = body_plain.count(''!'')
    # FAQ section exclamations
    faq_section = re.search(r''<h2[^>]*>Frequently Asked Questions</h2>(.*?)$'', html, re.DOTALL|re.IGNORECASE)
    faq_count = faq_section.group(1).count(''!'') if faq_section else 0
    fails = []
    if body_count > 1:
        fails.append((''7a'', f''{body_count} exclamation marks in body'', 
                       ''max 1 in body copy per PDP (0 ideal) — CHECK 7a''))
    return body_count, faq_count, fails

def check_there_is(body_plain):
    """CHECK 7b: ''There is/are...'' sentence openers — max 2 per PDP."""
    count = len(re.findall(r''(?:^|\. )There (?:is|are|was|were|\''s) '', body_plain))
    fails = []
    if count > 2:
        fails.append((''7b'', f''{count} "There is/are" openers'',
                       ''max 2 per PDP — rewrite as active constructions (CHECK 7b)''))
    return count, fails

def check_self_ref(body_plain):
    """CHECK 8: Self-referential content"""
    patterns = [r''the ashridge (?:page|website|description)'', r''existing (?:page|description)'',
                r''their website'', r''the current page'']
    return any(re.search(p, body_plain, re.IGNORECASE) for p in patterns)

def check_duplicate_links(html):
    """CHECK 11: Redundant internal links (with exemptions)"""
    body = re.sub(r''<h2>Why (?:Ashridge|buy from Ashridge)\?</h2>.*?(?=<h2>)'',
                  '''', html, flags=re.DOTALL|re.IGNORECASE)
    links = re.findall(r''href="(/products/[^"]+)"'', body)
    dupes = []
    for l in set(links):
        if links.count(l) > 1 and l not in EXEMPT_URLS:
            dupes.append((l, links.count(l)))
    return dupes

def detect_content_type(html):
    """Detect whether HTML is a PDP or a guide/blog post.
    PDPs have spec panels with Variety: lines. Guides don''t."""
    has_spec = bool(re.search(r''<strong>Variety:</strong>'', html))
    return ''pdp'' if has_spec else ''guide''

def extract_topic_phrase(html):
    """For guides: extract the core topic from the first H2.
    Returns a list of keyword fragments to check against other headings."""
    first_h2 = re.search(r''<h2[^>]*>(.*?)</h2>'', html)
    if not first_h2:
        return []
    title = strip_html(first_h2.group(1)).lower()
    # Common topic phrases in guide titles
    phrases = []
    for candidate in [''bulbs in the green'', ''spring bulbs'', ''bulbs in pots'',
                       ''bulbs in containers'', ''bulbs flower'', ''flower bulbs'',
                       ''bulb'', ''lavender'', ''dahlia'', ''sweet pea'', ''cosmos'']:
        if candidate in title:
            phrases.append(candidate)
    # Fallback: if no known phrase matched, use significant nouns from title
    if not phrases:
        words = [w for w in title.split() if len(w) > 3 
                 and w not in (''with'',''from'',''that'',''this'',''your'',''when'',''what'',''they'')]
        phrases = words[:3]
    return phrases

def check_heading_keywords(html, content_type, variety_name=''''):
    """CHECK 15: Heading keyword relevance.
    Every H2/H3 must make sense in isolation.
    - PDPs: variety name in every H2 (overlaps CHECK 3).
    - Guides: core topic phrase in every H2; H3s checked if bare word alone is ambiguous.
    FAQ H3s (questions with ''?'') are exempt."""
    h2s = re.findall(r''<h2[^>]*>(.*?)</h2>'', html)
    h3s = re.findall(r''<h3[^>]*>(.*?)</h3>'', html)
    fails = []
    
    if content_type == ''pdp'':
        # CHECK 3 covers variety name in the opening H2.
        # CHECK 15 covers the rest: flag H2s that are generic (no subject keyword).
        # Two types of exempt heading:
        #   (a) Standardised headings — always the same wording across the whole set
        #       (Why Ashridge variants, FAQs, Companions).
        #   (b) Flexible middle H2s — topic-specific but variety-name-free. These pass
        #       because the topic IS self-contained without the variety name: "In a Vase",
        #       "How the Colour Works", "In the Border". Distinct from truly generic labels
        #       like "Aftercare" or "Getting Started" which identify no specific topic at all.
        EXEMPT_PATTERNS = [
            # (a) Standardised headings
            r''why (?:ashridge|buy)'',
            r''frequently asked'',
            r''planting companions'',
            r''companion plant'',
            r''growing companions'',
            r''perfect partners'',
            r''pairing ideas'',
            # (b) Flexible middle H2s (topic self-contained without variety name)
            r''in a vase'',
            r''in the (?:border|garden|vase|cutting garden|cut.flower garden)'',
            r''how the colou?r works'',
            r''cut.flower'',
            r''for cutting'',
            r''at the shows?'',
            r''in the wild'',
        ]
        # Generic heading patterns — make sense only in context, not in isolation
        GENERIC_PATTERNS = [
            r''^how to (?:grow|plant|care|use)$'',
            r''^aftercare$'',
            r''^getting started$'',
            r''^more information$'',
            r''^about(?: this)?(?: variety)?$'',
            r''^introduction$'',
            r''^overview$'',
            r''^care (?:guide|tips|advice)$'',
            r''^planting$'',
            r''^growing$'',
        ]
        for h in h2s[1:]:  # Skip opening H2 — CHECK 3 already covers it
            h_text = strip_html(h).strip()
            h_lower = h_text.lower()
            # Skip exempt headings
            if any(re.search(p, h_lower) for p in EXEMPT_PATTERNS):
                continue
            # Flag headings that match generic patterns exactly
            if any(re.match(p, h_lower) for p in GENERIC_PATTERNS):
                fails.append((h_text, ''Generic heading — no subject keyword (CHECK 15)''))

    else:
        # Guide mode
        topic_phrases = extract_topic_phrase(html)
        if not topic_phrases:
            return [(''NO TOPIC DETECTED'', ''Could not extract topic from first H2'')]
        
        # Check H2s (skip the first one — it IS the title)
        for h in h2s[1:]:
            h_text = strip_html(h).lower()
            has_keyword = any(phrase in h_text for phrase in topic_phrases)
            # Also accept if it contains ''bulb'' anywhere (covers many guide topics)
            if not has_keyword and ''bulb'' not in h_text:
                fails.append((strip_html(h), ''H2 missing topic keyword''))
        
        # Check H3s — only flag if they''re NOT questions and lack keywords
        for h in h3s:
            h_text = strip_html(h)
            if ''?'' in h_text:
                continue  # FAQ questions are exempt
            h_lower = h_text.lower()
            has_keyword = any(phrase in h_lower for phrase in topic_phrases)
            if not has_keyword and ''bulb'' not in h_lower:
                # Only flag if heading is truly generic (one or two words)
                if len(h_lower.split()) <= 3:
                    fails.append((h_text, ''H3 may need topic keyword''))
    
    return fails

def check_snippet_readiness(html, content_type):
    """CHECK 16: Snippet-ready structure.
    16a: FAQ answers must open with standalone response under 50 words.
    16b: Guide H2 sections must open with direct answer in 40-60 words.
    16c: Lists must have keyword-rich heading directly above them."""
    fails = []
    
    # 16a: FAQ snippet-readiness
    # Find all H3 + following paragraph pairs
    faq_pairs = re.findall(
        r''<h3[^>]*>(.*?)</h3>\s*<p>(.*?)</p>'',
        html, re.DOTALL
    )
    for question, answer in faq_pairs:
        q_text = strip_html(question).strip()
        if ''?'' not in q_text:
            continue  # Not a FAQ question
        
        a_text = strip_html(answer).strip()
        # Get first sentence
        first_sent_match = re.match(r''^(.*?(?:\.|$))'', a_text)
        if not first_sent_match:
            continue
        first_sent = first_sent_match.group(1).strip()
        first_sent_words = len(first_sent.split())
        
        # Check for throat-clearing openers
        throat_clearing = [
            r''^(?:that\''s a |this is a |it\''s a )(?:great|good|common|fair) question'',
            r''^(?:the (?:honest|simple|short) answer (?:is|here))'',
            r''^(?:well,? )'',
            r''^(?:so,? )'',
            r''^it depends(?:\.|,| on)'',
        ]
        for pattern in throat_clearing:
            if re.search(pattern, first_sent.lower()):
                fails.append((''16a'', q_text[:60], f''Throat-clearing opener: "{first_sent[:50]}..."''))
                break
        
        # Check standalone "Yes." or "No." without substance
        if re.match(r''^(?:Yes|No)\.?\s*$'', first_sent):
            fails.append((''16a'', q_text[:60], ''Opens with bare Yes/No — fold into a complete statement''))
        
        # Check word count (over 50 = too long for snippet extraction)
        if first_sent_words > 50:
            fails.append((''16a'', q_text[:60], f''First sentence {first_sent_words}w (target: under 50w)''))
    
    # 16b: Guide H2 section openings (guides only)
    if content_type == ''guide'':
        # Find H2 + first paragraph pairs
        h2_sections = re.findall(
            r''<h2[^>]*>(.*?)</h2>\s*(?:<p>)(.*?)</p>'',
            html, re.DOTALL
        )
        for heading, first_para in h2_sections:
            h_text = strip_html(heading).strip()
            p_text = strip_html(first_para).strip()
            
            # Skip very short intro paragraphs (likely transitional)
            p_words = len(p_text.split())
            if p_words < 10:
                continue
            
            # Get first two sentences
            sentences = re.split(r''(?<=[.!?])\s+'', p_text)
            first_two = '' ''.join(sentences[:2]) if len(sentences) >= 2 else sentences[0]
            first_two_words = len(first_two.split())
            
            # Check if first two sentences could serve as a standalone answer
            # Flag if they''re very long (over 80 words — well past snippet extraction window)
            if first_two_words > 80:
                fails.append((''16b'', h_text[:60], f''Opening {first_two_words}w before delivering core point — consider leading with the direct answer''))
    
    # 16c: Lists without keyword-rich headings
    # Find all <ul> and <ol> and check what''s directly above them
    list_positions = [(m.start(), m.group()) for m in re.finditer(r''<(?:ul|ol)[^>]*>'', html)]
    for pos, tag in list_positions:
        # Get the 200 chars before the list
        preceding = html[max(0, pos-300):pos]
        # Check if there''s a heading close before the list
        heading_match = re.search(r''<h[23][^>]*>(.*?)</h[23]>'', preceding)
        if not heading_match:
            # Check if preceded by a <p> with bold lead (acceptable but not ideal)
            p_match = re.search(r''<p>.*?</p>\s*$'', preceding, re.DOTALL)
            if p_match:
                continue  # Has preceding context, may be fine
            fails.append((''16c'', f''List at position {pos}'', ''No heading found directly above list''))
    
    return fails

def check_keyword_density(html, content_type):
    """CHECK 17: Keyword phrase density.
    17a: No exact 2+ word phrase in more than 60% of H2 headings.
    17b: No exact 3+ word phrase more than 5x/1000w in body copy.
    17c: No exact multi-word phrase in more than 50% of H2 opener sentences."""
    fails = []
    
    # Extract all H2 headings
    h2s_raw = re.findall(r''<h2[^>]*>(.*?)</h2>'', html)
    h2s = [strip_html(h).strip().lower() for h in h2s_raw]
    total_h2 = len(h2s)
    
    if total_h2 < 4:
        return fails  # Too few headings to measure meaningfully
    
    # Helper: extract n-word phrases from text
    def get_phrases(text, n):
        words = text.split()
        words = [w.strip(''.,;:!?()—–"\''-'') for w in words if w.strip(''.,;:!?()—–"\''-'')]
        return ['' ''.join(words[i:i+n]) for i in range(len(words)-n+1)]
    
    # 17a: Heading phrase monotony
    # Check 2-word and 3-word phrases across H2s
    from collections import Counter
    for phrase_len in (2, 3):
        phrase_counts = Counter()
        for h in h2s:
            for phrase in set(get_phrases(h, phrase_len)):
                phrase_counts[phrase] += 1
        
        # Filter out very common stopword-only phrases
        stops = {''the'',''a'',''an'',''and'',''or'',''but'',''in'',''on'',''at'',''to'',''for'',''of'',''is'',
                 ''it'',''are'',''was'',''with'',''from'',''by'',''as'',''this'',''that'',''you'',''your'',
                 ''we'',''our'',''if'',''not'',''no'',''do'',''so'',''—'',''–'',''&''}
        for phrase, count in phrase_counts.most_common(10):
            words_in_phrase = phrase.split()
            if all(w in stops for w in words_in_phrase):
                continue  # Skip pure-stopword phrases
            pct = count / total_h2 * 100
            if pct > 60:
                fails.append((''17a'', f''"{phrase}"'', f''in {count}/{total_h2} H2s ({pct:.0f}%) — vary phrasing''))
    
    # 17b: Body copy exact-phrase density (3+ word phrases)
    body_text = strip_html(html).strip().lower()
    body_wc = len(body_text.split())
    
    if body_wc > 200:  # Only check on substantial content
        phrase_counts_3 = Counter(get_phrases(body_text, 3))
        threshold_per_1k = 5
        threshold = max(5, int(body_wc / 1000 * threshold_per_1k))
        
        for phrase, count in phrase_counts_3.most_common(20):
            words_in_phrase = phrase.split()
            if all(w in stops for w in words_in_phrase):
                continue
            if count > threshold:
                rate = count / body_wc * 1000
                fails.append((''17b'', f''"{phrase}"'', f''{count}x in {body_wc}w ({rate:.1f}/1000w) — exceeds {threshold_per_1k}/1000w threshold''))
    
    # 17c: Opening-sentence echo
    # Extract first sentence of paragraph after each H2
    h2_openers = re.findall(
        r''<h2[^>]*>.*?</h2>\s*(?:<p>)(.*?)</p>'',
        html, re.DOTALL
    )
    opener_sents = []
    for o in h2_openers:
        text = strip_html(o).strip().lower()
        sents = re.split(r''(?<=[.!?])\s+'', text)
        if sents and len(sents[0].split()) >= 4:
            opener_sents.append(sents[0])
    
    total_openers = len(opener_sents)
    if total_openers >= 4:
        opener_phrase_counts = Counter()
        for sent in opener_sents:
            for phrase in set(get_phrases(sent, 3)):
                opener_phrase_counts[phrase] += 1
        
        for phrase, count in opener_phrase_counts.most_common(10):
            words_in_phrase = phrase.split()
            if all(w in stops for w in words_in_phrase):
                continue
            pct = count / total_openers * 100
            if pct > 50:
                fails.append((''17c'', f''"{phrase}"'', f''in {count}/{total_openers} openers ({pct:.0f}%) — vary opening phrasing''))
    
    return fails
```

### 2.2d CHECK 18 — Image alt text

```python
def check_image_alt(html):
    """CHECK 18: Verify all <img> tags have descriptive alt text."""
    fails = []
    
    imgs = re.findall(r''<img[^>]*>'', html, re.IGNORECASE)
    if not imgs:
        return fails  # No images = nothing to check
    
    for img in imgs:
        # Missing alt attribute entirely
        if ''alt='' not in img.lower():
            src = re.search(r''src=["\'']([^"\'']*)["\'']'', img)
            src_str = src.group(1)[-40:] if src else ''unknown''
            fails.append((''18'', f''<img src="...{src_str}">'', ''missing alt attribute''))
            continue
        
        # Empty alt text — empty string is valid for decorative images; only flag non-empty but too-short alt
        alt_match = re.search(r''alt=["\'']([^"\'']*)["\'']'', img)
        if alt_match:
            alt_text = alt_match.group(1).strip()
            if alt_text == '''':
                pass  # Empty alt is correct for decorative images — do not flag
            elif len(alt_text) < 5:
                fails.append((''18'', f''alt="{alt_text}"'', ''alt text too short to be descriptive''))
            elif len(alt_text) > 140:
                fails.append((''18'', f''alt="{alt_text[:40]}..."'', f''alt text {len(alt_text)} chars — over 140 limit''))
        
        # Missing loading="lazy" (skip first image)
        if imgs.index(img) > 0 and ''loading='' not in img.lower():
            fails.append((''18'', ''<img ...>'', ''missing loading="lazy"''))
    
    return fails
```

### 2.2e CHECK 19 — Readability score

```python
def count_syllables_simple(word):
    """Simple English syllable counter — no external dependencies."""
    word = word.lower().strip(''.,;:!?()—–"\''-'')
    if not word:
        return 0
    if len(word) <= 3:
        return 1
    count = 0
    vowels = ''aeiouy''
    prev_vowel = False
    for char in word:
        is_vowel = char in vowels
        if is_vowel and not prev_vowel:
            count += 1
        prev_vowel = is_vowel
    if word.endswith(''e'') and count > 1:
        count -= 1
    if word.endswith(''le'') and len(word) > 2 and word[-3] not in vowels:
        count += 1
    return max(1, count)

def check_readability(html):
    """CHECK 19: Flesch-Kincaid grade level. Returns (fk_grade, result)."""
    plain = strip_html(html).strip()
    plain = re.sub(r''\n+'', '' '', plain)
    plain = re.sub(r'' +'', '' '', plain)
    
    sentences = [s.strip() for s in re.split(r''[.!?]+'', plain) if len(s.strip().split()) >= 3]
    words = [w for w in plain.split() if w.strip(''.,;:!?()—–"\''-'')]
    
    if not sentences or len(words) < 50:
        return (0.0, ''SKIP'')  # Too short to measure meaningfully
    
    total_syllables = sum(count_syllables_simple(w) for w in words)
    avg_sentence_len = len(words) / len(sentences)
    avg_syllables = total_syllables / len(words)
    
    fk_grade = 0.39 * avg_sentence_len + 11.8 * avg_syllables - 15.59
    
    if fk_grade <= 9.0:
        return (fk_grade, ''PASS'')
    elif fk_grade <= 10.5:
        return (fk_grade, ''FLAG'')
    else:
        return (fk_grade, ''FAIL'')
```

### 2.2f CHECK 20 — Paragraph length

```python
def check_paragraph_length(html):
    """CHECK 20: Flag paragraphs over 5 sentences or 100 words."""
    fails = []
    
    paras = re.findall(r''<p>(.*?)</p>'', html, re.DOTALL)
    long_count = 0
    total_measured = 0
    
    for p in paras:
        p_text = strip_html(p).strip()
        words = p_text.split()
        if len(words) < 5:
            continue  # Skip tiny fragments
        
        total_measured += 1
        sents = [s for s in re.split(r''(?<=[.!?])\s+'', p_text) if len(s.split()) >= 3]
        sent_count = max(1, len(sents))
        wc = len(words)
        
        if sent_count > 5 or wc > 100:
            long_count += 1
            preview = p_text[:60].replace(''\n'', '' '')
            fails.append((''20'', f''"{preview}..."'', f''{sent_count} sentences, {wc} words''))
    
    # Page-level check: >15% of paragraphs are long
    if total_measured > 0 and long_count / total_measured > 0.15:
        fails.insert(0, (''20-page'', f''{long_count}/{total_measured} paragraphs'', f''{long_count/total_measured:.0%} over threshold — 15% max''))
    
    return fails
```

### 2.2g CHECK 21 — Meta description quality

```python
def check_meta_description(meta_text, topic_keyword='''', all_metas=None):
    """CHECK 21: Meta description quality. 
    meta_text: the meta description string.
    topic_keyword: primary keyword expected (variety name or guide topic).
    all_metas: list of all meta descriptions in the set, for uniqueness check.
    """
    fails = []
    
    if not meta_text or not meta_text.strip():
        fails.append((''21'', ''(empty)'', ''no meta description provided''))
        return fails
    
    meta = meta_text.strip()
    
    # Length
    if len(meta) > 165:
        fails.append((''21'', f''{len(meta)} chars'', f''over 165-char limit — trim by {len(meta)-165}''))
    
    # Contains "and" instead of "&"
    if '' and '' in meta.lower():
        fails.append((''21'', ''"and"'', ''use "&" to save characters''))
    
    # Primary keyword present
    if topic_keyword and topic_keyword.lower() not in meta.lower():
        fails.append((''21'', f''missing "{topic_keyword}"'', ''primary keyword not found in meta description''))
    
    # Uniqueness
    if all_metas:
        dupes = [m for m in all_metas if m.strip().lower() == meta.lower() and m is not meta_text]
        if dupes:
            fails.append((''21'', ''duplicate'', ''same meta description appears on another page''))
    
    return fails
```

```python
def check_passive_voice(body_plain, wc):
    """CHECK 23: Passive voice density.
    Returns (count, rate_per_400w, fails).
    Counts syntactic passives: is/are/was/were/been/be + past participle.
    Spec panels, FAQ answers, and quoted sources are exempt — this runs on body_plain.
    """
    passive_pattern = re.compile(
        r''\b(?:is|are|was|were|been|be|being)\s+\w+ed\b'',
        re.IGNORECASE
    )
    # Common false positives to exclude (adjective + past-participle forms that aren''t passives)
    FALSE_POSITIVE_FRAGMENTS = {''is used'', ''are used'', ''was used'', ''were used''}  # Kept as legitimate passives
    matches = passive_pattern.findall(body_plain)
    count = len(matches)
    
    fails = []
    # Rate per 400 words
    rate = (count / wc) * 400 if wc > 0 else 0
    if rate > 2:
        fails.append((''23'', f''{count} passives / {wc}w ({rate:.1f}/400w)'', 
                       f''exceeds 2 per 400w — active voice preferred (CHECK 23)''))
    return count, rate, fails


def check_link_text(html):
    """CHECK 24: Link text quality.
    Flags generic anchor text: click here, find out more, learn more, read more,
    here (standalone), our range, this link, more information.
    """
    BANNED_LINK_TEXT = {
        ''click here'', ''find out more'', ''learn more'', ''read more'',
        ''here'', ''our range'', ''this link'', ''more information'',
        ''find out'', ''click'', ''read on'', ''more details'',
    }
    link_pattern = re.compile(r''<a\b[^>]*>(.*?)</a>'', re.IGNORECASE | re.DOTALL)
    fails = []
    for match in link_pattern.finditer(html):
        text = strip_html(match.group(1)).strip().lower()
        if text in BANNED_LINK_TEXT:
            fails.append((''24'', f''"{text}"'', f''generic link text — use descriptive anchor (CHECK 24)''))
    return fails


def check_opening_word(html):
    """CHECK 25: Extract first word of body copy P1 for opening word variety check.
    Returns the first word (lowercase) or None if not found.
    """
    body = get_body_copy(html)
    if not body:
        return None
    paragraphs = re.findall(r''<p[^>]*>(.*?)</p>'', body, re.DOTALL)
    for p in paragraphs:
        text = strip_html(p).strip()
        words = text.split()
        if words:
            return words[0].lower().rstrip(''.,;:!?'')
    return None


def check_opening_word_variety(opener_words):
    """CHECK 25: Batch check — flag if any word appears as opener in >2 PDPs in a batch of 5+.
    opener_words: dict of {filename: first_word}.
    Returns list of (word, count, filenames) for flagged words.
    """
    from collections import Counter
    if len(opener_words) < 5:
        return []  # Only applies to batches of 5+
    counts = Counter(opener_words.values())
    flagged = [(word, count, [fn for fn, w in opener_words.items() if w == word])
               for word, count in counts.items() if count > 2]
    return sorted(flagged, key=lambda x: -x[1])


def check_comma_splice(body_plain, wc):
    """CHECK 26: Comma splice frequency.
    Heuristic: count sentences where a comma precedes what looks like an independent clause start.
    Pattern: comma + optional space + capital letter + lowercase continuation (not a proper noun).
    This is intentionally conservative — only flags probable mechanical splices, not rhythm ones.
    Returns (count, fails).
    """
    # Pattern: ", [Capital][lowercase word(s)]" where the capital starts a new independent clause
    # We look for: ", [He/She/They/It/The/A/An/You/We/I] " as high-confidence independent clause starters
    CLAUSE_STARTERS = r''(?:He|She|They|It|The|A|An|You|We|I|This|These|That|Those|There)\b''
    splice_pattern = re.compile(r'',\s+'' + CLAUSE_STARTERS, re.UNICODE)
    matches = splice_pattern.findall(body_plain)
    count = len(matches)
    
    fails = []
    # Threshold: more than 2 per 500 words
    rate = (count / wc) * 500 if wc > 0 else 0
    if rate > 2:
        fails.append((''26'', f''{count} probable splices / {wc}w ({rate:.1f}/500w)'',
                       ''comma splice frequency high — review for mechanical over-use (CHECK 26)''))
    return count, fails

```

```python
# --- CHECK 27b: Spec panel synonym-cluster repetition ---
# Synonym clusters: terms treated as equivalent for spec panel repetition detection.
# If any cluster (by any term) appears on >60% of PDPs in a batch of 5+, flag it.
# Clusters are defined here; batch-level check runs in quality scoring §5.

SPEC_SYNONYM_CLUSTERS = {
    ''scent_intensity'': [
        ''strongly scented'', ''strong scent'', ''strongly perfumed'', ''strong perfume'',
        ''richly scented'', ''richly perfumed'', ''heavily scented'', ''heavily perfumed'',
        ''well scented'', ''well-scented'', ''well perfumed'', ''well-perfumed'',
        ''pleasantly scented'', ''pleasantly perfumed'', ''delightfully scented'',
        ''delightfully perfumed'', ''wonderfully scented'', ''wonderfully perfumed'',
        ''intensely scented'', ''intensely perfumed'', ''deeply scented'', ''deeply perfumed'',
    ],
    ''scent_light'': [
        ''lightly scented'', ''light scent'', ''mild scent'', ''mildly scented'',
        ''faint scent'', ''faintly scented'', ''subtle scent'', ''subtly scented'',
        ''barely scented'', ''little scent'', ''gentle scent'', ''gently scented'',
    ],
    ''cutting_quality'': [
        ''excellent cut flower'', ''good cut flower'', ''superb cut flower'',
        ''ideal cut flower'', ''perfect cut flower'', ''fine cut flower'',
        ''great for cutting'', ''excellent for cutting'', ''ideal for cutting'',
        ''good for cutting'', ''perfect for cutting'', ''superb for cutting'',
    ],
    ''stem_length'': [
        ''long stems'', ''long-stemmed'', ''good stems'', ''strong stems'',
        ''excellent stems'', ''fine stems'', ''tall stems'',
    ],
}


def check_spec_panel_synonyms(pdps_spec_text):
    """CHECK 27b: Spec panel synonym-cluster repetition (batch-level).
    pdps_spec_text: dict of {filename: spec_panel_plain_text}.
    For each synonym cluster, flag if any cluster (by any synonym) appears
    on more than 60% of PDPs in a batch of 5+.
    Returns list of (cluster_name, matched_terms, count, n, filenames) tuples.
    """
    if len(pdps_spec_text) < 5:
        return []  # Batch too small for meaningful check
    
    threshold = 0.6
    n = len(pdps_spec_text)
    fails = []
    
    for cluster_name, synonyms in SPEC_SYNONYM_CLUSTERS.items():
        pattern = re.compile(''|''.join(re.escape(s) for s in synonyms), re.IGNORECASE)
        matching_files = []
        matched_terms = set()
        for filename, spec_text in pdps_spec_text.items():
            m = pattern.search(spec_text)
            if m:
                matching_files.append(filename)
                matched_terms.add(m.group().lower())
        count = len(matching_files)
        if n > 0 and count / n > threshold:
            fails.append((
                cluster_name,
                sorted(matched_terms),
                count,
                n,
                matching_files
            ))
    return fails


def check_favourites(body_plain):
    """CHECK 28: Don''t declare favourites publicly.
    Flag phrases that could declare one variety superior to others in the range.
    Returns list of fails.
    """
    FORBIDDEN = [
        r''\bour favou?rite\b'',
        r''\bmy favou?rite\b'',
        r''the best\b.{0,30}\bin our range\b'',
        r''\bour best\b'',
        r''the finest\b.{0,30}\bin(?:\s+the)?\s+range\b'',
    ]
    fails = []
    for pattern in FORBIDDEN:
        m = re.search(pattern, body_plain, re.IGNORECASE)
        if m:
            fails.append((''28'', f''"{m.group()}"'',
                           ''avoid declaring a favourite — see Master Rules §3 (CHECK 28). ''
                           ''EXPERT flag appropriate if JdeB approval sought.''))
    return fails


def check_para_opener_repetition(html):
    """CHECK 29: Paragraph opener repetition within a single PDP.
    Flag if any word appears as the opener of more than 2 body <p> blocks.
    Returns list of fails.
    """
    body = get_body_copy(html)
    paras = re.findall(r''<p[^>]*>(.*?)</p>'', body, re.DOTALL | re.IGNORECASE)
    opener_words = []
    for p in paras:
        text = strip_html(p).strip()
        if len(text.split()) < 4:
            continue  # Skip very short or structural paragraphs
        first_word = text.split()[0].lower().rstrip(''.,;:'')
        opener_words.append(first_word)
    
    from collections import Counter
    counts = Counter(opener_words)
    fails = []
    for word, count in counts.items():
        if count > 2 and len(word) > 1:
            indices = [i + 1 for i, w in enumerate(opener_words) if w == word]
            fails.append((''29'', f''"{word}" opens {count} paragraphs (¶{", ¶".join(str(i) for i in indices)})'',
                           ''paragraph opener repeated — vary paragraph openings (CHECK 29)''))
    return fails


def check_sentence_opener_repetition(html):
    """CHECK 31: Sentence construction repetition within a paragraph.
    Flag if 3+ sentences in the same <p> block begin with the same word.
    Returns list of fails.
    """
    body = get_body_copy(html)
    variety = extract_variety_name(html)
    variety_first = variety.split()[0].lower() if variety else ''''
    paras = re.findall(r''<p[^>]*>(.*?)</p>'', body, re.DOTALL | re.IGNORECASE)
    
    fails = []
    for i, p in enumerate(paras):
        text = strip_html(p).strip()
        sentences = re.split(r''(?<=[.!?])\s+'', text)
        sentences = [s for s in sentences if len(s.split()) >= 3]
        if len(sentences) < 3:
            continue
        
        first_words = [s.split()[0].lower().rstrip(''.,;:'') for s in sentences]
        from collections import Counter
        word_counts = Counter(first_words)
        for word, count in word_counts.items():
            if count >= 3 and (len(word) > 2 or word == variety_first):
                fails.append((''31'', f''Paragraph {i + 1}: "{word}" starts {count} sentences'',
                               ''repeated sentence opener within paragraph — AI structural tell (CHECK 31)''))
    return fails


def check_generic_filler(body_plain):
    """CHECK 30: Generic filler phrases — auto-fail.
    Phrases that signal generic AI output regardless of banned vocabulary.
    Returns list of fails.
    """
    FILLER_PATTERNS = [
        (r''perfect for (?:borders?,?\s*pots?\s*and\s*vases?|pots?,?\s*borders?\s*and\s*vases?|vases?,?\s*(?:borders?|pots?)\s*and\s*(?:borders?|pots?))'',
         ''generic triple "perfect for" — be specific about why for THIS variety (CHECK 30)''),
        (r''\ba welcome addition to any garden\b'',
         ''generic filler phrase (CHECK 30)''),
        (r''\bideal for any border\b'',
         ''generic filler phrase (CHECK 30)''),
        (r''\bsuit(?:s|able for) any (?:style of )?garden\b'',
         ''generic filler phrase (CHECK 30)''),
        (r''\ba versatile choice for\b'',
         ''generic filler phrase — state the specific use instead (CHECK 30)''),
        (r''\bno garden should be without\b'',
         ''generic filler phrase (CHECK 30)''),
    ]
    fails = []
    for pattern, message in FILLER_PATTERNS:
        m = re.search(pattern, body_plain, re.IGNORECASE)
        if m:
            fails.append((''30'', f''"{m.group()}"'', message))
    return fails

```

### CHECKs 32–42 — Editorial Voice (§3 E1–E11)

Added v3.20 (15 Mar 2026). Source: `G1_a_ash-editorial-voice-addendum-v1_0.md`.

```python
# --- MODULE-LEVEL CONSTANT for CHECK 36 ---
HEDGE_WORDS = [
    r''\bcan be\b'', r''\bmay be\b'', r''\bmight be\b'', r''\bperhaps\b'',
    r''\bsomewhat\b'', r''\brelatively\b'', r''\brather\b(?! than)'',
    r''\bfairly\b'', r''\bquite\b(?! (?:a lot|right|wrong|simply|clearly))'',
    r''\btend(?:s)? to\b'', r''\ba little\b'', r''\ba bit\b'',
    r''\bgenerally\b'', r''\btypically\b'', r''\busually\b'',
    r''\bslightly\b'', r''\bto some (?:extent|degree)\b'',
    r''\bit is possible\b'', r''\bcould potentially\b''
]

def check_personal_anecdote(body_plain):
    """CHECK 32: Personal anecdote presence (E1).
    Scans for markers of personal content. Returns (found_markers, fails)."""
    markers = []
    rel_words = r''\b(?:friend|neighbour|neighbor|grandmother|granddaughter|grandfather|grandson|sister|brother|mother|father|wife|husband|partner|customer|visitor)\b''
    rel = re.findall(rel_words, body_plain, re.IGNORECASE)
    if rel: markers.extend([f''relationship: {w}'' for w in rel])
    mem_patterns = [r''\bI (?:remember|have seen|once|saw|visited|met|grew up)\b'',
                    r''\byears ago\b'', r''\bat home\b'', r''\bin my (?:garden|experience)\b'',
                    r''\bwe have (?:one|a|an)\b'']
    for p in mem_patterns:
        if re.search(p, body_plain, re.IGNORECASE):
            markers.append(f''memory: {p}'')
    place_pattern = r''\bin (?!Group |January|February|March|April|May|June|July|August|September|October|November|December)[A-Z][a-z]+(?:,| (?:in|near))''
    places = re.findall(place_pattern, body_plain)
    if places: markers.extend([f''place: {p.strip()}'' for p in places])
    fails = []
    if not markers:
        fails.append((''32'', ''No personal anecdote markers detected'',
                       ''Flag for JdeB input — every PDP needs at least one personal reference (E1)''))
    return markers, fails


def check_sentence_variation(body_plain):
    """CHECK 33: Sentence length variation (E2).
    Flags if no short sentences (<=7 words) or fragments in body copy."""
    sentences = re.split(r''(?<=[.!?])\s+'', body_plain.strip())
    sentences = [s for s in sentences if len(s.split()) >= 1]
    short = [s for s in sentences if len(s.split()) <= 7]
    common_verbs = {''is'',''are'',''was'',''were'',''has'',''have'',''had'',''do'',''does'',''did'',
                    ''will'',''would'',''can'',''could'',''should'',''may'',''might'',''shall'',
                    ''grows'',''flowers'',''reaches'',''produces'',''needs'',''gives'',''makes'',
                    ''plant'',''cut'',''prune'',''water'',''feed'',''grow'',''flower'',''reach''}
    fragments = []
    for s in sentences:
        words_lower = {w.lower().strip(''.,;:!?'') for w in s.split()}
        if not words_lower & common_verbs and len(s.split()) <= 10:
            fragments.append(s)
    fails = []
    if not short and not fragments:
        fails.append((''33'', ''No short sentences (≤7w) or fragments in body copy'',
                       ''Break up prose rhythm with at least one short declarative or fragment (E2)''))
    return len(short), len(fragments), fails


def check_colloquial_voice(body_plain):
    """CHECK 34: Colloquial voice markers (E3).
    Informational — flags absence, not enforces presence."""
    markers = []
    informal = re.findall(r"\b(?:you''ve|we''ve|they''re|who''s|that''s|here''s|there''s|wouldn''t|couldn''t|shouldn''t|you''ll|we''ll|they''ll)\b", body_plain, re.IGNORECASE)
    if informal: markers.append(f''contractions: {len(informal)}'')
    rhetorical = re.findall(r''[A-Z][^.!?]*\?'', body_plain)
    if rhetorical: markers.append(f''rhetorical questions: {len(rhetorical)}'')
    colloquial_patterns = [r''no wonder'', r''say no more'', r''mind you'', r''by the way'',
                           r''to be fair'', r''let\''s face it'', r''put it this way'',
                           r''like .+ and .+'',
                           r''the (?:honest |simple )?truth is'',
                           r''guess wh(?:at|ich)'', r''in a word'']
    for p in colloquial_patterns:
        if re.search(p, body_plain, re.IGNORECASE):
            markers.append(f''colloquial: {p}'')
    return markers  # Informational only — no fails generated


def check_honest_limitation(html):
    """CHECK 35: Honest limitation in Why Ashridge block (E4)."""
    wa_match = re.search(
        r''<h2>(?:Why (?:Ashridge|Buy)[^<]*|From Our Nursery[^<]*|Raised at[^<]*|About Your Plant)</h2>(.*?)(?=<h2>|$)'',
        html, re.DOTALL | re.IGNORECASE)
    if not wa_match:
        return [], [(''35'', ''No Why Ashridge block found'', ''Cannot check for honest limitations'')]
    wa_text = strip_html(wa_match.group(1)).lower()
    limitation_markers = [
        r''\bbut\b'', r''\bsometimes\b'', r''\bdifficult\b'', r''\bnot always\b'',
        r''\bhonest\b'', r''\badmit\b'', r''\bin extremis\b'', r''\bbuy in\b'',
        r''\bbought in\b'', r''\bnot easy\b'', r''\btricky\b'', r''\bchalleng'',
        r''\bexception\b'', r''\boccasionally\b'', r''\brarely\b'',
        r''\bnot every\b'', r''\bfew losses\b'', r''\bmost satisfying\b''
    ]
    found = [p for p in limitation_markers if re.search(p, wa_text)]
    fails = []
    if not found:
        fails.append((''35'', ''Why Ashridge block has no honest qualification'',
                       ''Add at least one admission or limitation specific to this variety (E4)''))
    return found, fails


def check_hedge_density(body_plain, body_wc):
    """CHECK 36: Hedge word density (E5). Target: <4/1000w."""
    count = 0
    found = []
    for pattern in HEDGE_WORDS:
        matches = re.findall(pattern, body_plain, re.IGNORECASE)
        count += len(matches)
        if matches:
            found.extend(matches)
    rate = (count / body_wc * 1000) if body_wc > 0 else 0
    fails = []
    if rate > 8:
        fails.append((''36'', f''{count} hedge words ({rate:.1f}/1000w)'',
                       ''FAIL — rewrite with direct statements (E5)''))
    elif rate > 4:
        fails.append((''36'', f''{count} hedge words ({rate:.1f}/1000w)'',
                       ''FLAG — reduce hedging, commit to claims you are confident about (E5)''))
    return count, rate, found, fails


def check_spec_hook(html, category=''''):
    """CHECK 37: Spec panel hook quality (E6).
    Flags variety lines that read as bare data strings.
    PERENNIAL EXEMPTION: For perennial categories (salvia, foliage, herbaceous),
    the variety line is name-only by design (SP-P1). Skip this check for perennials."""
    if category.lower() in (''salvia'', ''foliage'', ''herbaceous'', ''perennial''):
        return []  # SP-P1 exemption — hook moves to first H2 sentence
    m = re.search(r''<strong>Variety:</strong>\s*(.*?)</li>'', html)
    if not m:
        return [(''37'', ''No variety line found'', ''Cannot check spec hook'')]
    variety_line = strip_html(m.group(1)).strip()
    data_patterns = [r''pruning group \d'', r''group \d'', r''evergreen'',
                     r''deciduous'', r''scented'', r''winter.flowering'',
                     r''summer.flowering'', r''spring.flowering'']
    residue = variety_line.lower()
    for p in data_patterns:
        residue = re.sub(p, '''', residue)
    residue = re.sub(r''[,\-–—]'', '' '', residue)
    residue = re.sub(r''\b(?:and|the|a|an|with|in|for|from|to|of)\b'', '''', residue)
    name_match = re.match(r''^([^,–—]+)'', variety_line)
    if name_match:
        for w in name_match.group(1).split():
            residue = residue.replace(w.lower(), '''')
    residue = residue.strip()
    fails = []
    if len(residue.split()) < 3:
        fails.append((''37'', f''Spec variety line may lack a selling hook: "{variety_line}"'',
                       ''Add a phrase with character — this is the first thing the customer reads (E6)''))
    return fails


def check_wa_specificity(html, variety_name):
    """CHECK 38: Why Ashridge plant-specificity (E7).
    Flags blocks that contain only generic nursery facts."""
    wa_match = re.search(
        r''<h2>(?:Why (?:Ashridge|Buy)[^<]*|From Our Nursery[^<]*|Raised at[^<]*|About Your Plant)</h2>(.*?)(?=<h2>|$)'',
        html, re.DOTALL | re.IGNORECASE)
    if not wa_match:
        return [(''38'', ''No Why Ashridge block found'', '''')]
    wa_text = strip_html(wa_match.group(1)).lower()
    specific_markers = [
        r''\b(?:this|these) (?:variety|clematis|wisteria|honeysuckle|jasmine|plant)'',
        r''\b(?:root|propagat|cutting|graft)\w* (?:willingly|easily|readily|difficult|tricky)'',
        r''\bfew losses\b'', r''\bgive us\b'', r''\bmost satisfying\b'',
        r''\bbuy in\b'', r''\bbought in\b'', r''\bin extremis\b'',
        r''\bdifficult (?:to|clematis|plant)\b'',
    ]
    genus_words = [w.lower() for w in variety_name.split() if len(w) > 3]
    name_present = any(w in wa_text for w in genus_words)
    marker_found = any(re.search(p, wa_text) for p in specific_markers)
    fails = []
    if not marker_found and not name_present:
        fails.append((''38'', ''Why Ashridge block appears generic — no plant-specific production detail'',
                       ''Add at least one fact about producing THIS variety at Ashridge (E7)''))
    return fails


def check_noun_echo(body_plain, variety_name):
    """CHECK 39: Noun echo within 15-word window (E8).
    Flags repeated nouns where a pronoun would be more natural."""
    exempt = {w.lower() for w in variety_name.split() if len(w) > 2}
    exempt.update([''clematis'', ''wisteria'', ''honeysuckle'', ''jasmine'', ''ivy'',
                   ''passion'', ''flower'', ''virginia'', ''creeper'', ''hydrangea''])
    words = body_plain.split()
    echoes = []
    for i, word in enumerate(words):
        w = re.sub(r''[.,;:!?\''"()—–]'', '''', word).lower()
        if len(w) < 4 or w in exempt:
            continue
        window = words[i+1:i+16]
        for j, w2 in enumerate(window):
            w2_clean = re.sub(r''[.,;:!?\''"()—–]'', '''', w2).lower()
            if w2_clean == w:
                context_start = max(0, i-3)
                context_end = min(len(words), i+j+4)
                context = '' ''.join(words[context_start:context_end])
                echoes.append((w, context))
                break
    seen = set()
    unique_echoes = []
    for noun, ctx in echoes:
        if noun not in seen:
            seen.add(noun)
            unique_echoes.append((noun, ctx))
    fails = []
    if len(unique_echoes) > 2:
        examples = ''; ''.join([f''"{n}" in "...{c}..."'' for n, c in unique_echoes[:3]])
        fails.append((''39'', f''{len(unique_echoes)} noun echoes in body copy'',
                       f''Replace repeated nouns with pronouns where referent is clear (E8). Examples: {examples}''))
    return unique_echoes, fails


def check_visual_detail(body_plain):
    """CHECK 40: Visual/physical detail presence (E9). Informational."""
    markers = []
    sensory = [r''\bsatin\b'', r''\bvelvety?\b'', r''\bsilky?\b'', r''\bglossy\b'',
               r''\bwaxy\b'', r''\bwaft\b'', r''\bperfume\b'', r''\bfragran'',
               r''\bcatches the (?:light|eye|sun)\b'', r''\bstop.{0,5}(?:passers|people|traffic)\b'',
               r''\bsmell\b'', r''\btaste\b'', r''\btouch\b'']
    for p in sensory:
        if re.search(p, body_plain, re.IGNORECASE):
            markers.append(f''sensory: {p}'')
    scale = re.findall(r''\b(?:floor|storey|stories|roof|window|door|shed|fence|pergola)\b'', body_plain, re.IGNORECASE)
    if scale: markers.append(f''scale refs: {len(scale)}'')
    return markers  # Informational only


def check_editorial_opinion(body_plain):
    """CHECK 41: Editorial opinion presence (E11).
    Flags PDPs with no editorial position."""
    opinion_markers = [
        r''\bin our experience\b'', r''\bwe (?:find|prefer|think|recommend|believe)\b'',
        r''\bthe best (?:way|method|approach|time)\b'',
        r''\ba better (?:choice|option|alternative)\b'',
        r''\bwill disappoint\b'', r''\bdon\''t try\b'', r''\bavoid\b'',
        r''\bdespite what\b'', r''\bcontrary to\b'', r''\bunlike the (?:textbook|book)'',
        r''\bin my experience\b'', r''\bwe have found\b'',
        r''\bwe would\b'', r''\bwe suggest\b'',
        r''\bperforms better\b'', r''\bat its best\b'',
        r''\bnot (?:a plant|suitable|the right)\b''
    ]
    found = [p for p in opinion_markers if re.search(p, body_plain, re.IGNORECASE)]
    fails = []
    if not found:
        fails.append((''41'', ''No editorial opinion detected in body copy'',
                       ''Add at least one recommendation, preference, or experience-based judgment (E11)''))
    return found, fails


def check_batch_voice_score(pdp_results):
    """CHECK 42: Batch-level voice score (E1-E11 composite).
    pdp_results: dict of {filename: {check_num: passed_bool}}
    Run after all per-PDP checks complete."""
    scores = {}
    for fname, checks in pdp_results.items():
        passed = sum(1 for v in checks.values() if v)
        scores[fname] = passed
    avg = sum(scores.values()) / len(scores) if scores else 0
    fails = []
    if avg < 4:
        fails.append((''42'', f''Batch voice score {avg:.1f}/11'',
                       ''HIGH — most PDPs lack editorial voice. Review E1–E11 compliance.''))
    elif avg < 6:
        fails.append((''42'', f''Batch voice score {avg:.1f}/11'',
                       ''MEDIUM — several PDPs need stronger editorial voice.''))
    low_scorers = [(f, s) for f, s in scores.items() if s < 4]
    for f, s in low_scorers:
        fails.append((''42'', f''{f}: {s}/11'', ''Individual PDP below minimum voice threshold''))
    return scores, avg, fails
```

```python
def run_claude_test(pdps):
    """Run CT v3.17 on all PDPs or guides. Returns list of result dicts."""
    results = []
    
    # Auto-detect content type from first file
    first_html = list(pdps.values())[0]
    content_type = detect_content_type(first_html)
    print(f"Content type detected: {content_type.upper()}\n")
    
    print(f"{''File'':<32} {''H2'':>3} {''Em'':>6} {''CV'':>5} {''Vocab'':>14} {''ItIs'':>4} {''Self'':>4} {''Dup'':>4} {''Hdg'':>4} {''Snip'':>4} {''KwD'':>4} {''Alt'':>4} {''FK'':>5} {''¶Ln'':>4} {''Result'':>7}")
    print(''-'' * 125)
    
    for filename, html in pdps.items():
        ctype = detect_content_type(html)
        variety = extract_variety_name(html) if ctype == ''pdp'' else filename.replace(''.html'','''')
        plain = strip_html(html)
        body = get_body_copy(html) if ctype == ''pdp'' else html
        body_plain = strip_html(body)
        wc = len(body_plain.split())
        total_wc = len(plain.split())
        
        # Run all checks
        h2_text, h2_ok = check_h2(html, variety) if ctype == ''pdp'' else (''N/A'', True)
        em_count, em_rate = check_emdash(body_plain, wc)
        
        para_wcs = get_body_paragraphs(html) if ctype == ''pdp'' else [len(p.split()) for p in re.findall(r''<p>(.*?)</p>'', html, re.DOTALL) if len(strip_html(p).split()) > 5]
        cv = statistics.stdev(para_wcs) / statistics.mean(para_wcs) if len(para_wcs) >= 2 else 0
        
        banned, flagged = check_vocab(body_plain)
        it_is = check_it_is(body_plain)
        self_ref = check_self_ref(body_plain)
        dupes = check_duplicate_links(html)
        faq_count = len(re.findall(r''<h3>'', html))
        
        # CHECK 15: Heading keyword relevance
        heading_fails = check_heading_keywords(html, ctype, variety)
        
        # CHECK 16: Snippet-ready structure
        snippet_fails = check_snippet_readiness(html, ctype)
        
        # CHECK 17: Keyword phrase density
        density_fails = check_keyword_density(html, ctype)
        
        # CHECK 18: Image alt text
        alt_fails = check_image_alt(html)
        
        # CHECK 19: Readability score
        fk_grade, fk_result = check_readability(html)
        
        # CHECK 20: Paragraph length
        para_fails = check_paragraph_length(html)
        
        # CHECKs 28/29/30/31: Additional content quality (per-PDP)
        fav_fails = check_favourites(body_plain) if ctype == ''pdp'' else []
        para_opener_fails = check_para_opener_repetition(html) if ctype == ''pdp'' else []
        filler_fails = check_generic_filler(body_plain)
        sent_rep_fails = check_sentence_opener_repetition(html) if ctype == ''pdp'' else []
        
        # CHECKs 32–42: Editorial voice (per-PDP, PDP-only)
        if ctype == ''pdp'':
            anecdote_markers, anecdote_fails = check_personal_anecdote(body_plain)
            short_count, frag_count, variation_fails = check_sentence_variation(body_plain)
            colloquial_markers = check_colloquial_voice(body_plain)
            limitation_found, limitation_fails = check_honest_limitation(html)
            hedge_count, hedge_rate, hedge_found, hedge_fails = check_hedge_density(body_plain, wc)
            spec_hook_fails = check_spec_hook(html)
            wa_spec_fails = check_wa_specificity(html, variety)
            echo_list, echo_fails = check_noun_echo(body_plain, variety)
            visual_markers = check_visual_detail(body_plain)
            opinion_found, opinion_fails = check_editorial_opinion(body_plain)
            # Track voice score per-PDP for CHECK 42
            voice_passes = {
                ''E1'': len(anecdote_markers) > 0,
                ''E2'': short_count > 0 or frag_count > 0,
                ''E3'': len(colloquial_markers) > 0,
                ''E4'': len(limitation_found) > 0,
                ''E5'': hedge_rate <= 4,
                ''E6'': len(spec_hook_fails) == 0,
                ''E7'': len(wa_spec_fails) == 0,
                ''E8'': len(echo_list) <= 2,
                ''E9'': len(visual_markers) > 0,
                ''E10'': True,  # Botanical accuracy — manual only, default pass
                ''E11'': len(opinion_found) > 0,
            }
            voice_score = sum(1 for v in voice_passes.values() if v)
        else:
            anecdote_fails = variation_fails = limitation_fails = []
            hedge_fails = spec_hook_fails = wa_spec_fails = echo_fails = opinion_fails = []
            voice_passes = {}
            voice_score = None
        
        # Determine result
        fails = []
        flags = []
        if ctype == ''pdp'' and not h2_ok: fails.append(''H2'')
        if em_rate > EM_DASH_FAIL: fails.append(''Em'')
        elif em_rate > EM_DASH_FLAG: flags.append(''Em'')
        if banned: fails.append(''Vocab'')
        if it_is > IT_IS_THRESHOLD: fails.append(''ItIs'')
        if self_ref: fails.append(''Self'')
        if dupes: fails.append(''Dupes'')
        if heading_fails: fails.append(''Hdg'')
        if snippet_fails: fails.append(''Snip'')
        if density_fails: flags.append(''KwD'')
        if alt_fails: flags.append(''Alt'')
        if fk_result == ''FAIL'': fails.append(''FK'')
        elif fk_result == ''FLAG'': flags.append(''FK'')
        # CHECK 20: page-level para flag only (individual paras are informational)
        page_para_flags = [f for f in para_fails if f[0] == ''20-page'']
        if page_para_flags: flags.append(''¶Ln'')
        
        if fav_fails: fails.append(''Fav'')
        if filler_fails: fails.append(''Fill'')
        if para_opener_fails: flags.append(''POp'')
        if sent_rep_fails: flags.append(''SRp'')
        
        # Voice checks (CHECKs 32–42) — PDPs only
        if ctype == ''pdp'':
            if anecdote_fails: flags.append(''E1'')
            if variation_fails: flags.append(''E2'')
            if limitation_fails: flags.append(''E4'')
            if hedge_fails:
                if hedge_rate > 8: fails.append(''Hdg'')
                else: flags.append(''Hdg'')
            if spec_hook_fails: flags.append(''E6'')
            if wa_spec_fails: flags.append(''E7'')
            if echo_fails: flags.append(''E8'')
            if opinion_fails: flags.append(''E11'')
        
        vocab_str = '',''.join(banned) if banned else ('',''.join(f''~{w}'' for w in flagged) if flagged else ''—'')
        em_str = f"{em_rate:.1f}" + ("!" if em_rate > EM_DASH_FAIL else ("~" if em_rate > EM_DASH_FLAG else ""))
        display_name = variety[:30] if ctype == ''pdp'' else filename[:30]
        
        print(f"{display_name:<32} {''✓'' if h2_ok else ''✗'':>3} {em_str:>6} {cv:>5.2f} {vocab_str:>14} {it_is:>4} {''✗'' if self_ref else ''✓'':>4} {len(dupes):>4} {len(heading_fails):>4} {len(snippet_fails):>4} {len(density_fails):>4} {len(alt_fails):>4} {fk_grade:>5.1f} {len(para_fails):>4} {result:>7}")
        
        # Print heading detail if failures found
        if heading_fails:
            for h_text, reason in heading_fails:
                print(f"  └─ Hdg FAIL: \"{h_text}\" — {reason}")
        
        # Print snippet detail if failures found
        if snippet_fails:
            for check_id, context, reason in snippet_fails:
                print(f"  └─ Snip FAIL ({check_id}): \"{context}\" — {reason}")
        
        # Print keyword density detail if flags found
        if density_fails:
            for check_id, context, reason in density_fails:
                print(f"  └─ KwD FLAG ({check_id}): {context} — {reason}")
        
        # Print image alt detail if flags found
        if alt_fails:
            for check_id, context, reason in alt_fails:
                print(f"  └─ Alt FLAG ({check_id}): {context} — {reason}")
        
        # Print readability detail if flagged/failed
        if fk_result in (''FLAG'', ''FAIL''):
            print(f"  └─ FK {fk_result}: grade {fk_grade:.1f} — {''review long sentences'' if fk_result == ''FLAG'' else ''rewrite needed''}")
        
        # Print paragraph length detail (show up to 5 worst)
        if para_fails:
            for check_id, context, reason in para_fails[:5]:
                label = ''PAGE FLAG'' if check_id == ''20-page'' else ''FLAG''
                print(f"  └─ ¶Ln {label} ({check_id}): {context} — {reason}")
            if len(para_fails) > 5:
                print(f"  └─ ... and {len(para_fails)-5} more")
        
        # Print new check detail
        for check_id, context, reason in fav_fails:
            print(f"  └─ FAIL ({check_id}): {context} — {reason}")
        for check_id, context, reason in filler_fails:
            print(f"  └─ FAIL ({check_id}): {context} — {reason}")
        for check_id, context, reason in para_opener_fails:
            print(f"  └─ FLAG ({check_id}): {context} — {reason}")
        for check_id, context, reason in sent_rep_fails:
            print(f"  └─ FLAG ({check_id}): {context} — {reason}")
        
        # Print voice check detail (CHECKs 32–42, PDP only)
        if ctype == ''pdp'':
            for check_id, context, reason in anecdote_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            for check_id, context, reason in variation_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            for check_id, context, reason in limitation_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            for check_id, context, reason in hedge_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            for f in spec_hook_fails:
                print(f"  └─ Voice ({f[0]}): {f[1]} — {f[2]}")
            for f in wa_spec_fails:
                print(f"  └─ Voice ({f[0]}): {f[1]} — {f[2]}")
            for check_id, context, reason in echo_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            for check_id, context, reason in opinion_fails:
                print(f"  └─ Voice ({check_id}): {context} — {reason}")
            print(f"  └─ Voice score: {voice_score}/11 ({'', ''.join(k for k,v in voice_passes.items() if not v) or ''all pass''})")
        
        results.append({
            ''filename'': filename, ''variety'': variety, ''content_type'': ctype,
            ''h2_text'': h2_text, ''h2_ok'': h2_ok,
            ''em_rate'': em_rate, ''cv'': cv,
            ''banned'': banned, ''flagged'': flagged,
            ''it_is'': it_is, ''self_ref'': self_ref,
            ''dupes'': dupes, ''faq_count'': faq_count,
            ''heading_fails'': heading_fails,
            ''snippet_fails'': snippet_fails,
            ''density_fails'': density_fails,
            ''alt_fails'': alt_fails,
            ''fk_grade'': fk_grade, ''fk_result'': fk_result,
            ''para_fails'': para_fails,
            ''wc'': wc, ''total_wc'': total_wc,
            ''result'': result, ''fails'': fails, ''flags'': flags,
            ''voice_score'': voice_score, ''voice_passes'': voice_passes,
        })
    
    # Summary
    passes = sum(1 for r in results if r[''result''] == ''PASS'')
    flags_count = sum(1 for r in results if r[''result''] == ''FLAG'')
    fails_count = sum(1 for r in results if r[''result''] == ''FAIL'')
    print(f"\n{passes} PASS, {flags_count} FLAG, {fails_count} FAIL out of {len(results)}")
    
    # Batch voice score (CHECK 42) — PDP batches of 2+ only
    pdp_results_for_voice = {r[''filename'']: r[''voice_passes''] for r in results if r[''content_type''] == ''pdp'' and r[''voice_passes'']}
    if len(pdp_results_for_voice) >= 2:
        voice_scores, voice_avg, voice_fails = check_batch_voice_score(pdp_results_for_voice)
        print(f"\n--- VOICE SCORE (CHECK 42) ---")
        print(f"Batch average: {voice_avg:.1f}/11")
        for fname, score in voice_scores.items():
            status = ''LOW'' if score < 4 else (''OK'' if score < 6 else ''GOOD'')
            print(f"  {fname[:40]:<42} {score}/11  {status}")
        for check_id, context, reason in voice_fails:
            print(f"  └─ {reason}: {context}")
    
    return results
```

---

### CHECKs 43–44 — Style Compliance

```python
def check_contractions(soup):
    """CHECK 43: Contractions vs formal negatives (WARN level).
    
    Master Rules §3 Voice: formal negatives are a reliable AI tell.
    Scans body <p> tags for ''do not'', ''will not'', ''cannot'', ''does not'', ''should not''.
    Excludes FAQ answers (which may quote formal phrasing) and spec panels.
    """
    formal_negatives = [''do not'', ''will not'', ''cannot'', ''does not'', ''should not'']
    flags = []
    for p in soup.find_all(''p''):
        # Skip if inside FAQ section (after <h2>Frequently Asked Questions</h2>)
        # Simple heuristic: check if p is preceded by an h3 (FAQ question)
        text = p.get_text().lower()
        for neg in formal_negatives:
            if neg in text:
                snippet = p.get_text()[:80]
                flags.append((neg, snippet))
    return flags  # Each (formal_negative, snippet) — WARN level


def check_self_notes(soup):
    """CHECK 44: Self-notes in body text (FAIL level).
    
    Master Rules §12: internal production notes must be HTML comments or omitted.
    Scans <p> and <li> content for patterns that indicate self-notes rendered as body text.
    """
    patterns = [''remember to'', ''need to add'', ''todo'', ''check this'', 
                ''add later'', ''note to self'', ''need to check'', ''still need'']
    fails = []
    for tag in soup.find_all([''p'', ''li'']):
        text = tag.get_text().lower()
        for pattern in patterns:
            if pattern in text:
                snippet = tag.get_text()[:80]
                fails.append((pattern, snippet))
    return fails  # Each (pattern, snippet) — FAIL level
```

**Runner integration:** Add to the per-PDP check sequence after CHECK 42:

```python
    # CHECK 43 — Contractions (WARN)
    contraction_flags = check_contractions(soup)
    if contraction_flags:
        for neg, snippet in contraction_flags:
            print(f"  CHECK 43 WARN: formal negative ''{neg}'' — use contraction. \"{snippet}...\"")
            results[''flags''].append((''CHECK 43'', fname, f"formal negative ''{neg}''"))

    # CHECK 44 — Self-notes (FAIL)
    self_note_fails = check_self_notes(soup)
    if self_note_fails:
        for pattern, snippet in self_note_fails:
            print(f"  CHECK 44 FAIL: self-note in body text — ''{pattern}''. \"{snippet}...\"")
            results[''fails''].append((''CHECK 44'', fname, f"self-note ''{pattern}''"))
```

---

### CHECK 45 — SEO Title Tag Quality

```python
def check_title_tag(seo_title, variety_name='''', page_type=''pdp''):
    """CHECK 45: SEO title tag — writing for Google preservation.
    
    Master Rules §12: 30-60 chars, 5-10 words, no pipes/brackets/parentheses,
    keyword leads, brand at end or omit. Source: McAlpin study (April 2025).
    """
    issues = []
    if not seo_title:
        return [(''45'', ''No SEO title found'', ''FAIL'')]
    
    char_count = len(seo_title)
    word_count = len(seo_title.split())
    
    # Character count thresholds
    if char_count < 25:
        issues.append((''45'', f''Title too short ({char_count} chars): "{seo_title}"'',
                       ''FAIL — almost certain Google rewrite. Target 30-60 chars''))
    elif char_count < 30:
        issues.append((''45'', f''Title short ({char_count} chars): "{seo_title}"'',
                       ''WARN — borderline, likely rewrite. Target 30-60 chars''))
    elif char_count > 70:
        issues.append((''45'', f''Title too long ({char_count} chars): "{seo_title}"'',
                       ''FAIL — truncation and rewrite. Target 30-60 chars''))
    elif char_count > 60:
        issues.append((''45'', f''Title long ({char_count} chars): "{seo_title}"'',
                       ''WARN — may be rewritten. Target 30-60 chars''))
    
    # Pipe character
    if ''|'' in seo_title:
        issues.append((''45'', f''Pipe character in title: "{seo_title}"'',
                       ''WARN — Google strips template punctuation''))
    
    # Brackets and parentheses
    if re.search(r''[\[\]\(\)]'', seo_title):
        issues.append((''45'', f''Brackets/parentheses in title: "{seo_title}"'',
                       ''WARN — Google strips these in 76% of rewrites''))
    
    # Brand in first half
    brand_words = [''ashridge'', ''ashridge trees'']
    first_half = seo_title[:len(seo_title)//2].lower()
    for brand in brand_words:
        if brand in first_half:
            issues.append((''45'', f''Brand name in first half of title: "{seo_title}"'',
                           ''WARN — Google removes brand names in 63% of rewrites''))
            break
    
    # Primary keyword (variety name) absent
    if variety_name and variety_name.lower() not in seo_title.lower():
        issues.append((''45'', f''Primary keyword "{variety_name}" absent from title: "{seo_title}"'',
                       ''FAIL — title must contain primary keyword''))
    
    return issues
```

**Runner integration:** Add to the per-PDP check sequence after CHECK 44:

```python
    # CHECK 45 — SEO title tag (WARN/FAIL)
    if seo_title:
        title_issues = check_title_tag(seo_title, variety_name, page_type)
        for check_id, detail, level in title_issues:
            if ''FAIL'' in level:
                print(f"  CHECK 45 FAIL: {detail}")
                results[''fails''].append((''CHECK 45'', fname, detail))
            else:
                print(f"  CHECK 45 WARN: {detail}")
                results[''flags''].append((''CHECK 45'', fname, detail))
```

---

## 3. LINK VALIDATION

### 3.1 Standard links per category

**Dahlias:**
- Grow guide: `/blogs/garden-plants/how-to-grow-dahlias`
- Pots guide: `/blogs/garden-plants/dahlias-in-pots`
- Overwinter guide: `/blogs/garden-plants/overwintering-dahlias`
- Collection pages: `/collections/dahlia-tubers`, `/collections/decorative-dinnerplate-dahlia-tubers`, `/collections/ball-dahlia-tubers`, `/collections/cactus-dahlia-tubers`

**Sweet peas:**
- Grow guide: `/blogs/bedding/how-to-grow-sweet-peas`
- Collection: `/collections/sweet-pea-plants`

**Add more per category as needed.**

### 3.2 Link validation script

```python
def validate_links(pdps, category=''dahlia''):
    """Check all internal links across the PDP set"""
    
    # Collect all outgoing links per PDP
    all_links = {}
    all_product_links = Counter()
    
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        links = re.findall(r''href="(/[^"]+)"'', html)
        product_links = [l for l in links if l.startswith(''/products/'')]
        collection_links = [l for l in links if l.startswith(''/collections/'')]
        blog_links = [l for l in links if l.startswith(''/blogs/'')]
        
        all_links[variety] = {
            ''products'': product_links,
            ''collections'': collection_links,
            ''blogs'': blog_links,
            ''total'': len(links),
            ''product_count'': len(set(product_links)),
        }
        
        for l in product_links:
            all_product_links[l] += 1
    
    # Report
    print("=== LINKS PER PDP ===")
    for variety, data in all_links.items():
        flag = " ⚠️" if data[''product_count''] < 3 or data[''product_count''] > 6 else ""
        print(f"  {variety:<22} {data[''product_count'']} variety links, {len(data[''collections''])} collection, {len(data[''blogs''])} guide{flag}")
    
    print("\n=== INCOMING LINKS PER VARIETY ===")
    for url, count in all_product_links.most_common():
        short = url.split(''/'')[-1]
        flag = " ← overlinked" if count > 6 else (" ← underlinked" if count <= 1 else "")
        print(f"  {count:>2}x  {short}{flag}")
    
    # CHECK 12: Link concentration
    total_links = sum(all_product_links.values())
    top_20_pct = max(1, len(all_product_links) // 5)
    top_urls = all_product_links.most_common(top_20_pct)
    top_links = sum(c for _, c in top_urls)
    concentration = top_links / total_links if total_links else 0
    print(f"\n  CHECK 12: Top {top_20_pct} URLs ({top_20_pct}/{len(all_product_links)}) receive {concentration:.0%} of links", end="")
    print(" ← FAIL" if concentration > 0.4 else " ← OK")
    
    return all_links, all_product_links
```

---

## 4. PHRASE REPETITION

```python
def check_phrase_repetition(pdps):
    """Find sentences that appear on 2+ PDPs (excluding Why Ashridge block)"""
    
    # Extract sentences per PDP (body + FAQs, excluding Why Ashridge)
    pdp_sentences = {}
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        body = get_body_copy(html)
        plain = strip_html(body)
        # Split into sentences (rough)
        sents = [s.strip() for s in re.split(r''[.!?]+'', plain) if len(s.strip()) > 20]
        pdp_sentences[variety] = sents
    
    # Find cross-PDP repeats
    all_sents = {}
    for variety, sents in pdp_sentences.items():
        for s in sents:
            normalised = '' ''.join(s.lower().split())
            if normalised not in all_sents:
                all_sents[normalised] = []
            all_sents[normalised].append(variety)
    
    repeats = {s: varieties for s, varieties in all_sents.items() if len(varieties) > 1}
    
    if repeats:
        print(f"=== REPEATED SENTENCES ({len(repeats)} found) ===")
        for sent, varieties in sorted(repeats.items(), key=lambda x: -len(x[1])):
            print(f"\n  [{len(varieties)}x] {sent[:80]}...")
            for v in varieties:
                print(f"       → {v}")
    else:
        print("No cross-PDP sentence repetition found.")
    
    return repeats
```

---

## 5. CONTENT QUALITY SCORING

### 5.1 Category-specific scoring — Dahlias

```python
def score_dahlias(pdps):
    """Score dahlia PDPs on category-specific quality criteria"""
    
    print("=== DAHLIA QUALITY SCORING ===\n")
    
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        plain = strip_html(html)
        body = get_body_copy(html)
        body_plain = strip_html(body)
        
        score = 0
        max_score = 8
        notes = []
        
        # 1. Origin/breeder mentioned
        if re.search(r''(?:bred|raised|introduced|seedling|sport|origin)'', body_plain, re.IGNORECASE):
            score += 1
        else:
            notes.append(''No origin/breeder'')
        
        # 2. Type classification in spec panel
        if re.search(r''<strong>Type:</strong>'', html):
            score += 1
        else:
            notes.append(''No type classification'')
        
        # 3. AGM status addressed
        if re.search(r''AGM'', plain):
            score += 1
        else:
            notes.append(''AGM not mentioned'')
        
        # 4. Distinctive H2
        h2s = re.findall(r''<h2>(.*?)</h2>'', html)
        if h2s and not h2s[0].lower().startswith(''about ''):
            score += 1
        else:
            notes.append(''Generic H2'')
        
        # 5. Word count in range (700-1100w per Master Rules v8.38 universal standard)
        wc = len(plain.split())
        if 700 <= wc <= 1100:
            score += 1
        else:
            notes.append(f''Word count {wc} outside 700-1100'')
        
        # 6. Container FAQ — category-aware (v3.7 fix)
        # Some categories restrict container FAQs to approved varieties only.
        # Sweet peas: 15% target (~6 PDPs). Other categories: populate per category ref.
        CONTAINER_APPROVED = {
            ''sweet_pea'': [''Albutt Blue'', ''Bristol'', ''Erewhon'', ''Jilly'', ''Matucana'', ''Turquoise Lagoon''],
            # Add other categories as needed:
            # ''dahlia'': [...],
            # ''lavender'': [...],
            # ''cosmos'': [...],
        }
        approved = CONTAINER_APPROVED.get(category, None)
        has_container_faq = bool(re.search(r''<h3>[^<]*(pot|container|grow.*in a)[^<]*</h3>'', html, re.IGNORECASE))
        has_container_mention = bool(re.search(r''pot|container'', body_plain, re.IGNORECASE))
        if approved is not None:  # category has a restricted list
            if variety in approved:
                if has_container_mention:
                    score += 1
                else:
                    notes.append(''MISSING: Container guidance (approved variety)'')
            else:
                if has_container_faq:
                    notes.append(''FLAG: Container FAQ present — variety not on approved list (see cat ref §4a)'')
                else:
                    score += 1  # correct: no container FAQ on non-approved variety
        else:
            # No restriction defined for this category — original logic
            if has_container_mention:
                score += 1
            else:
                notes.append(''No container guidance'')
        
        # 7. FAQ variety (5+ unique questions)
        faq_count = len(re.findall(r''<h3>'', html))
        if faq_count >= 5:
            score += 1
        else:
            notes.append(f''Only {faq_count} FAQs'')
        
        # 8. Companion links to in-range varieties
        product_links = re.findall(r''href="/products/([^"]+)"'', html)
        if len(set(product_links)) >= 3:
            score += 1
        else:
            notes.append(f''Only {len(set(product_links))} variety links'')
        
        rating = "★★★" if score >= 7 else ("★★" if score >= 5 else "★")
        issues = ''; ''.join(notes) if notes else ''Clean''
        print(f"  {rating} {variety:<22} {score}/{max_score}  {issues}")
```

### 5.2 Category-specific scoring — Sweet Peas

```python
def score_sweet_peas(pdps):
    """Score sweet pea PDPs on category-specific quality criteria"""
    
    # NSPS classification mapping (from NSPS Classification Reference)
    NSPS = {
        "Albutt Blue": ("Semi-Grandiflora", None),
        "Almost Black": ("Modern Grandiflora", None),
        "America": ("Old-Fashioned", None),
        "Anniversary": ("Spencer", "15"),
        "Ballerina Blue": ("Spencer", "9a"),
        "Black Knight": ("Old-Fashioned", None),
        "Blue Velvet": ("Spencer", "9"),
        "Bobby''s Girl": ("Spencer", None),
        "Bramdean": ("Old-Fashioned", None),
        "Bristol": ("Spencer", "9b"),
        "Brook Hall": ("Spencer", None),
        "Cathy": ("Semi-Grandiflora", None),
        "Charlie''s Angel": ("Spencer", "9b"),
        "Erewhon": ("Modern Grandiflora", None),
        "Flora Norton": ("Old-Fashioned", None),
        "Gwendoline": ("Spencer", "4a"),
        "Heathcliff": ("Modern Grandiflora", None),
        "Heaven Scent": ("Spencer", "11a"),
        "Henry Thomas": ("Spencer", "3b"),
        "Jilly": ("Spencer", "2"),
        "Just Julia": ("Spencer", "9a"),
        "King''s High Scent": ("Modern Grandiflora", None),
        "Lord Nelson": ("Old-Fashioned", None),
        "Matucana": ("Modern Grandiflora", None),
        "Millennium": ("Spencer", "3b"),
        "Mollie Rilstone": ("Spencer", "15a"),
        "Mrs Collier": ("Old-Fashioned", None),
        "Noel Sutton": ("Spencer", "9a"),
        "Our Harry": ("Spencer", "9a"),
        "Pink Pearl": ("Spencer", "10"),
        "Promise": ("Spencer", "16a"),
        "Restormel": ("Spencer", "3"),
        "Turquoise Lagoon": (None, None),
        "Valerie Harrod": ("Spencer", "13"),
        "White Frills": ("Spencer", "1"),
        "White Supreme": ("Spencer", "1"),
        "Windsor": ("Spencer", "5"),
    }
    
    print("  SWEET PEA CATEGORY CHECKS")
    print("  " + "=" * 50)
    
    for pdp in pdps:
        variety = pdp.get(''variety'', ''Unknown'')
        html = pdp.get(''html'', '''')
        notes = []
        
        # 1. Show class line present
        if ''Show class:'' not in html:
            notes.append(''MISSING: Show class spec line'')
        
        # 2. NSPS type verification
        nsps_entry = NSPS.get(variety)
        if nsps_entry:
            nsps_type, nsps_class = nsps_entry
            if nsps_type:
                # Check spec panel Type line matches
                if nsps_type == "Old-Fashioned":
                    # We use "Grandiflora" in Type line for Old-Fashioned
                    if ''Grandiflora'' not in html or ''Modern Grandiflora'' in html.split(''Type:'')[1].split(''</li>'')[0] if ''Type:'' in html else True:
                        notes.append(f''CHECK: Type should be Grandiflora (NSPS: Old-Fashioned)'')
                elif nsps_type == "Spencer":
                    if ''Spencer'' not in html.split(''Type:'')[1].split(''</li>'')[0] if ''Type:'' in html else True:
                        notes.append(f''CHECK: Type should be Spencer'')
                elif nsps_type in ("Modern Grandiflora", "Semi-Grandiflora"):
                    if nsps_type not in html:
                        notes.append(f''CHECK: Type should be {nsps_type}'')
        
        # 3. Scent line present with Parsons rating
        if ''Scent:'' in html:
            scent_line = html.split(''Scent:'')[1].split(''</li>'')[0] if ''Scent:'' in html else ''''
            if ''/5'' not in scent_line and ''out of 5'' not in scent_line:
                notes.append(''FLAG: Scent line may lack Parsons rating'')
        else:
            notes.append(''MISSING: Scent spec line'')
        
        # 4. Growing guide link
        if ''/how-to-grow-sweet-peas'' not in html:
            notes.append(''MISSING: Growing guide link'')
        
        # 5. Collection link
        if ''/collections/sweet-pea-plants'' not in html:
            notes.append(''MISSING: Collection link in FAQ'')
        
        # 6. Body copy type accuracy — check for "Spencer" in body when NSPS says otherwise
        if nsps_entry and nsps_entry[0] and nsps_entry[0] != "Spencer":
            # Count "Spencer" mentions in body (not in spec panel)
            body_after_specs = html.split(''</ul>'')[1] if ''</ul>'' in html else html
            spencer_mentions = body_after_specs.lower().count(''spencer'')
            if spencer_mentions > 0:
                notes.append(f''WARNING: {spencer_mentions} "Spencer" mention(s) in body — variety is {nsps_entry[0]}'')
        
        # 7. Container FAQ distribution compliance (v3.7 addition)
        # Only 6 approved sweet pea varieties should carry a container FAQ.
        CONTAINER_APPROVED_SP = [''Albutt Blue'', ''Bristol'', ''Erewhon'', ''Jilly'', ''Matucana'', ''Turquoise Lagoon'']
        has_container_faq = bool(re.search(r''<h3>[^<]*(pot|container|grow.*in a)[^<]*</h3>'', html, re.IGNORECASE))
        if has_container_faq and variety not in CONTAINER_APPROVED_SP:
            notes.append(f''SWAP: Container FAQ present — {variety} not on approved list (max 6 PDPs: {", ".join(CONTAINER_APPROVED_SP)})'')
        elif not has_container_faq and variety in CONTAINER_APPROVED_SP:
            notes.append(f''MISSING: {variety} is approved for container FAQ but none found'')
        
        # Report
        status = "✅ PASS" if not notes else "⚠️ FLAGS"
        print(f"\n  {variety}: {status}")
        for n in notes:
            print(f"    → {n}")
```

---

## 6. PUTTING IT ALL TOGETHER

```python
def run_full_audit(category=''dahlia''):
    """Run the complete audit pipeline"""
    
    pdps = load_pdps()
    
    if not pdps:
        print("No HTML files found in /mnt/user-data/uploads")
        return
    
    print(f"=== PDP AUDIT: {category.upper()} ({len(pdps)} files) ===\n")
    
    # 1. Claude Test
    print("--- CLAUDE TEST v3.17 ---\n")
    ct_results = run_claude_test(pdps)
    
    # 2. Link validation
    print("\n--- LINK VALIDATION ---\n")
    links, incoming = validate_links(pdps, category)
    
    # 3. Phrase repetition
    print("\n--- PHRASE REPETITION ---\n")
    repeats = check_phrase_repetition(pdps)
    
    # 4. Content quality
    print(f"\n--- CONTENT QUALITY ---\n")
    if category == ''dahlia'':
        score_dahlias(pdps)
    elif category == ''sweet_pea'':
        score_sweet_peas(pdps)
    
    # 4a. CHECK 27b — Spec panel synonym-cluster repetition (batch-level)
    print("\n--- SPEC PANEL SYNONYM CHECK (CHECK 27b) ---\n")
    spec_texts = {}
    for filename, html in pdps.items():
        # Extract spec panel text only
        spec_match = re.search(r''<ul class="pdp-specs">(.*?)</ul>'', html, re.DOTALL | re.IGNORECASE)
        spec_texts[filename] = strip_html(spec_match.group(1)) if spec_match else ''''
    synonym_fails = check_spec_panel_synonyms(spec_texts)
    if synonym_fails:
        for cluster_name, terms, count, n, files in synonym_fails:
            print(f"  FLAG [{cluster_name}]: terms {terms} appear on {count}/{n} PDPs (>{int(0.6*n)}) — vary spec panel wording")
            for f in files[:5]:
                print(f"    → {f}")
    else:
        print("  ✓ Spec panel synonym variation looks good")
    
    # 5. Word count summary
    print("\n--- WORD COUNTS ---\n")
    for r in ct_results:
        print(f"  {r[''variety'']:<22} {r[''total_wc'']:>4}w total, {r[''wc'']:>4}w body, {r[''faq_count'']} FAQs")
    total = sum(r[''total_wc''] for r in ct_results)
    print(f"  {''TOTAL'':<22} {total:>4}w")
    
    return ct_results, links, incoming, repeats

# To run: run_full_audit(''dahlia'')
```

---

## 7. LINK FORMAT CHECK (BONUS)

Checks whether all internal links have the required `rel="noopener noreferrer" target="_blank"` attributes:

```python
def check_link_format(pdps):
    """Check all internal links have required attributes"""
    print("=== LINK FORMAT CHECK ===\n")
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        # Find all internal links
        all_links = re.findall(r''<a\s+[^>]*href="/[^"]*"[^>]*>'', html)
        missing = []
        for link in all_links:
            if ''rel="noopener noreferrer"'' not in link or ''target="_blank"'' not in link:
                href = re.search(r''href="([^"]*)"'', link)
                missing.append(href.group(1) if href else link)
        if missing:
            print(f"  {variety}: {len(missing)} links missing attributes")
            for m in missing[:5]:
                print(f"    → {m}")
            if len(missing) > 5:
                print(f"    ...and {len(missing)-5} more")
        else:
            print(f"  {variety}: ✓ all links formatted correctly")
```

---

## 7a. HYGIENE SCAN (for "Check the PDPs" trigger)

This section runs **only** when the trigger is "check the PDPs" (or a variant). It is not part of the standard "run the PDP audit" workflow. The hygiene scan catches issues outside the Claude Test and content quality checks — things that accumulate silently when slugs change, governance conventions evolve, or EXPERT comments are left behind.

### 7a.1 Stale URL slugs — within-category (HIGH)

```python
def check_stale_slugs(pdps, canonical_suffix):
    """Check all internal /products/ hrefs end with the canonical slug suffix.
    
    canonical_suffix: e.g. ''-sweet-pea-plants'', ''-cosmos-plants''
    """
    print("=== STALE URL SLUGS (WITHIN-CATEGORY) ===\n")
    stale_count = 0
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        product_links = re.findall(r''href="(/products/[^"]*)"'', html)
        stale = [href for href in product_links if not href.endswith(canonical_suffix)]
        if stale:
            stale_count += len(stale)
            print(f"  {variety}: {len(stale)} stale slug(s)")
            for s in stale:
                print(f"    → {s}")
        else:
            print(f"  {variety}: ✓ all product slugs current")
    print(f"\n  TOTAL STALE SLUGS: {stale_count}")
    return stale_count
```

### 7a.2 Stale URL slugs — cross-category (HIGH)

Checks all `/products/`, `/collections/`, and `/blogs/` hrefs against the hub redirect registers (currently `R_a_dahlia-301-redirect-table.md`; extensible to other categories). Catches links to products or guides that have been migrated to new slugs in another category — e.g. a sweet pea PDP still linking to an old dahlia type-specifier slug.

**How to run:** Load the redirect register(s) from the hub. Extract old→new slug pairs. Flag any href matching an old slug.

```python
def check_cross_category_slugs(pdps, redirect_registers):
    """Check /products/, /collections/, /blogs/ hrefs against cross-category redirect registers.
    
    redirect_registers: dict of {old_slug: new_slug} pairs compiled from hub redirect tables.
    e.g. {''/products/bishop-of-llandaff-peony-dahlia-tubers'': ''/products/bishop-of-llandaff-dahlia-tubers''}
    """
    print("=== STALE URL SLUGS (CROSS-CATEGORY) ===\n")
    stale_count = 0
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        all_hrefs = re.findall(r''href="(/(?:products|collections|blogs)/[^"]*)"'', html)
        stale = [(href, redirect_registers[href]) for href in all_hrefs if href in redirect_registers]
        if stale:
            stale_count += len(stale)
            print(f"  {variety}: {len(stale)} cross-category stale slug(s)")
            for old, new in stale:
                print(f"    → {old}")
                print(f"       should be: {new}")
        else:
            print(f"  {variety}: ✓ no cross-category stale slugs")
    print(f"\n  TOTAL CROSS-CATEGORY STALE SLUGS: {stale_count}")
    return stale_count
```

**Note:** If the redirect register is not available (hub files not loaded), skip with a warning — do not silently pass.

### 7a.3 Missing or misordered link attributes (MEDIUM)

This reuses the §7 `check_link_format` function. Additionally checks that `rel` appears before `target` in the attribute order:

```python
def check_link_attributes(pdps):
    """Check all internal links have rel before target, both present."""
    print("=== LINK ATTRIBUTE CHECK ===\n")
    issues = {}
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        all_links = re.findall(r''<a\s+[^>]*href="/[^"]*"[^>]*>'', html)
        file_issues = []
        for link in all_links:
            has_rel = ''rel="noopener noreferrer"'' in link
            has_target = ''target="_blank"'' in link
            if not has_rel or not has_target:
                href = re.search(r''href="([^"]*)"'', link)
                file_issues.append((''missing'', href.group(1) if href else link))
            elif has_rel and has_target:
                rel_pos = link.index(''rel='')
                target_pos = link.index(''target='')
                if target_pos < rel_pos:
                    href = re.search(r''href="([^"]*)"'', link)
                    file_issues.append((''misordered'', href.group(1) if href else link))
        if file_issues:
            issues[variety] = file_issues
            print(f"  {variety}: {len(file_issues)} issue(s)")
            for issue_type, href in file_issues[:5]:
                print(f"    → [{issue_type}] {href}")
        else:
            print(f"  {variety}: ✓")
    return issues
```

### 7a.4 Residual EXPERT/TODO comments (MEDIUM)

```python
def check_residual_comments(pdps):
    """Flag EXPERT or TODO comments in files not marked as -commented."""
    print("=== RESIDUAL COMMENTS ===\n")
    found = {}
    for filename, html in pdps.items():
        is_commented = ''-commented'' in filename
        expert = re.findall(r''<!--\s*EXPERT[:\s].*?-->'', html, re.DOTALL)
        todo = re.findall(r''<!--\s*TODO[:\s].*?-->'', html, re.DOTALL)
        comments = expert + todo
        if comments and not is_commented:
            variety = extract_variety_name(html)
            found[variety] = comments
            print(f"  {variety}: {len(comments)} residual comment(s) in non-commented file")
            for c in comments[:3]:
                preview = c[:80].replace(''\n'', '' '')
                print(f"    → {preview}...")
        elif comments and is_commented:
            variety = extract_variety_name(html)
            print(f"  {variety}: {len(comments)} comment(s) — file correctly flagged as -commented")
        else:
            variety = extract_variety_name(html)
            print(f"  {variety}: ✓ no residual comments")
    return found
```

### 7a.5 Old filenames in HTML (LOW)

```python
def check_old_filenames(pdps):
    """Flag references to deprecated naming conventions inside HTML content."""
    print("=== OLD FILENAME REFERENCES ===\n")
    # Patterns that suggest old naming conventions
    old_patterns = [
        (r''ashridge-pdp-'', ''Old ashridge- governance prefix (should be G1_/G2_/A_/R_/X_)''),
        (r''T1_ash-'', ''Old T1_ash- governance prefix (should be G1_)''),
        (r''T2_ash-'', ''Old T2_ash- governance prefix (should be G2_ or A_)''),
        (r''S1_ash-'', ''Old S1_ash- spoke prefix (should be G1_ for category references)''),
        (r''S1_dahlia-'', ''Old S1_dahlia- spoke prefix (should be G2_ for model PDPs)''),
        (r''ashridge-sweet-pea-category'', ''Old category reference filename''),
        (r''-seedling-plug-plants'', ''Old sweet pea slug suffix (should be -sweet-pea-plants)''),
    ]
    found = {}
    for filename, html in pdps.items():
        variety = extract_variety_name(html)
        file_issues = []
        for pattern, description in old_patterns:
            matches = re.findall(pattern, html)
            if matches:
                file_issues.append((description, len(matches)))
        if file_issues:
            found[variety] = file_issues
            print(f"  {variety}: {len(file_issues)} old pattern(s)")
            for desc, count in file_issues:
                print(f"    → {desc} ({count}×)")
        else:
            print(f"  {variety}: ✓")
    return found
```

### 7a.6 Hygiene scan runner

```python
def run_hygiene_scan(pdps, canonical_suffix=None, redirect_registers=None):
    """Run all hygiene checks. Call after the standard audit when trigger is ''check the PDPs''."""
    
    print("\n" + "=" * 60)
    print("HYGIENE SCAN")
    print("=" * 60 + "\n")
    
    # 1. Within-category stale slugs
    if canonical_suffix:
        stale = check_stale_slugs(pdps, canonical_suffix)
    else:
        print("=== STALE URL SLUGS (WITHIN-CATEGORY) ===\n")
        print("  ⚠ No canonical suffix provided — skipping within-category slug check.")
        print("  Load the category reference to enable this check.\n")
        stale = None
    
    # 2. Cross-category stale slugs
    print()
    if redirect_registers:
        cross_stale = check_cross_category_slugs(pdps, redirect_registers)
    else:
        print("=== STALE URL SLUGS (CROSS-CATEGORY) ===\n")
        print("  ⚠ No redirect register provided — skipping cross-category slug check.")
        print("  Load hub redirect tables (R_a_dahlia-301-redirect-table.md etc.) to enable.\n")
        cross_stale = None
    
    # 3. Link attributes
    print()
    attr_issues = check_link_attributes(pdps)
    
    # 4. Residual comments
    print()
    comments = check_residual_comments(pdps)
    
    # 5. Old filenames
    print()
    old_files = check_old_filenames(pdps)
    
    # Summary
    print("\n--- HYGIENE SUMMARY ---\n")
    if stale is not None:
        print(f"  Within-category slugs: {''CLEAN'' if stale == 0 else f''{stale} found (HIGH)''}")
    if cross_stale is not None:
        print(f"  Cross-category slugs:  {''CLEAN'' if cross_stale == 0 else f''{cross_stale} found (HIGH)''}")
    print(f"  Link attributes:       {''CLEAN'' if not attr_issues else f''{sum(len(v) for v in attr_issues.values())} issues (MEDIUM)''}")
    print(f"  Residual comments:     {''CLEAN'' if not comments else f''{sum(len(v) for v in comments.values())} found (MEDIUM)''}")
    print(f"  Old filenames:         {''CLEAN'' if not old_files else f''{sum(len(v) for v in old_files.values())} found (LOW)''}")
    
    return stale, cross_stale, attr_issues, comments, old_files
```

---

## 8. OUTPUT

After running the audit, Claude should produce:

1. **A prioritised issues report** (markdown file) with:
   - HIGH: any CT FAIL items, broken links, factual errors, stale URL slugs within-category and cross-category (hygiene)
   - MEDIUM: CT FLAG items, link distribution imbalance, phrase repetition, missing link attributes (hygiene), residual EXPERT/TODO comments (hygiene)
   - LOW: minor wording suggestions, old filename references (hygiene)

   When the trigger was "check the PDPs", the hygiene results appear in a dedicated **Hygiene Scan** section after the standard audit results.

2. **Updated spreadsheet** — update the category tab with:
   - CT v3.17 result per PDP
   - Word count
   - FAQ count and questions used
   - Container answer tier
   - Any notes from the audit

---

## NOTES

- **One category at a time.** Don''t mix dahlia and sweet pea PDPs in one audit run.
- **Two trigger phrases.** "Run the PDP audit" = standard audit (§§2–7). "Check the PDPs" = standard audit + hygiene scan (§7a). The hygiene scan only runs when explicitly triggered by the "check the PDPs" phrase (or close variant).
- **Guides and PDPs auto-detected.** The runner checks for a spec panel (Variety: line). If absent, it switches to guide mode — CHECK 3 is skipped, CHECK 15 uses topic-phrase matching instead of variety-name matching, and body copy extraction uses the full HTML rather than stripping spec/Why Buy blocks.
- **Update EXEMPT_URLS** per category before running CHECK 11.
- **The CT dash thresholds were tightened in v3.10 to reflect JdeB''s cosmos pots guide edit. Previous: FAIL >1.5, FLAG >0.8. New: FAIL >0.8, FLAG >0.3. Target: zero em-dashes in body text. JdeB''s edited cosmos guides (main + pots, v2.2) both scored 0.00/100w.** check_emdash now also counts hyphens used as dashes (word - word pattern), which JdeB also avoids.
- **Para CV is informational only.** JdeB prefers natural 2-paragraph flow — low CV is the owner''s choice, not a failing.
- **Hygiene scan requires the canonical slug suffix** from the category reference file. If unavailable, the stale slug check is skipped with a warning.
- **This file supersedes pdp-audit-template.md** for automated audits. The template remains useful as a manual checklist for one-off reviews.

---

## REVISION LOG

- 20 Mar 2026 (v3.22): CHECK 45 added — SEO title tag quality (`check_title_tag()`).
- 20 Mar 2026 (v3.21): CHECKs 43–44 added (contractions, self-notes). CHECK 37 perennial exemption. §3a→§3 cross-ref update.
- 15 Mar 2026 (v3.20): Editorial voice checks (CHECKs 32–42). 11 functions for E1–E11. Batch voice score. HEDGE_WORDS constant.
- 12 Mar 2026 (v3.19): Cross-file consistency fixes. Dahlia guide URL corrected. Cross-category slug check added. BANNED list: "showcasing" added.
- 12 Mar 2026 (v3.18): CHECKs 27a/27b/28/29/30/31 added. EXEMPT_PATTERNS expanded. SPEC_SYNONYM_CLUSTERS defined.
- 12 Mar 2026 (v3.17): CHECKs 23–26 added. BANNED phrase list expanded. Version strings corrected throughout.
- 12 Mar 2026 (v3.16): Governance audit fixes A3–A7. Collection URL corrected. CHECK 18 empty-alt fix. CHECK 15 generic H2 detection.
- 12 Mar 2026 (v3.15): Dahlia word count range corrected 700–800 → 700–1,100 to match Master Rules v8.7.
- 7 Mar 2026 (v3.14): Editorial lessons guide reference added. RHS AGM reference updated to compact markdown format.
- 7 Mar 2026 (v3.13): CHECK 22 — collection slug verification against canonical URLs.
- 6 Mar 2026 (v3.12): Hygiene scan added for "Check the PDPs" trigger. Four hygiene check functions. Stale slug detection.
- 5 Mar 2026 (v3.11): Word count range corrected. CT version references updated.
- 3 Mar 2026 (v3.10): Dash thresholds tightened (FAIL 0.8, FLAG 0.3). Hyphens-as-dashes detection added.
- 3 Mar 2026 (v3.8): Dash density thresholds tightened further. Numeric range dashes excluded.
- 2 Mar 2026 (v3.7): Container FAQ compliance — category-aware approved variety lists. Word count range updated.
- 28 Feb 2026 (v3.4): CHECKs 15–17 added (heading keywords, snippet structure, keyword phrase density). Guide-mode auto-detection.
- 25 Feb 2026 (v3.3): Created. Combines audit template with CT v3.3, link validation, phrase repetition, content quality scoring.
', 'text/markdown', NOW(), 'seed')
ON CONFLICT (filename) DO NOTHING;

INSERT INTO governance_files (filename, content, content_type, updated_at, uploaded_by)
VALUES ('GOV-verification-hierarchy-v1_0.md', '# Cosmo Source Authority Hierarchy and Data Verification Protocol
## GOV-verification-hierarchy-v1_0.md
## 6 April 2026

---

## Purpose

This document governs how information enters Cosmo and how it is verified before reaching content production. It was written after a systemic data quality audit (6 April 2026) triggered by a classification error: Clematis montana ''Odorata'' was recorded in `cultivar_reference` as a Late Large-flowered Group 3 clematis (3m) when the RHS and International Clematis Register confirm it is a Montana Group 1 clematis (8m). The error originated from a secondary source and was never cross-checked against the authoritative register. It propagated into a buying guide draft.

The audit revealed the same pattern across other genera: AGM status from commercial nursery websites treated as fact, hardiness data absent for secondary-source cultivars, and no systematic cross-reference against definitive lists. This document establishes the hierarchy and process that prevents recurrence.

---

## Source Authority Tiers

### Tier 1 — Definitive registers and institutional bodies

Treated as correct without further verification. When Tier 1 and any lower tier conflict, **Tier 1 wins**.

| Source | Scope | How stored in Cosmo |
|---|---|---|
| **RHS published AGM lists** (Dec 2024) | AGM status and hardiness for all ornamentals, fruit, herbs, veg | `reference_documents` (full text); `cultivar_reference.rhs_agm`, `rhs_agm_year`, `rhs_hardiness` |
| **RHS Plant Database** | Classification, hardiness, AGM for all genera | `reference_sources` (source_id); `cultivar_reference` rows with `source_type = ''database''` |
| **International Clematis Register & Checklist 2002** | Clematis classification, pruning groups, parentage | `reference_sources`; 151 clematis cultivars in `cultivar_reference` |
| **National Sweet Pea Society Classification List 2026** | Sweet pea classification by NSPS series | `reference_sources`; 37 Lathyrus cultivars in `cultivar_reference` |
| **RHS The Garden magazine** | Editorial content, trial results, seasonal advice | `editorial_content`; `knowledge_staging` |
| **RHS trial reports** | Variety performance, hardiness, disease resistance under trial conditions | `reference_claims` |

`rhs_verification_status` applied: `register_verified_match`

---

### Tier 2 — Recognised specialist authorities

Trusted within their stated domain. Where they conflict with Tier 1 on classification, AGM, or hardiness, Tier 1 wins. Where they cover ground Tier 1 doesn''t (detailed variety descriptions, growing notes, cultural observations), they are treated as authoritative within that domain.

| Source | Authoritative domain | Trust scope | Notes |
|---|---|---|---|
| **David Austin Roses** | David Austin rose varieties — description, classification, performance, parentage | Complete within their own range | Nobody knows their own roses better. Trust completely for DA-bred varieties. |
| **Peter Beales** | All other rose varieties — historical classification, performance, description | Complete for non-DA varieties | The pre-eminent non-DA rose authority. Historically the reference for old roses. |
| **Thorncroft Clematis** | Clematis — growing requirements, performance, practical classification | Cultural notes and growing; cross-check classification against ICR | Specialist grower; monitored site. Classification should be cross-checked against ICR for pruning groups. |
| **Downderry Nursery** | Lavender — variety classification, performance, hardiness, fragrance | Cultural notes and variety selection | Now defunct but data snapshot remains valid. 91 Lavandula cultivars ingested. |
| **Sarah Raven** | Cosmos, sweet peas, dahlias — variety selection, growing, companion planting, cutting garden use | Editorial and recommendation content | High editorial quality. Trust for variety performance and use-case recommendations in these genera. |

`rhs_verification_status` applied: `register_verified_match` for domain-specific claims; AGM and hardiness must still be cross-checked against Tier 1 before content production use.

---

### Tier 3 — Reputable secondary sources

Useful and generally accurate but not authoritative for classification or AGM. Data from these sources is ingested as `unverified` and must be cross-checked against Tier 1 or Tier 2 before being used in content production for the fields listed in the verification gate below.

| Source | Notes |
|---|---|
| ART (Agroforestry Research Trust) | Good for fruit variety descriptions, pollination groups, harvest season. Not the official register for any genus. |
| RHS monitored site pages (crawled) | Real-time RHS content extracted via FireCrawl. Treat as Tier 1 once verified against the stable RHS Plant Database, but raw crawl extracts start as `unverified`. |
| Feedly RSS feed items | Content signals and editorial intelligence. Good for discovering information, not authoritative for botanical facts. |
| FireCrawl crawls of non-Tier-1/2 sites | Starting material only. Requires verification before database entry for any key classification field. |
| Aylett Nurseries (dahlias) | Good secondary source for dahlia variety data. Cross-reference AGM with RHS ornamentals list. |
| Gardens Illustrated, Gardeners'' World | Editorial/cultural content. Good for situational recommendations and plant use; not authoritative for botanical classification. |

`rhs_verification_status` applied: `unverified` on ingestion.

---

### Tier 4 — General commercial or unknown sources

Everything else. Treated as unverified intelligence. Never used directly in content production without verification. This includes: general nursery websites, Google shopping data, price comparison sites, and any source Claude cannot identify.

`rhs_verification_status` applied: `unverified` on ingestion.

---

## The Verification Gate

The gate applies when information moves from the database into content production. Any cultivar or species data used in a PDP, growing guide, advice page, or lifecycle email must have the following fields verified:

| Field | Authority | `rhs_verification_status` required |
|---|---|---|
| AGM status (`rhs_agm`) | RHS published AGM lists December 2024 (stored in `reference_documents`) — not nursery website claims | `register_verified_match` |
| AGM year (`rhs_agm_year`) | Same | `register_verified_match` |
| Hardiness (`rhs_hardiness`) | RHS AGM lists or RHS Plant Database | `register_verified_match` or `rhs_verified_match` |
| Species / group classification | Relevant register (ICR for clematis; RHS for others) | `register_verified_match` |
| Type classification (rose type, dahlia group, etc.) | Tier 1 or appropriate Tier 2 for the genus | `register_verified_match` |

**Fields that do not require gate verification before content production:** Flower colour, approximate height, scent notes, companion planting recommendations, cultural advice. These can be drawn from Tier 2/3 sources with appropriate hedging in content if uncertain.

### The content production rule

Before asserting AGM status, hardiness, or species classification in a PDP or guide, query `rhs_verification_status` on the relevant `cultivar_reference` row. If the status is `unverified`:
- Do not assert the unverified value as fact
- Flag the gap explicitly or omit the claim
- Do not use a nursery website''s statement as a substitute for verified database data

---

## The Ingestion Rule

For every piece of information entering Cosmo — whether from an RSS feed, a FireCrawl crawl, an RHS magazine scan, a Feedly item, or a manual research session:

1. **Identify the source tier** before writing anything to the database
2. **Assign `rhs_verification_status` at ingestion:**
   - Tier 1 sources → `register_verified_match`
   - Tier 2 sources (within their domain) → `register_verified_match`; for AGM and hardiness, `unverified` until cross-checked against Tier 1
   - Tier 3/4 sources → `unverified`
3. **Do not overwrite existing Tier 1/2 data** with Tier 3/4 data. If a secondary source contradicts existing verified data, record the discrepancy in `verification_notes` and flag for review
4. **For AGM claims specifically:** The RHS published AGM lists are the only authoritative source. A commercial nursery website calling a plant AGM is not sufficient evidence to set `rhs_agm = true`. Verify against `reference_documents` (which contains the full RHS lists)
5. **For conflicts between tiers:** Tier 1 wins. Record both values in `verification_notes` and mark `rhs_verification_status = ''rhs_verified_discrepancy''`

---

## Verification Status Values

`cultivar_reference.rhs_verification_status` uses these values:

| Value | Meaning |
|---|---|
| `unverified` | Data has not been cross-checked against any authoritative register. Default for Tier 3/4 sources. |
| `rhs_verified_match` | Checked against RHS Plant Database in this session; key fields agree |
| `rhs_verified_discrepancy` | Checked against RHS; discrepancy found and recorded in `verification_notes` |
| `rhs_not_found` | Cultivar searched for on RHS but not found (may be legitimate — not all cultivars are listed) |
| `register_verified_match` | Confirmed against an authoritative register (ICR, NSPS, RHS AGM lists, RHS Plant Database). The gold standard. |
| `register_verified_discrepancy` | In an authoritative register but key fields differ from database; discrepancy in `verification_notes` |

---

## AGM List Verification — Procedure

The RHS AGM lists (December 2024) are stored in `reference_documents` linked to `reference_sources`. To verify AGM status for any genus:

```sql
-- Check whether a cultivar is in the AGM lists (via reference_documents text search)
SELECT content FROM reference_documents rd
JOIN reference_sources rs ON rd.reference_source_id = rs.id
WHERE rs.source_name ILIKE ''%AGM%''
AND rd.content ILIKE ''%[cultivar name]%'';

-- Update a cultivar confirmed as AGM from the list
UPDATE cultivar_reference SET
  rhs_agm = true,
  rhs_agm_year = [year],
  rhs_hardiness = ''[H-rating]'',
  rhs_verification_status = ''register_verified_match'',
  verification_notes = ''Confirmed in RHS AGM [Ornamental Plants / Fruit, Herbs and Vegetables] December 2024.'',
  verified_at = NOW()
WHERE cultivar_name = ''[name]''
AND species_ref_id = ''[species_uuid]'';

-- Mark cultivar confirmed as NOT in AGM list
UPDATE cultivar_reference SET
  verification_notes = ''AGM status confirmed absent: not in RHS AGM [list] December 2024.'',
  verified_at = NOW()
WHERE cultivar_name = ''[name]'';
```

---

## Self-Correcting Mechanisms

**RHS site monitoring (live):** 952 RHS pages crawled, daily monitoring active via content hash change detection. Changes to RHS plant pages — AGM withdrawals, hardiness revisions, classification updates — will be flagged as changes in `content_feed_items` within 24 hours of publication.

**AGM list refresh:** The RHS publishes updated AGM lists periodically (typically annually). When a new list is available, re-run the cross-reference queries used in the 6 April 2026 session against all affected genera. Update `reference_documents` with the new list text and update the `reference_sources` record with the new publication year.

**`v_conflicting_claims` view:** Surfaces disagreements between sources already in `reference_claims`. Should be run quarterly and discrepancies resolved.

---

## Genera Verification Status (as at 6 April 2026)

| Genus | AGM verified | Hardiness verified | Classification verified | Outstanding |
|---|---|---|---|---|
| Clematis | ✓ (ICR + RHS) | Partial | ✓ (ICR) | Type classification for 110 non-AGM Ashridge roses still to check |
| Rosa | ✓ (RHS Dec 2024) | 16 AGM holders now verified | Partial | Hardiness + type for 110 non-AGM unverified rows |
| Malus | ✓ (RHS Dec 2024) | ✓ (all H6) | Partial (ART source) | Full classification check pending |
| Pyrus | ✓ (RHS Dec 2024) | ✓ (all H6) | Partial | — |
| Prunus (cherries/plums) | ✓ (RHS Dec 2024) | ✓ | Partial | — |
| Rosmarinus | ✓ (RHS Dec 2024) | ✓ (H4) | — | — |
| Lavandula | ✓ (RHS Hardy Lavender Trials) | ✓ | ✓ (Downderry) | — |
| Lathyrus | ✓ (NSPS 2026) | — | ✓ (NSPS) | — |
| Dahlia | ✗ Incomplete | ✗ | Partial | Complete from RHS ornamentals AGM list |
| Tulipa | ✗ Not verified | ✗ | ✗ | RHS AGM ornamentals list available |
| Narcissus | ✗ Not verified | ✗ | ✗ | RHS AGM ornamentals list available |

---

## Revision Log

- 6 April 2026 (v1.0): Created following systematic data quality audit. Root cause: Clematis montana ''Odorata'' misclassified as Late Large-flowered Group 3 from a secondary source. Audit revealed incomplete AGM data across Rosa, Malus, and other genera. AGM data cross-referenced and corrected for Rosa (16 cultivars), Malus (47 apples), Pyrus (8 pears), Prunus (cherries, plums, damsons), Rosmarinus (5 varieties). RHS AGM lists December 2024 (ornamentals + fruit/veg) registered as reference sources and stored in `reference_documents`.
', 'text/markdown', NOW(), 'seed')
ON CONFLICT (filename) DO NOTHING;

-- ------------------------------------------------------------
-- faq_bank — ≥5 approved rows (0 approved Rosa FAQs exist in production)
-- ------------------------------------------------------------
INSERT INTO faq_bank (question, answer, category, topic, faq_type, species_ref_id, status)
VALUES
    ('When is the best time to plant a climbing rose?', 'Plant bare-root climbing roses between November and March while dormant. Container-grown roses can go in at any time, though autumn and spring are ideal.', 'roses', 'planting', 'when', '1058bd1d-5a3c-4682-8523-bfe722f48723', 'approved'),
    ('How do I train a climbing rose against a wall?', 'Fix horizontal wires 45cm apart across the wall. Fan the main stems outward at 45 degrees from the base — horizontal training encourages more flowering shoots along the length of the stem.', 'roses', 'training', 'how_to', '1058bd1d-5a3c-4682-8523-bfe722f48723', 'approved'),
    ('How much space does a climbing rose need?', 'Most climbing roses reach 3–4m tall and spread 1.5–2m wide at maturity. Allow at least 1.5m between plants and fix supports before planting.', 'roses', 'sizing', 'how_to', '1058bd1d-5a3c-4682-8523-bfe722f48723', 'approved'),
    ('Is Climbing Iceberg fragrant?', 'Climbing Iceberg has a light, sweet fragrance — noticeable up close on a warm day. It compensates with exceptional repeat flowering from June through to the first frosts.', 'roses', 'fragrance', 'what_is', '1058bd1d-5a3c-4682-8523-bfe722f48723', 'approved'),
    ('When should I prune a climbing rose?', 'Prune lightly in autumn to remove dead or damaged wood. Do the main structural pruning in late winter (February–March): cut side shoots back to 2–3 buds and tie in any new long canes.', 'roses', 'pruning', 'when', '1058bd1d-5a3c-4682-8523-bfe722f48723', 'approved')
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- pdp_content — 0 rows for test slug (tests version=1 logic in EF)
-- ------------------------------------------------------------
DELETE FROM pdp_content WHERE slug = 'champagne-moment-floribunda-rose-plants';
