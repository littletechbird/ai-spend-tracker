# Public publish checklist

Before GitHub push, Cloudflare deploy, or an X post:

## Hosted HTTPS + both devices

- [ ] Default story is **hosted HTTPS PWA** (one URL) — not localhost-only
- [ ] README covers **mobile** (Add to Home Screen / Install) and **desktop** (Chrome Install / pin)
- [ ] Demo mode works on static host (no PowerShell): open URL → example meters + **Demo** chip
- [ ] `docs/deploy.md` / `wrangler.toml` present; **no secrets** in repo
- [ ] `HOSTED.md` states: no inference tokens for refresh

## Scrub / privacy

- [ ] No real names, handles, emails, phone, address, machine hostnames / IDs
- [ ] No live spend numbers (use `static/demo-spend.json` / example cache only)
- [ ] No invoice IDs / receipt subjects / team IDs / API key names
- [ ] No `sand-secrets`, OAuth tokens, management keys, `.env`
- [ ] No absolute personal user paths / local desk paths in docs
- [ ] UI title/footer are product-only (“AI Spend Tracker”); littletechbird mark OK as creator link
- [ ] Screenshots use privacy mask **or** example data
- [ ] Live install folder is **not** what you push — this public pack is

If anything personal leaked into a file, remove it here and regenerate example cache — do not “fix it after” on the live tree.
