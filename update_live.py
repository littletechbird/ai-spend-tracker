#!/usr/bin/env python3
"""Merge live spend fields into cache/spend.json.

Usage:
  echo '{"rows":[{"id":"higgsfield","current":"$12.40","status":"OK"}]}' | python3 update_live.py
  python3 update_live.py <<'JSON'
  {"higgsfield": {"current": "120 credits", "status": "OK", "next_reset": "2026-10-01"}}
  JSON

Accepts either:
  {"rows": [ {id, ...fields}, ... ]}
  {"<id>": { ...fields }, ...}
  [{id, ...}, ...]
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / "cache" / "spend.json"
PT = ZoneInfo("America/Los_Angeles")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _now_pt() -> str:
    return datetime.now(PT).strftime("%Y-%m-%d %I:%M:%S %p PT")


def _normalize(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [r for r in payload if isinstance(r, dict) and r.get("id")]
    if not isinstance(payload, dict):
        raise SystemExit("JSON must be object or array")
    if "rows" in payload and isinstance(payload["rows"], list):
        return [r for r in payload["rows"] if isinstance(r, dict) and r.get("id")]
    # map id -> fields
    out = []
    for k, v in payload.items():
        if k in ("updated_at", "updated_at_pt", "meta") or not isinstance(v, dict):
            continue
        row = dict(v)
        row["id"] = row.get("id") or k
        out.append(row)
    return out


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        raise SystemExit("Pass JSON on stdin")
    updates = _normalize(json.loads(raw))
    if not updates:
        raise SystemExit("No row updates found")

    CACHE.parent.mkdir(parents=True, exist_ok=True)
    if CACHE.exists():
        data = json.loads(CACHE.read_text(encoding="utf-8"))
    else:
        data = {"rows": [], "updated_at": None, "updated_at_pt": None}

    by_id = {r["id"]: r for r in data.get("rows") or [] if r.get("id")}
    for upd in updates:
        eid = upd["id"]
        base = by_id.get(eid) or {"id": eid, "account": eid}
        # merge non-null fields from update
        for k, v in upd.items():
            if k == "id":
                continue
            if v is not None:
                base[k] = v
        by_id[eid] = base

    # preserve order: existing then new
    order = [r["id"] for r in data.get("rows") or [] if r.get("id")]
    for u in updates:
        if u["id"] not in order:
            order.append(u["id"])
    data["rows"] = [by_id[i] for i in order if i in by_id]
    data["updated_at"] = _now_iso()
    data["updated_at_pt"] = _now_pt()
    data["meta"] = data.get("meta") or {}
    data["meta"]["last_inject"] = data["updated_at"]

    CACHE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(f"Merged {len(updates)} row(s) → {CACHE}")
    print(f"Updated: {data['updated_at_pt']}")


if __name__ == "__main__":
    main()
