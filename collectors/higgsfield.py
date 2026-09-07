"""Higgsfield balance collector — FREE / CACHE ONLY.

HARD RULES:
- Never call Imagine, generate_*, or any billable Higgsfield API.
- Prefer local cache / Hatch inject via update_live.py.
- Env token presence does NOT authorize paid calls; only free read-only
  balance endpoints would be allowed later, and only ≤1/min.
"""
from __future__ import annotations

import os
from typing import Any


def collect(base: dict[str, Any] | None = None) -> dict[str, Any]:
    b = base or {}
    row = {
        "id": "higgsfield",
        "account": "Higgsfield",
        "sub_level": b.get("sub_level") or "starter",
        "limit": b.get("limit"),
        "limit_period": b.get("limit_period"),
        "current": b.get("current"),
        "next_reset": b.get("next_reset"),
        "status": "CONNECTOR",
        "note": "Cache/inject only — never billable generate calls",
        "source": "higgsfield",
    }

    # Preserve injected / snapshot values; do not hit network.
    if row.get("current") is not None:
        row["status"] = "OK"
        row["note"] = b.get("note") or "From cache snapshot (free; not re-fetched every poll)"
        return row

    token = os.environ.get("HF_TOKEN") or os.environ.get("HIGGSFIELD_TOKEN")
    if token:
        row["status"] = "NEEDS_API"
        row["note"] = "Token present but live free-balance not wired; use update_live.py (no paid calls)"
    else:
        row["status"] = "CONNECTOR"
        row["note"] = "Inject via update_live.py / Hatch — no auto API"
    return row
