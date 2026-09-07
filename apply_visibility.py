#!/usr/bin/env python3
import json
from pathlib import Path
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

PT = ZoneInfo("America/Los_Angeles")
KEEP = {"xai-console", "grok-cursor", "higgsfield", "suno"}
ORDER = ["xai-console", "grok-cursor", "higgsfield", "suno"]
CACHE = Path("/workspace/spend-tracker/cache/spend.json")

data = json.loads(CACHE.read_text(encoding="utf-8"))
before = [r.get("id") for r in data.get("rows") or []]
by = {r["id"]: r for r in (data.get("rows") or []) if r.get("id") in KEEP}
data["rows"] = [by[i] for i in ORDER if i in by]
now = datetime.now(timezone.utc)
data["updated_at"] = now.isoformat()
data["updated_at_pt"] = now.astimezone(PT).strftime("%Y-%m-%d %I:%M:%S %p PT")
meta = data.get("meta") or {}
meta["cache_max_age_s"] = 55
meta["owner"] = ""
meta["last_sync_routine"] = data["updated_at"]
data["meta"] = meta
CACHE.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("before", before)
print("after", [r["id"] for r in data["rows"]])
print(data["updated_at_pt"])
