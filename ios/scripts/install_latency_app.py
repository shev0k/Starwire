"""Adds the "Starwire input latency" test app to Vibeshine, on the PC that hosts it.

Copies test-pattern.ps1 and input-latency.html into %LOCALAPPDATA%\\StarwireTestPattern, backs up
apps.json next to itself, and adds one app: a copy of "Starwire colour bars" (its own virtual
display, the PC's monitors left on) that shows input-latency.html instead. Nothing else in
apps.json changes; the script checks that before writing. Restart SunshineService afterwards.
    python ios/scripts/install_latency_app.py [--apps <apps.json>] [--dry-run]
"""

import argparse
import copy
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
APPS_JSON = Path(r"C:\Program Files\Sunshine\config\apps.json")
NAME = "Starwire input latency"
TEMPLATE = "Starwire colour bars"


def with_latency_app(apps: dict, folder: Path) -> dict:
    """apps.json's contents with the latency app added (or left alone if it's there)."""
    updated = copy.deepcopy(apps)
    entries = updated.get("apps", [])
    if any(app.get("name") == NAME for app in entries):
        return updated
    template = next(app for app in entries if app.get("name") == TEMPLATE)
    app = copy.deepcopy(template)
    app["name"] = NAME
    page = (folder / "input-latency.html").as_uri()
    app["cmd"] = (f'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '
                  f'"{folder / "test-pattern.ps1"}" -Url "{page}"')
    for key in ("uuid", "id"):
        app.pop(key, None)
    entries.append(app)
    return updated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", type=Path, default=APPS_JSON)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    folder = Path(os.environ["LOCALAPPDATA"]) / "StarwireTestPattern"
    before = json.loads(args.apps.read_text(encoding="utf-8"))
    after = with_latency_app(before, folder)
    added = len(after["apps"]) - len(before["apps"])
    if after["apps"][:len(before["apps"])] != before["apps"] or {k: v for k, v in after.items() if k != "apps"} != \
            {k: v for k, v in before.items() if k != "apps"}:
        print("Refusing: something besides the new app would change")
        return 1
    print("Would add" if args.dry_run else "Adding", NAME if added else "nothing (already there)")
    if args.dry_run:
        return 0
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("test-pattern.ps1", "input-latency.html"):
        shutil.copy2(HERE / name, folder / name)
    if added:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = args.apps.with_name(f"{args.apps.name}.starwire-backup-{stamp}")
        shutil.copy2(args.apps, backup)
        args.apps.write_text(json.dumps(after, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Backed up to {backup}; restart SunshineService to load it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
