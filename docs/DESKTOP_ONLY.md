# Desktop-only — why Spend is not a phone product

**Product decision:** 2026-09-06  
**By:** Brent Spink / [littletechbird](https://github.com/littletechbird)

AI Spend Tracker is a **desktop product**. The supported path is a desktop side panel or local host that polls a **local cache**. Phone / “Add to Home Screen” / hosted live JSON for a glanceable mobile meter is **not** a supported product path.

## The sand trap

A phone (or hosted PWA) cannot stay fresh enough to be a useful glance unless an agent **republishes** the meters.

- Republishing often enough to *feel* useful **burns AI tokens**.
- The closer you chase “useful freshness” on mobile, the more expensive it gets.
- That is a **sand trap:** closer to useful ⇒ more costly ⇒ further from useful.

Desktop does not have this tax. The side panel / local host polls a local cache **for free** (no token tax) and is **always-on when the desk is on**. That is the product.

## What this means in the repo

| Keep | Do not sell |
| --- | --- |
| Desktop install (local host, Chrome / Edge install, pin, side panel) | Phone / Add to Home Screen / Install app as a supported path |
| Responsive CSS (harmless if a window is narrow) | Live phone meters via bot sync, agent republish, or hosted live JSON |
| Public pack with **example** meters only | Private URLs, real spends, personal machine paths |
| Optional static hosted **demo** of the UI | Hosted HTTPS as the way to keep a phone “live” |

Older notes that treated mobile-first hosting as the lock (one URL, phone PWA, agent overwrite of live JSON) are **superseded** by this decision. See the stub in [`mobile-first.md`](mobile-first.md).
