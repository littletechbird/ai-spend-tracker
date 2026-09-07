# Public publish checklist

Before GitHub push, Cloudflare deploy, or an X post:

## Desktop product (not phone)

- [ ] Default story is **desktop local host / side panel** — see `docs/DESKTOP_ONLY.md`
- [ ] README install is **desktop dialog only** (no Add to Home Screen / phone PWA as a supported path)
- [ ] Hosted URL, if mentioned, is an **example UI demo** — not a live phone meter
- [ ] Demo mode works on static files: example meters + **Demo** chip
- [ ] `docs/deploy.md` / `wrangler.toml` present; **no secrets** in repo
- [ ] `HOSTED.md` states: no inference tokens for refresh; no agent republish loop for mobile freshness

## Scrub / privacy

- [ ] No real names, handles, emails, phone, address, machine hostnames / IDs
- [ ] No live spend numbers (use `static/demo-spend.json` / example cache only)
- [ ] No invoice IDs / receipt subjects / team IDs / API key names
- [ ] No `sand-secrets`, OAuth tokens, management keys, `.env`
- [ ] No absolute personal user paths in docs
- [ ] UI title/footer are product-only (“AI Spend Tracker”); littletechbird mark OK as creator link
- [ ] Screenshots use privacy mask **or** example data
- [ ] Live install folder is **not** what you push — this public pack is

If anything personal leaked into a file, remove it here and regenerate example cache — do not “fix it after” on the live tree.
