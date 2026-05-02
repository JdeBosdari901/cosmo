# Cosmo Admin Dashboard

Single-file React app deployed as a Cloudflare Pages site. No build step — uses React, Supabase JS, and Chart.js via CDN UMD bundles, so the file in this folder is the deployment artefact verbatim.

**Live URL:** https://cosmo-admin.pages.dev
**Cloudflare Pages project:** `cosmo-admin`
**Source baseline committed:** 2 May 2026

## Deploying

The dashboard does not auto-deploy from this repo. You deploy by running `wrangler` from your local machine, pointed at this folder.

### Preview (any non-main branch)

```bash
cd dashboard

CLOUDFLARE_API_TOKEN=<token from SYS-credentials.md> \
CLOUDFLARE_ACCOUNT_ID=<account id from SYS-credentials.md> \
npx wrangler@latest pages deploy . \
  --project-name=cosmo-admin \
  --branch=<your-branch-name> \
  --commit-dirty=true
```

This creates a preview URL of the form `https://<branch>.cosmo-admin.pages.dev`. Production at `cosmo-admin.pages.dev` is unaffected.

### Production

Same command with `--branch=main`. Per `SYS-verification-protocol.md` § Workflow activation, **production deploys must be preceded by an end-to-end check on a preview URL**, with the verification result visible in conversation/notes before the production deploy is run.

## Anon key in source

The `SUPABASE_ANON_KEY` constant near the top of `index.html` is committed as a literal. This is correct: Supabase publishable/anon keys are designed to be exposed in client code and are protected at the database layer by Row Level Security. See [Supabase API keys docs](https://supabase.com/docs/guides/api/api-keys).

If the anon key is rotated, update both this file and `SYS-credentials.md` in the same commit.

## What's in the file

The file is one large `<script>` block defining functional React components for each page in the dashboard. Top-level structure:

| Component | Lines (approx) | What it does |
|---|---|---|
| `Login` | top | Email/password login via Supabase Auth |
| `Overview` | early | Top-level KPI cards |
| `Staging` | | Pages awaiting publish |
| `Explorer` | | Generic table viewer over Supabase tables |
| `Sources` | | Sitemap/feed sync state |
| `Ecosystem` | | Linked-content map |
| `PageSpeed` | | PageSpeed metrics |
| `PriorityMatrix` | | Improvement priority grid |
| `ContentEcosystem` | mid | Content tab (Pages, Performance, Improvements, Articles, AI Placeholders, AI Visibility sub-tabs) |
| `Alerts` | | Workflow watchdog + EF run health |
| `Docs` | | Markdown viewer for governance files |
| `Attribution` | | Marketing attribution dashboard |
| `BomSwap` | | BOM swap UI for Katana |
| `Processes` | | Process register viewer |
| `App` | bottom | Top-level router |

## Editing protocol

When editing `index.html`:

1. Always work from the latest `main` (the deployed production version is the source of truth — pull and confirm before editing).
2. Make changes locally, deploy to a preview branch, verify behaviour on the preview URL.
3. Only then commit + push and deploy to production.
4. Commit messages should describe the user-visible change ("Add AI Placeholders sub-tab to Content"), not the implementation detail.

## Known gaps

- No automated tests. Smoke testing is manual via the preview URL.
- The file is large (~5,300 lines, ~263 KB). Consider splitting into modules if it grows significantly further. The current single-file design is intentional for the no-build, edit-and-deploy workflow.
