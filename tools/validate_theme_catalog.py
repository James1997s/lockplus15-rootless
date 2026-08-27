#!/usr/bin/env python3
"""Validate the native-only local SpecialLock catalog and its embedded asset declarations."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1] / "themes"
CATALOG = ROOT / "catalog.json"
ALLOWED_ASSET_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif"}


def fail(message: str) -> None:
    raise SystemExit(message)


def safe_relative(value: str) -> bool:
    path = Path(value)
    parsed = urlparse(value)
    return bool(value) and not path.is_absolute() and not parsed.scheme and not parsed.netloc and ".." not in path.parts


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    entries = catalog.get("themes")
    if not isinstance(entries, list) or not entries:
        fail("Catalog must contain a non-empty themes array.")

    identifiers: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            fail("Catalog contains a non-object entry.")
        identifier = entry.get("id")
        name = entry.get("name")
        location = entry.get("url")
        if not isinstance(identifier, str) or not identifier or not all(character.isalnum() or character in "_-" for character in identifier):
            fail("Theme is missing a safe id.")
        if identifier in identifiers:
            fail(f"Duplicate theme id: {identifier}")
        identifiers.add(identifier)
        if not isinstance(name, str) or not name:
            fail(f"Theme {identifier} has no name.")
        if entry.get("format") != "native":
            fail(f"Theme {identifier} is not marked native.")
        if not isinstance(location, str) or not location.endswith(".json") or not safe_relative(location):
            fail(f"Theme {identifier} has an invalid local manifest location.")
        path = ROOT / location
        if not path.is_file():
            fail(f"Theme file missing: {location}")
        theme = json.loads(path.read_text(encoding="utf-8"))
        if theme.get("format") != "native" or theme.get("id") != identifier:
            fail(f"Theme {identifier} is not a matching native manifest.")
        elements = theme.get("placedElements")
        if not isinstance(elements, dict) or not elements:
            fail(f"Theme {identifier} lacks placedElements.")
        for element_id, properties in elements.items():
            if not isinstance(element_id, str) or not isinstance(properties, dict):
                fail(f"Theme {identifier} has an invalid element.")
            if properties.get("type") == "html":
                fail(f"Theme {identifier} declares blocked HTML rendering.")
            for property_name, property_value in properties.items():
                if not isinstance(property_name, str) or not isinstance(property_value, str):
                    fail(f"Theme {identifier} has a non-string style property.")
                lowered = property_value.lower()
                if any(token in lowered for token in ("javascript:", "data:text/html", "http://", "https://", "<script", "<iframe")):
                    fail(f"Theme {identifier} contains a blocked content reference.")
        assets = theme.get("assets", [])
        if not isinstance(assets, list):
            fail(f"Theme {identifier} has an invalid asset list.")
        for asset in assets:
            if not isinstance(asset, dict):
                fail(f"Theme {identifier} has an invalid asset record.")
            asset_id, asset_url, digest = asset.get("id"), asset.get("url"), asset.get("sha256")
            if not isinstance(asset_id, str) or not asset_id or not isinstance(asset_url, str) or not safe_relative(asset_url) or Path(asset_url).suffix.lower() not in ALLOWED_ASSET_EXTENSIONS:
                fail(f"Theme {identifier} has an unsafe asset declaration.")
            asset_path = ROOT / asset_url
            if not asset_path.is_file() or not isinstance(digest, str) or hashlib.sha256(asset_path.read_bytes()).hexdigest() != digest.lower():
                fail(f"Theme {identifier} asset hash mismatch: {asset_url}")

    print(f"Validated {len(entries)} native catalog entries and local asset declarations.")


if __name__ == "__main__":
    main()
