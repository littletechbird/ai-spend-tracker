"""Grok Bot / Cursor usage — free DashboardService RPC collector on the user's Windows machine.

Live path: collectors/grok_bot_dashboard_rpc.ps1 (PowerShell) decrypts
%APPDATA%\\Grok Bot\\sand-secrets.json via Electron OSCrypt (DPAPI+AES-GCM),
calls GetSandUsageStatus + GetCurrentPeriodUsage, writes cache/grok_bot_usage_live.json
and merges spend.json row id=grok-cursor (source=dashboard_rpc).

This Python stub remains for update_live/server aggregation compatibility only.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
LIVE = ROOT / "cache" / "grok_bot_usage_live.json"


def collect(base: dict[str, Any] | None = None) -> dict[str, Any]:
    row: dict[str, Any] = {
        "id": "grok-cursor",
        "account": "Grok Bot / Cursor",
        "sub_level": (base or {}).get("sub_level") or "weekly usage + on-demand",
        "limit": (base or {}).get("limit"),
        "limit_period": (base or {}).get("limit_period") or "week",
        "current": (base or {}).get("current"),
        "next_reset": (base or {}).get("next_reset"),
        "status": "NEEDS_COLLECTOR",
        "note": "Run collectors/grok_bot_dashboard_rpc.ps1 on the user's Windows machine",
        "source": "pending_live",
    }
    if LIVE.exists():
        try:
            live = json.loads(LIVE.read_text(encoding="utf-8"))
            parts = []
            pct = live.get("weekly_usage_pct")
            if pct is not None:
                parts.append(f"weekly {round(float(pct), 1)}%")
            used = live.get("on_demand_spend_usd")
            lim = live.get("on_demand_limit_usd")
            if used is not None and lim is not None:
                parts.append(f"on-demand ${used} / ${lim}")
            elif used is not None:
                parts.append(f"on-demand ${used}")
            if parts:
                row["current"] = " · ".join(parts)
            if live.get("next_reset_pt"):
                row["next_reset"] = live["next_reset_pt"]
            row["status"] = "OK"
            row["source"] = live.get("source") or "dashboard_rpc"
            row["note"] = "DashboardService RPCs (local decrypt, free)"
        except Exception as e:  # noqa: BLE001
            row["status"] = "ERROR"
            row["note"] = f"live cache unreadable: {e}"
    return row
