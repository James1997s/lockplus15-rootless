#!/usr/bin/env python3
"""Refresh SHA-256 records for existing local folder-theme files after reviewed edits."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "themes"
CATALOG = ROOT / "catalog.json"


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    updated = 0
    for record in catalog.get("themes", []):
        if not isinstance(record, dict):
            continue
        manifest_path = ROOT / str(record.get("url", ""))
        if not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("format") != "folder":
            continue
        base_path = manifest.get("basePath")
        if not isinstance(base_path, str) or base_path.startswith("/") or ".." in Path(base_path).parts:
            raise SystemExit(f"Unsafe basePath in {manifest_path}")
        for file_record in manifest.get("files", []):
            if not isinstance(file_record, dict) or not isinstance(file_record.get("path"), str):
                raise SystemExit(f"Invalid file record in {manifest_path}")
            relative_path = Path(file_record["path"])
            if relative_path.is_absolute() or ".." in relative_path.parts:
                raise SystemExit(f"Unsafe file path in {manifest_path}: {relative_path}")
            local_file = ROOT / base_path / relative_path
            if not local_file.is_file():
                raise SystemExit(f"Missing declared file: {local_file}")
            file_record["sha256"] = hashlib.sha256(local_file.read_bytes()).hexdigest()
            updated += 1
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Updated SHA-256 records for {updated} declared folder-theme files.")


if __name__ == "__main__":
    main()
