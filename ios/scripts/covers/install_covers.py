"""Gives Vibeshine's Starwire test apps their covers, on the PC that hosts them.

Renders make_covers.py's SVGs to PNG with headless Chrome into
%LOCALAPPDATA%\\StarwireTestPattern\\covers, backs up apps.json next to itself, and sets the
"image-path" of the three test apps to those PNGs. Nothing else in apps.json changes: the script
checks that before writing. Vibeshine reads the change after SunshineService restarts.
    python ios/scripts/covers/install_covers.py [--apps <apps.json>] [--dry-run]
"""

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_covers  # noqa: E402

APPS_JSON = Path(r"C:\Program Files\Sunshine\config\apps.json")
CHROME = Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
# App name in Vibeshine -> cover file name
APP_COVERS = {title: name for name, title in make_covers.COVERS.items()}


def with_covers(apps: dict, folder: Path) -> dict:
    """apps.json's contents with the test apps' image-path pointing at the covers in `folder`.
    Every other app and field stays as it was."""
    updated = copy.deepcopy(apps)
    for app in updated.get("apps", []):
        name = APP_COVERS.get(app.get("name"))
        if name:
            app["image-path"] = str(folder / f"{name}.png")
    return updated


def changed_fields(before: dict, after: dict) -> list:
    """(app name, field) for every field that differs; apps are matched by position."""
    changes = []
    old_apps, new_apps = before.get("apps", []), after.get("apps", [])
    if len(old_apps) != len(new_apps) or {k for k in before if k != "apps"} != {k for k in after if k != "apps"}:
        return [("*", "structure")]
    for key in before:
        if key != "apps" and before[key] != after[key]:
            changes.append(("*", key))
    for old, new in zip(old_apps, new_apps):
        for field in sorted(set(old) | set(new)):
            if old.get(field) != new.get(field):
                changes.append((old.get("name"), field))
    return changes


def render(folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    make_covers.main(str(folder))
    profile = folder / "chrome-profile"
    for name in make_covers.COVERS:
        svg = folder / f"{name}.svg"
        subprocess.run([str(CHROME), "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=1", "--window-size=600,800", f"--user-data-dir={profile}",
                        f"--screenshot={folder / (name + '.png')}", svg.as_uri()], check=True, capture_output=True)
    shutil.rmtree(profile, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apps", type=Path, default=APPS_JSON)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    folder = Path(os.environ["LOCALAPPDATA"]) / "StarwireTestPattern" / "covers"
    before = json.loads(args.apps.read_text(encoding="utf-8"))
    after = with_covers(before, folder)
    changes = changed_fields(before, after)
    if any(field != "image-path" for _, field in changes):
        print(f"Refusing: more than image-path would change: {changes}")
        return 1
    print("Would change:" if args.dry_run else "Changing:", changes or "nothing")
    if args.dry_run or not changes:
        return 0
    render(folder)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup = args.apps.with_name(f"{args.apps.name}.starwire-backup-{stamp}")
    shutil.copy2(args.apps, backup)
    args.apps.write_text(json.dumps(after, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Backed up to {backup}; restart SunshineService to load the covers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
