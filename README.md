# AI Spend Tracker

**Hosted HTTPS PWA** — one URL for phone and desktop. Track AI account spend / balances with **zero billable refresh tokens**.

This folder is the **public template**. It ships with **example** meters only. Live installs (real spends, secrets) stay private.

Creator mark: [littletechbird](https://github.com/littletechbird)

## Install (hosted — default)

Deploy once (see [`docs/deploy.md`](docs/deploy.md)), then open your HTTPS URL.

**Live public demo:** [https://ai-spend-tracker.pages.dev/](https://ai-spend-tracker.pages.dev/) — see also [`docs/mobile-first.md`](docs/mobile-first.md).

### Mobile

1. Open the HTTPS URL in **Safari** (iOS) or **Chrome** (Android).
2. **iOS Safari:** Share → **Add to Home Screen**.
3. **Android Chrome:** ⋮ → **Install app** / **Add to Home screen**.
4. Launch from the home-screen icon (standalone, no browser chrome).

### Desktop

1. Open the **same HTTPS URL** in Chrome (or Edge).
2. Install: address-bar install icon, or ⋮ → **Install AI Spend Tracker**.
3. Optional: right-click the app → **Pin to taskbar** / Pin to Start.

Demo mode works **immediately** with example meters — no keys, no PowerShell, no local host.

## Demo vs connected

| Mode | What you get |
| --- | --- |
| **Demo** (static host / GitHub Pages / Pages without `/api`) | Example rows from `static/demo-spend.json`. Chip shows **Demo**. Refresh reloads that JSON only. |
| **Connected** (optional later) | Free / read-only billing or usage connectors, or local cache. Still **no** chat completions, Imagine, or paid generation for refresh. |

Connect accounts later via free connectors / read-only keys when you are ready. Never put secrets in this public pack.

## Hard constraints

1. **Zero billable refresh.** Never call paid generation APIs to update the tracker. Free/read-only balance/usage/billing endpoints, email receipts, or static demo JSON only.
2. **Low CPU.** UI polls tiny JSON ~every 60s; pauses when the tab is hidden.
3. **One HTTPS URL** for phone-only and desktop installs (PWA).

## Advanced: local Windows host (optional)

Keep the existing local files if you want a machine-only install:

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

Local Spinkatron / localhost mode is **optional advanced** — not required for the public hosted PWA.

## Layout

```
static/                 # PWA UI + demo-spend.json
docs/deploy.md          # Cloudflare Pages (preferred)
HOSTED.md               # Architecture (static + optional /api)
wrangler.toml           # Cloudflare Pages stub (no secrets)
cache/spend.example.json
accounts.example.json
serve.ps1 / START.bat   # optional local Windows host
server.py               # optional local Python host
```

## Wire your own meters (later)

1. Copy `accounts.example.json` → `accounts.json` on your private install.
2. Prefer free balance / management / DashboardService collectors — never billable inference for refresh.
3. Keep API keys in your OS secret store / env — never commit them.
4. Hide free no-limit grants and canceled subs.

See [`HOSTED.md`](HOSTED.md), [`docs/deploy.md`](docs/deploy.md), and [`PUBLISH.md`](PUBLISH.md) before posting publicly.

## Privacy mask

Toolbar **Privacy mask** (off by default) hides limit / spend / notes until hover (desktop) or tap (mobile).

No Hatch sync routine required.
