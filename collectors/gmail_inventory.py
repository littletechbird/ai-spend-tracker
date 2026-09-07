"""Email-derived subscription rows from accounts.json (static inventory)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
ACCOUNTS_PATH = ROOT / "accounts.json"

GMAIL_SOURCES = {"gmail_inventory"}


def _load_accounts() -> list[dict[str, Any]]:
    if not ACCOUNTS_PATH.exists():
        return []
    data = json.loads(ACCOUNTS_PATH.read_text(encoding="utf-8"))
    return list(data.get("accounts") or [])


def collect_all(existing_by_id: dict[str, dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    existing_by_id = existing_by_id or {}
    rows: list[dict[str, Any]] = []
    for acct in _load_accounts():
        if acct.get("source") not in GMAIL_SOURCES:
            continue
        eid = acct["id"]
        prev = existing_by_id.get(eid) or {}
        subject = acct.get("last_invoice_subject") or prev.get("last_invoice_subject")
        inv_date = acct.get("last_invoice_date") or prev.get("last_invoice_date")
        note_parts = []
        if subject:
            note_parts.append(f"Invoice: {subject}")
        if inv_date:
            note_parts.append(f"Date: {inv_date}")
        if not note_parts:
            note_parts.append(acct.get("notes") or "Email-derived; no live balance")
        rows.append(
            {
                "id": eid,
                "account": acct.get("account") or eid,
                "sub_level": acct.get("sub_level") or "subscription",
                "limit": acct.get("limit") if acct.get("limit") is not None else prev.get("limit"),
                "limit_period": acct.get("limit_period") or prev.get("limit_period") or "month",
                "current": prev.get("current"),
                "next_reset": prev.get("next_reset"),
                "status": "EMAIL",
                "note": " · ".join(note_parts),
                "source": "gmail_inventory",
                "last_invoice_subject": subject,
                "last_invoice_date": inv_date,
            }
        )
    return rows
