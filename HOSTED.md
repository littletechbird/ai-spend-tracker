# Hosted architecture

Spend is **desktop-only**. The product path is a local host (or desktop install) that polls a **local cache**. A hosted static copy is an optional **example UI**, not a live phone meter. See [`docs/DESKTOP_ONLY.md`](docs/DESKTOP_ONLY.md).

## Default shape

```
Desktop local host  ->  polls cache/spend.json (or /api/spend) for free
         |
         |- Demo: GET /demo-spend.json  (or /cache/spend.example.json)
         |- Live:  GET /api/spend        (optional; machine-local or later Worker)
```

- **Static shell:** `index.html`, `app.js`, `style.css`, icons, `manifest.webmanifest`, `sw.js`.
- **Spend data:** tiny JSON. No WebSocket, no inference pipeline.
- **Refresh:** re-fetch JSON only. Chip shows **Demo** when using static example data.
- **Responsive CSS:** kept so a narrow desktop window still works. Not a mobile product.

## Anti-patterns (explicit)

- **No** chat completions, Imagine, `generate_*`, or other billable tokens to refresh meters.
- **No** agent / bot republish cron to keep a phone or hosted PWA “fresh” (token sand trap).
- **No** secrets in the public repo (connectors use env / secret store on the host, not committed files).
- **No** marketing of Add to Home Screen / phone PWA as a supported install.

## Optional `/api/spend`

When you add a local handler (or later a Cloudflare Pages Function / Worker):

1. Serve merged cache or free connector reads (read-only billing / usage / balance APIs).
2. Keep the same JSON shape as `static/demo-spend.json`.
3. Manual Refresh may hit `/api/spend/refresh` if implemented; otherwise reload the same snapshot.

If `/api/spend` is missing (404) or unreachable on a pure static host, the UI **falls back** to demo JSON so a public example still renders.

## Desktop localhost (the product)

`server.py` / `serve.ps1` / `START.bat` are the supported way to run live meters. They poll a local cache — no token tax, always-on when the desk is on.
