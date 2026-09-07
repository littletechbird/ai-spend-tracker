"""xAI console / usage collector — FREE READ OR CACHE ONLY.

HARD RULES:
- Never burn prepaid credits or call paid generation endpoints.
- get_usage_credits-style free reads are OK only if throttled ≤1/min
  and implemented as read-only; v1 prefers cache/spend.json snapshot.
- If login/cookies missing: status NEEDS_LOGIN — do NOT auto-launch browser.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "cache" / "xai_usage_snapshot.json"
COOKIE_CANDIDATES = [
    Path.home() / ".config" / "xai" / "cookies.json",
    ROOT / "cache" / "xai_cookies.json",
    ROOT / "cache" / "xai_session.json",
]


def _from_snapshot() -> dict[str, Any] | None:
    if not SNAPSHOT.exists():
        return None
    try:
        return json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    except Exception:
        return None


def collect(base: dict[str, Any] | None = None) -> dict[str, Any]:
    b = base or {}
    row = {
        "id": "xai-api",
        "account": "xAI API / SpaceXAI swarm",
        "sub_level": b.get("sub_level") or "prepaid + free credits",
        "limit": b.get("limit"),
        "limit_period": b.get("limit_period") or "month",
        "current": b.get("current"),
        "next_reset": b.get("next_reset"),
        "status": "NEEDS_LOGIN",
        "note": "NEEDS_LOGIN — no auto browser; inject or free usage snapshot only",
        "source": "xai_console",
    }

    snap = _from_snapshot()
    if snap:
        free_bal = snap.get("free_balance", snap.get("free"))
        prepaid = snap.get("prepaid", snap.get("prepaid_balance", 0))
        parts = []
        if free_bal is not None:
            parts.append(f"free ${free_bal}")
        if prepaid is not None:
            parts.append(f"prepaid ${prepaid}")
        row["current"] = " / ".join(parts) if parts else row.get("current")
        row["sub_level"] = snap.get("plan") or row["sub_level"]
        if snap.get("limit") is not None:
            row["limit"] = snap.get("limit")
        if snap.get("next_reset"):
            row["next_reset"] = snap.get("next_reset")
        row["status"] = "OK"
        row["note"] = snap.get("note") or "From free usage snapshot (≤1/min; cache preferred)"
        row["source"] = "xai_usage_snapshot"
        return row

    # Keep last known from merged cache (injected)
    if row.get("current") is not None:
        row["status"] = "OK" if b.get("status") == "OK" else "STALE"
        row["note"] = b.get("note") or "Last known from spend.json (no network refresh)"
        return row

    if os.environ.get("XAI_MGMT_KEY") or os.environ.get("XAI_API_KEY"):
        row["status"] = "NEEDS_MGMT_KEY"
        row["note"] = "Key in env but free usage read not wired; use snapshot / update_live.py — no paid calls"

    for path in COOKIE_CANDIDATES:
        if path.exists():
            row["status"] = "NEEDS_BROWSER"
            row["note"] = f"Cookie file {path.name} present; scrape not auto-run (no headless loop)"
            return row

    return row
