#!/usr/bin/env python3
"""AI Spend Tracker — lightweight HTTP server on 0.0.0.0:8787.

HARD CONSTRAINTS:
- ZERO BILLABLE API calls on refresh (cache / free read-only only).
- Server collector refresh at most ~1/min (CACHE_MAX_AGE_S=55).
- Never auto-launch browser or headless scrape loops.
"""
from __future__ import annotations

import json
import threading
import time
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"
CACHE = ROOT / "cache" / "spend.json"
ACCOUNTS = ROOT / "accounts.json"
HOST, PORT = "0.0.0.0", 8787
CACHE_MAX_AGE_S = 55
PT = ZoneInfo("America/Los_Angeles")

_lock = threading.Lock()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _now_pt() -> str:
    return datetime.now(PT).strftime("%Y-%m-%d %I:%M:%S %p PT")


def _read_cache() -> dict[str, Any]:
    if not CACHE.exists():
        return {"rows": [], "updated_at": None, "updated_at_pt": None}
    try:
        return json.loads(CACHE.read_text(encoding="utf-8"))
    except Exception:
        return {"rows": [], "updated_at": None, "updated_at_pt": None}


def _write_cache(data: dict[str, Any]) -> None:
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    CACHE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def _cache_age_s(data: dict[str, Any]) -> float:
    ts = data.get("updated_at")
    if not ts:
        return 1e9
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return (datetime.now(timezone.utc) - dt).total_seconds()
    except Exception:
        return 1e9


def _existing_by_id(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {r["id"]: r for r in (data.get("rows") or []) if isinstance(r, dict) and r.get("id")}


def _base_from_accounts(aid: str) -> dict[str, Any] | None:
    if not ACCOUNTS.exists():
        return None
    try:
        accounts = json.loads(ACCOUNTS.read_text(encoding="utf-8")).get("accounts") or []
        for a in accounts:
            if a.get("id") == aid:
                return a
    except Exception:
        pass
    return None


def refresh_collectors(force: bool = False) -> dict[str, Any]:
    """Run collectors and merge into spend.json if cache is stale."""
    with _lock:
        data = _read_cache()
        if not force and _cache_age_s(data) < CACHE_MAX_AGE_S:
            return data

        existing = _existing_by_id(data)

        # Import collectors lazily so server starts even if one is broken
        from collectors import cursor_usage, gmail_inventory, higgsfield, xai_console

        rows: list[dict[str, Any]] = []

        xai_base = {**(existing.get("xai-api") or {}), **(_base_from_accounts("xai-api") or {})}
        rows.append(xai_console.collect(xai_base))

        cur_base = {**(existing.get("grok-cursor") or {}), **(_base_from_accounts("grok-cursor") or {})}
        rows.append(cursor_usage.collect(cur_base))

        hf_base = {**(existing.get("higgsfield") or {}), **(_base_from_accounts("higgsfield") or {})}
        # Preserve injected live fields
        rows.append(higgsfield.collect(hf_base))

        email_rows = gmail_inventory.collect_all(existing)
        rows.extend(email_rows)

        # Preserve any extra injected rows not in the standard set
        known = {r["id"] for r in rows}
        for eid, erow in existing.items():
            if eid not in known:
                rows.append(erow)

        # Prefer injected current/limit/next_reset/status when collector says CONNECTOR/STALE/NEEDS_*
        # and existing had OK + values from update_live
        for i, row in enumerate(rows):
            prev = existing.get(row["id"])
            if not prev:
                continue
            # Always keep previously injected numeric/text spend if collector didn't set a fresher live value
            if row.get("current") is None and prev.get("current") is not None:
                row["current"] = prev["current"]
            if row.get("limit") is None and prev.get("limit") is not None:
                row["limit"] = prev["limit"]
            if not row.get("next_reset") and prev.get("next_reset"):
                row["next_reset"] = prev["next_reset"]
            # If update_live marked OK, don't wipe to CONNECTOR on refresh unless collector got real data
            if prev.get("status") == "OK" and row.get("status") in (
                "CONNECTOR",
                "NEEDS_LOGIN",
                "NEEDS_BROWSER",
                "NEEDS_MGMT_KEY",
                "NEEDS_API",
                "STALE",
                "EMAIL",
            ):
                if prev.get("current") is not None or prev.get("source") == "inject":
                    row["status"] = "OK"
                    row["note"] = prev.get("note") or "Injected live value"
                    row["source"] = prev.get("source") or row.get("source")
            rows[i] = row

        out = {
            "rows": rows,
            "updated_at": _now_iso(),
            "updated_at_pt": _now_pt(),
            "meta": {
                "cache_max_age_s": CACHE_MAX_AGE_S,
                "owner": "",
            },
        }
        _write_cache(out)
        return out


def seed_if_needed() -> None:
    if CACHE.exists():
        return
    refresh_collectors(force=True)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC), **kwargs)

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[spend-tracker] {self.address_string()} {fmt % args}")

    def _send_json(self, obj: Any, code: int = 200) -> None:
        body = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            self.path = "/index.html"
            return super().do_GET()
        if path == "/api/health":
            return self._send_json(
                {
                    "ok": True,
                    "service": "spend-tracker",
                    "time_pt": _now_pt(),
                    "cache": str(CACHE),
                }
            )
        if path == "/api/spend":
            data = refresh_collectors(force=False)
            return self._send_json(data)
        if path == "/api/spend/refresh":
            data = refresh_collectors(force=True)
            return self._send_json(data)
        return super().do_GET()


def main() -> None:
    seed_if_needed()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"AI Spend Tracker listening on http://{HOST}:{PORT}/")
    print(f"Local: http://127.0.0.1:{PORT}/")
    print(f"Cache: {CACHE}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down")
        httpd.shutdown()


if __name__ == "__main__":
    main()
