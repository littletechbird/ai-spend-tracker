## Hosted publish + connectors (merge into skill)

**Publish default = hosted HTTPS PWA** (Cloudflare Pages / static `static/` root). One URL installs on **phone** (Add to Home Screen / Install app) and **desktop** (Chrome Install / pin). Demo mode uses `static/demo-spend.json` with a clear **Demo** chip when `/api/spend` is absent — no PowerShell required for the public install story.

**Local 127.0.0.1 / Windows host** (`START.bat`, `serve.ps1`, `server.py`) remains **optional advanced**; keep those files, do not delete. No Hatch sync cron as a dependency.

**Zero billable AI tokens for refresh:** never call Imagine, chat completions, or paid generation to update meters. Prefer free / read-only billing·usage·balance connectors, email receipts, or static demo JSON. Cloud connectors and free read-only APIs are OK; secrets stay in host env / OS secret store — never in the public pack.

Public pack path for share: anonymized tree (example meters only). See pack `README.md`, `HOSTED.md`, `docs/deploy.md`, `PUBLISH.md`.
