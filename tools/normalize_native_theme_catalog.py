#!/usr/bin/env python3
"""Require explicit native manifests and catalog records for every selectable theme."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "themes"
CATALOG_PATH = ROOT / "catalog.json"


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    records = catalog.get("themes")
    if not isinstance(records, list) or not records:
        raise SystemExit("Catalog must contain a non-empty themes array")
    for record in records:
        if not isinstance(record, dict):
            raise SystemExit("Catalog contains a non-object record")
        theme_id = record.get("id")
        theme_url = record.get("url")
        if not isinstance(theme_id, str) or not isinstance(theme_url, str):
            raise SystemExit("Catalog record is missing id or URL")
        manifest_path = ROOT / theme_url
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("format") == "folder":
            raise SystemExit(f"Folder manifest remains active: {theme_id}")
        manifest["schemaVersion"] = 2
        manifest["format"] = "native"
        manifest["id"] = theme_id
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        record["format"] = "native"
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Normalized {len(records)} selectable themes as native manifests.")


if __name__ == "__main__":
    main()
