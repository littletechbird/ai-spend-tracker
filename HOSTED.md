# Hosted architecture

## Default publish shape

```
HTTPS PWA (static/)  ->  phone + desktop install from one URL
         |
         |- Demo: GET /demo-spend.json  (or /cache/spend.example.json)
         |- Live:  GET /api/spend        (optional Worker / Pages Function)
```

- **Static shell:** `index.html`, `app.js`, `style.css`, icons, `manifest.webmanifest`, `sw.js`.
- **Spend data:** tiny JSON. No WebSocket, no inference pipeline.
- **Refresh:** re-fetch JSON only. Chip shows **Demo** when using static example data.

## Anti-patterns (explicit)

- **No** chat completions, Imagine, `generate_*`, or other billable tokens to refresh meters.
- **No** Hatch / agent sync cron as a dependency.
- **No** secrets in the public repo (connectors use env / secret store on the host, not committed files).

## Optional `/api/spend`

When you add a Cloudflare Pages Function or Worker:

1. Serve merged cache or free connector reads (read-only billing / usage / balance APIs).
2. Keep the same JSON shape as `static/demo-spend.json`.
3. Manual Refresh may hit `/api/spend/refresh` if implemented; otherwise reload the same snapshot.

If `/api/spend` is missing (404) or unreachable on a pure static host, the UI **falls back** to demo JSON so GitHub Pages / Cloudflare static still install and demo.

## Localhost (optional advanced)

`server.py` / `serve.ps1` remain for Windows/desktop localhost. They are not required for the hosted PWA path.
