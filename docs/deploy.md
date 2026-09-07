# Deploy — Cloudflare Pages (HTTPS PWA)

Preferred host for this pack: **Cloudflare Pages** (static root = `static/`). No secrets required in the repo.

## Option A — Dashboard (copy-paste)

1. Push this public pack to a GitHub repo (example data only — see `PUBLISH.md`).
2. Cloudflare Dashboard → **Workers & Pages** → **Create** → **Pages** → Connect to Git.
3. Build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `static`
4. Save and deploy. You get `https://<project>.pages.dev`.
5. Optional: attach a custom domain under the project Custom domains.

Install from that HTTPS URL on phone and desktop (see root `README.md`).

## Option B — Wrangler CLI

From the repo root (this pack):

```bash
# one-time: npm i -g wrangler   (or use npx)
npx wrangler pages project create ai-spend-tracker
npx wrangler pages deploy static --project-name=ai-spend-tracker
```

`wrangler.toml` in the repo root is a stub for project name / compatibility. **Do not** commit API tokens; use `wrangler login` or CI secrets outside the pack.

## After deploy

1. Open the HTTPS URL → confirm example rows and a **Demo** chip (no `/api` yet).
2. Mobile: Add to Home Screen / Install app.
3. Desktop Chrome: Install → pin to taskbar.
4. Later (optional): add a Pages Function for `/api/spend` backed by free connector reads — still zero billable inference tokens.

## GitHub Pages (also fine for demo)

Prefer publishing the **`static`** folder (e.g. action with `publish_dir: static`, or a `static`-only branch). Demo fallback in `app.js` keeps the UI working without `/api`.

## What not to do

- Do not put management keys, `.env`, or live `cache/*.json` in the connected repo.
- Do not call paid generation APIs from a refresh Function.
