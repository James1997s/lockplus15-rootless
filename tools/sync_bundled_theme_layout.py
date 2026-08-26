#!/usr/bin/env python3
"""Copy updated public themes into the bundled layout without adding remote-only records.

The layout catalog remains the package allow-list. Thus GitHub Sync Test, which is
not listed in the layout catalog, stays published-only and cannot be bundled.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_THEMES = ROOT / "themes"
BUNDLED_THEMES = ROOT / "layout" / "Library" / "LockPlus15" / "Themes"


def main() -> None:
    public_catalog = json.loads((PUBLIC_THEMES / "catalog.json").read_text(encoding="utf-8"))
    bundled_catalog = json.loads((BUNDLED_THEMES / "catalog.json").read_text(encoding="utf-8"))
    public_by_id = {record["id"]: record for record in public_catalog["themes"]}
    copied = 0

    for bundled_record in bundled_catalog["themes"]:
        theme_id = bundled_record["id"]
        public_record = public_by_id.get(theme_id)
        if public_record is None:
            raise SystemExit(f"Bundled record {theme_id!r} is missing from the public catalog")
        source = PUBLIC_THEMES / public_record["url"]
        destination = BUNDLED_THEMES / bundled_record["url"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        copied += 1

    print(f"Copied {copied} animated themes into the package layout.")


if __name__ == "__main__":
    main()
