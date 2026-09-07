# AI Spend Tracker

**Desktop-only.** Track AI account spend / balances from a **desktop side panel or local host** that polls a **local cache** — **zero billable refresh tokens**.

This folder is the **public template**. It ships with **example** meters only. Live installs (real spends, secrets) stay private.

Phone / Add to Home Screen / hosted live JSON is **not** a supported product path. See [`docs/DESKTOP_ONLY.md`](docs/DESKTOP_ONLY.md) (product decision 2026-09-06).

Creator mark: [littletechbird](https://github.com/littletechbird)

## Install (desktop)

The product is a machine-local host plus a desktop window (or Chrome / Edge install).

```bat
START.bat
```

Opens `http://127.0.0.1:8787/` via `serve.ps1` (standalone app window). Or:

```bash
python3 server.py
```

- UI: http://127.0.0.1:8787/
- Health: `/api/health`
- Spend JSON: `/api/spend`

Then, if you want an installed desktop dialog:

1. Open that local URL in **Chrome** (or Edge).
2. Install: address-bar install icon, or ⋮ → **Install AI Spend Tracker**.
3. Optional: right-click the app → **Pin to taskbar** / Pin to Start.

Demo mode in the static UI also works with example meters — no keys required. Real meters stay on your private machine cache.

### Not a product path (deprecated)

**Do not** treat Safari / Chrome “Add to Home Screen”, a phone PWA, or a hosted live JSON URL as the way to run Spend. A glanceable phone meter cannot stay fresh without agent republish, and republishing often enough burns tokens. Details: [`docs/DESKTOP_ONLY.md`](docs/DESKTOP_ONLY.md).

Responsive layout CSS remains so a narrow desktop window still stacks. That is not mobile support.

## Optional public demo (example UI only)

A static hosted copy of the **example** UI exists at [https://ai-spend-tracker.pages.dev/](https://ai-spend-tracker.pages.dev/) for looking at the shell. It is **demo data**, not a live phone meter, and not the install path. Deploy notes: [`docs/deploy.md`](docs/deploy.md).

## Demo vs connected

| Mode | What you get |
| --- | --- |
| **Demo** (static files / hosted example) | Example rows from `static/demo-spend.json`. Chip shows **Demo**. Refresh reloads that JSON only. |
| **Connected** (desktop local host) | Free / read-only billing or usage connectors, or local cache. Still **no** chat completions, Imagine, or paid generation for refresh. |

Connect accounts later via free connectors / read-only keys when you are ready. Never put secrets in this public pack.

## Hard constraints

1. **Zero billable refresh.** Never call paid generation APIs to update the tracker. Free/read-only balance/usage/billing endpoints, email receipts, or static demo JSON only.
2. **Low CPU.** UI polls tiny JSON ~every 60s; pauses when the tab is hidden.
3. **Desktop-only.** Local cache on a machine that is on when you are at the desk. No token-taxed republish loop to keep a phone “fresh.”

## Layout

```
static/                 # Desktop UI + demo-spend.json
docs/DESKTOP_ONLY.md    # Why mobile is not a product path
docs/deploy.md          # Optional static demo host
HOSTED.md               # Architecture (static + optional /api)
wrangler.toml           # Cloudflare Pages stub (no secrets)
cache/spend.example.json
accounts.example.json
serve.ps1 / START.bat   # desktop Windows host
server.py               # desktop Python host
```

## Wire your own meters (later)

1. Copy `accounts.example.json` → `accounts.json` on your private install.
2. Prefer free balance / management / DashboardService collectors — never billable inference for refresh.
3. Keep API keys in your OS secret store / env — never commit them.
4. Hide free no-limit grants and canceled subs.

See [`HOSTED.md`](HOSTED.md), [`docs/deploy.md`](docs/deploy.md), and [`PUBLISH.md`](PUBLISH.md) before posting publicly.

## Privacy mask

Toolbar **Privacy mask** (off by default) hides limit / spend / notes until hover (or tap in a narrow window).
