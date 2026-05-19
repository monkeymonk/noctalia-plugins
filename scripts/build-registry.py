#!/usr/bin/env python3
"""Regenerate registry.json from each plugin's manifest.json.

Scans repo-root subdirectories that contain a manifest.json, extracts the
fields Noctalia indexes, and stamps each entry with the lastUpdated
timestamp of the most recent commit that touched the plugin directory.
"""
from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIELDS = [
    "id",
    "name",
    "version",
    "official",
    "author",
    "description",
    "repository",
    "minNoctaliaVersion",
    "license",
    "tags",
    "lastUpdated",
]


def last_commit_iso(path: Path) -> str:
    try:
        out = subprocess.check_output(
            ["git", "log", "-1", "--format=%cI", "--", str(path)],
            cwd=REPO_ROOT,
            text=True,
        ).strip()
        if out:
            return out
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def build_entry(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text())
    entry = {
        "official": False,
        **{k: manifest[k] for k in FIELDS if k in manifest},
        "lastUpdated": last_commit_iso(manifest_path.parent),
    }
    return {k: entry[k] for k in FIELDS if k in entry}


def main() -> int:
    plugins = [
        build_entry(p) for p in sorted(REPO_ROOT.glob("*/manifest.json"))
    ]
    registry = {"version": 1, "plugins": plugins}
    (REPO_ROOT / "registry.json").write_text(
        json.dumps(registry, indent=2) + "\n"
    )
    print(f"wrote registry.json with {len(plugins)} plugin(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
