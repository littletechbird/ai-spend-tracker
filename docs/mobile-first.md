# Mobile-first hosting (phone works with Spinkatron OFF)

**Lock:** Phone PWA must use public HTTPS only — **zero** dependency on `127.0.0.1`, LAN, or a desktop that is often powered off.

**Constraints:** Zero billable token/inference refresh. Free / read-only meter sources only. Public pack stays scrubbed (see `PUBLISH.md`).

## What ships today

| Piece | Role |
| --- | --- |
| `static/` | Installable HTTPS PWA (manifest + SW) |
| `static/demo-spend.json` | Public demo meters (always safe to publish) |
| `static/live-spend.example.json` | Shape template for a live drop-in file |
| `static/spend-live.json` / `spend.json` | **Not in public pack** — Hatch/private host overwrite target |
| Optional `/api/spend` | Pages Function / Worker later (same JSON shape) |

**UI load order** (`app.js`):

1. `GET /api/spend` (and manual `GET /api/spend/refresh`) if present  
2. Else `GET /spend-live.json` then `GET /spend.json` (live static drop-in)  
3. Else demo JSON → **Demo** chip  

Service worker never caches `/api/*`, `/spend-live.json`, or `/spend.json` (shell cache `v4`).

## GitHub status (checked 2026-09-06)

`littletechbird` had **no** existing `ai-spend-tracker` / `spend-tracker` repo (repos present: `the-one-true-fairy-tale-amv`, `electrical-quote-tool`, `dark-room`).  
`gh` auth on Hatch box: **available** as `littletechbird`.

## Architecture options (live meters, no desktop)

### Option A — Cloudflare Pages static + Pages Function / Worker

- Static PWA from `static/`.
- Function at `/api/spend` reads free billing/usage APIs or KV/R2 JSON.
- Secrets stay in CF env / secret store — never in the browser or public repo.
- **Best long-term** for always-on live reads without a box cron.

### Option B — Hatch box routine writes scrubbed JSON every N minutes

- Routine on Hatch (always-on box) builds scrubbed `spend-live.json` (same shape as demo).
- Publishes to: Cloudflare Pages (redeploy / direct upload), R2 public object, or a private/unlisted host path.
- Phone only fetches HTTPS JSON — **no Spinkatron**.
- **Best for v1 private-for-Brent** (unlisted `*.pages.dev` URL + scrubbed file).

### Option C — Phone PWA connectors

- Hard: browser cannot hold management keys safely.
- Reject for v1 (and usually forever for secrets).

## Recommendation

| Audience | Choice | Why |
| --- | --- | --- |
| **v1 private-for-Brent** (unlisted URL OK) | **Option B** | Fastest path with zero desktop dependency; Hatch already authenticated for CF/gh; no secrets in PWA. |
| **Public demo** | Pure static Pages (demo JSON only) | Scrubbed example meters; installable PWA; no live numbers. |
| **Later connected** | Add **Option A** `/api/spend` | Free connector reads server-side; keep Option B as fallback snapshot. |

Do **not** rely on Spinkatron `server.py` / `127.0.0.1:8787` for phone.

## Hatch routine: overwrite live JSON

1. Collect free/read-only meters on Hatch (or copy scrubbed snapshot from a private cache).  
2. Emit JSON matching `static/live-spend.example.json` / `static/demo-spend.json`.  
3. Write to host as **`spend-live.json`** next to the PWA (Pages project root = `static/`):

```bash
# Example: after building scrubbed JSON at /tmp/spend-live.json
cp /tmp/spend-live.json /workspace/ai-account-tracker-public/static/spend-live.json
export PATH="$HOME/.local/node22/bin:$PATH"   # if system Node < 22
npx wrangler pages deploy static --project-name=ai-spend-tracker
```

Alternative (no full redeploy): put the file on **R2** / GitHub raw / Drive public link and point a tiny Pages Function at it later — still free reads only.

**Privacy:** never commit real `spend-live.json` to the public GitHub pack. `.gitignore` already excludes `static/spend-live.json` and `static/spend.json`.

## Deploy — public demo

Preferred: Cloudflare Pages (`wrangler.toml` → project `ai-spend-tracker`, output dir `static`).

```bash
export PATH="$HOME/.local/node22/bin:$PATH"
npx wrangler pages deploy static --project-name=ai-spend-tracker
```

GitHub Pages also fine: publish `static/` only; demo fallback works without `/api`.

### If auth blocked

1. Push scrubbed pack to `littletechbird/ai-spend-tracker` (public).  
2. Cloudflare Dashboard → Workers & Pages → Create → Pages → Connect Git.  
3. Build output directory: **`static`** (no build command).  
4. Deploy → open `https://ai-spend-tracker.pages.dev` (or the assigned URL).  
5. For private meters: keep a second private/unlisted Pages project and drop `spend-live.json` via Hatch.

## Hard no

- No chat completions / Imagine / paid generation to refresh meters.  
- No secrets in public repo or client JS.  
- No phone dependency on Spinkatron power state.
