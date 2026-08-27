#!/usr/bin/env python3
"""Reject remote resource loading in package-embedded SpecialLock folder themes."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "themes"
CATALOG = ROOT / "catalog.json"

REMOTE_HTML_ATTRIBUTE = re.compile(
    r"\b(?:src|href)\s*=\s*['\"]\s*(?:(?:https?:)?//)", re.IGNORECASE
)
REMOTE_CSS_URL = re.compile(
    r"\burl\(\s*['\"]?\s*(?:(?:https?:)?//)", re.IGNORECASE
)
NETWORK_API = re.compile(
    r"\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\b", re.IGNORECASE
)
DANGEROUS_HTML = re.compile(
    r"<\s*(?:iframe|object|embed|base)\b|\b(?:action|formaction)\s*=|\b(?:javascript|vbscript)\s*:",
    re.IGNORECASE,
)


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    problems: list[str] = []
    checked = 0

    for record in catalog.get("themes", []):
        if not isinstance(record, dict) or record.get("format") not in (None, "folder"):
            continue
        manifest_path = ROOT / str(record.get("url", ""))
        if not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("format") != "folder":
            continue
        theme_id = str(record.get("id", "<unknown>"))
        base_path = manifest.get("basePath")
        if not isinstance(base_path, str):
            problems.append(f"{theme_id}: missing folder basePath")
            continue
        for file_record in manifest.get("files", []):
            if not isinstance(file_record, dict) or not isinstance(file_record.get("path"), str):
                continue
            relative_path = file_record["path"]
            local_path = ROOT / base_path / relative_path
            if not local_path.is_file():
                continue
            suffix = local_path.suffix.lower()
            if suffix not in {".html", ".htm", ".css", ".js"}:
                continue
            text = local_path.read_text(encoding="utf-8", errors="replace")
            checks = [REMOTE_HTML_ATTRIBUTE, REMOTE_CSS_URL, NETWORK_API, DANGEROUS_HTML]
            for expression in checks:
                match = expression.search(text)
                if match:
                    problems.append(f"{theme_id}/{relative_path}: blocked external or interactive pattern {match.group(0)!r}")
            checked += 1

    if problems:
        print("Embedded folder-theme safety audit failed:")
        for problem in problems:
            print(f"ERROR: {problem}")
        raise SystemExit(1)
    print(f"Embedded folder-theme safety verified: {checked} HTML, CSS, or JS files are package-local only.")


if __name__ == "__main__":
    main()
