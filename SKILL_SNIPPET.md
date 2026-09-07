## Desktop product + connectors (merge into skill)

**Product = desktop local host** (`START.bat`, `serve.ps1`, `server.py`) plus a desktop dialog / side panel that polls a **local cache**. Zero billable AI tokens for refresh. See pack `docs/DESKTOP_ONLY.md` (decision 2026-09-06).

**Not a product path:** phone PWA, Add to Home Screen, or agent/bot republish of hosted live JSON to keep a mobile glance fresh. That loop is a token sand trap.

**Optional static host** (Cloudflare Pages / `static/` root) is an **example UI demo** only (`static/demo-spend.json`, **Demo** chip). Do not sell it as live phone meters.

**Zero billable AI tokens for refresh:** never call Imagine, chat completions, or paid generation to update meters. Prefer free / read-only billing·usage·balance connectors, email receipts, or static demo JSON. Cloud connectors and free read-only APIs are OK; secrets stay in host env / OS secret store — never in the public pack.

Public pack path for share: anonymized tree (example meters only). See pack `README.md`, `HOSTED.md`, `docs/deploy.md`, `PUBLISH.md`.
