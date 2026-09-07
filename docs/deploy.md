# Deploy — optional static demo (not the product)

Preferred public **example** host for this pack: **Cloudflare Pages** (static root = `static/`). No secrets required in the repo.

This deploys the **demo UI** (example meters). It is **not** a live phone meter and **not** the supported install. The product is desktop local host — see [`DESKTOP_ONLY.md`](DESKTOP_ONLY.md) and the root `README.md`.

## Option A — Dashboard (copy-paste)

1. Push this public pack to a GitHub repo (example data only — see `PUBLISH.md`).
2. Cloudflare Dashboard → **Workers & Pages** → **Create** → **Pages** → Connect to Git.
3. Build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `static`
4. Save and deploy. You get `https://<project>.pages.dev`.
5. Optional: attach a custom domain under the project Custom domains.

Open that HTTPS URL on **desktop** if you want to look at the example shell. Do not treat Add to Home Screen / phone install as a product path.

## Option B — Wrangler CLI

From the repo root (this pack):

```bash
# one-time: npm i -g wrangler   (or use npx)
npx wrangler pages project create ai-spend-tracker
npx wrangler pages deploy static --project-name=ai-spend-tracker
```

`wrangler.toml` in the repo root is a stub for project name / compatibility. **Do not** commit API tokens; use `wrangler login` or CI secrets outside the pack.

## After deploy

1. Open the HTTPS URL on desktop → confirm example rows and a **Demo** chip (no `/api` yet).
2. Do **not** document phone Add to Home Screen / Install app as supported.
3. Desktop Chrome may still offer an install icon; that is optional for the **demo** shell only.
4. Later (optional): add a Pages Function for `/api/spend` backed by free connector reads — still zero billable inference tokens. A hosted live JSON drop for phones is **not** a product goal.

## GitHub Pages (also fine for demo)

Prefer publishing the **`static`** folder (e.g. action with `publish_dir: static`, or a `static`-only branch). Demo fallback in `app.js` keeps the UI working without `/api`.

## What not to do

- Do not put management keys, `.env`, or live `cache/*.json` in the connected repo.
- Do not call paid generation APIs from a refresh Function.
- Do not republish live JSON on a timer so a phone PWA “stays fresh” — that is the token sand trap described in `DESKTOP_ONLY.md`.
