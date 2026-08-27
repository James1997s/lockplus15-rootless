#!/usr/bin/env python3
"""Convert active SpecialLock HTML-folder catalog entries into native scene manifests."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
THEMES = PROJECT / "themes"
CATALOG_PATH = THEMES / "catalog.json"

# Each migrated scene uses existing UIKit/Core Animation primitives only.
SCENES = {
    "xen-cat-side-clock-folder": {"title": "WHIMSY CAT", "accent": "#F5B6D3", "gradient": "#22122B,#5E2A5F,#130F27", "time_top": "190", "ring": True},
    "ios26-big-clock": {"title": "BIG CLOCK", "accent": "#B8D9FF", "gradient": "#101624,#31557D,#0B0F19", "time_top": "132", "ring": False},
    "oneui8-adaptive-clock": {"title": "ONE UI", "accent": "#E7E2FF", "gradient": "#121221,#34335F,#11101D", "time_top": "180", "image": "folder-themes/oneui8-adaptive-clock/wallpaper.jpg", "ring": True},
    "aurora-glass": {"title": "AURORA", "accent": "#D3FFF9", "gradient": "#0D1932,#24535A,#1A133B", "time_top": "176", "image": "folder-themes/aurora-glass/wallpaper.jpg", "ring": True},
    "ink-garden": {"title": "INK GARDEN", "accent": "#E8E1CB", "gradient": "#151915,#36422C,#10120E", "time_top": "192", "image": "folder-themes/ink-garden/wallpaper.jpg", "ring": False},
    "desert-sun": {"title": "DESERT SUN", "accent": "#FFE0A8", "gradient": "#40241D,#A6572F,#251810", "time_top": "177", "image": "folder-themes/desert-sun/wallpaper.jpg", "ring": True},
    "ocean-night": {"title": "OCEAN NIGHT", "accent": "#B8F1FF", "gradient": "#051A31,#0E4A67,#06101F", "time_top": "177", "image": "folder-themes/ocean-night/wallpaper.jpg", "ring": False},
    "neon-architecture": {"title": "NEON ARCHITECTURE", "accent": "#7EF9F1", "gradient": "#071026,#22245E,#0C0620", "time_top": "183", "ring": True},
    "geometric-twenty-four": {"title": "GEOMETRIC 24", "accent": "#F9D86E", "gradient": "#1B1B23,#45414D,#15151A", "time_top": "184", "image": "folder-themes/geometric-twenty-four/wallpaper.jpg", "ring": True},
    "purple-anime-stack-clock": {"title": "PURPLE ANIME", "accent": "#F2D7FF", "gradient": "#1F1038,#59358A,#140D27", "time_top": "176", "image": "folder-themes/purple-anime-stack-clock/artwork.webp", "ring": False},
    "animated-psychedelic-cat": {"title": "PSYCHEDELIC CAT", "accent": "#D29BFF", "gradient": "#0E0620,#5A187C,#0B1030", "time_top": "185", "ring": True},
    "stencil-revolt": {"title": "STENCIL REVOLT", "accent": "#F5D251", "gradient": "#191817,#453629,#181818", "time_top": "182", "image": "folder-themes/stencil-revolt/wallpaper.jpeg", "ring": False},
    "silent-film-chaplin": {"title": "SILENT FILM", "accent": "#F0EEE5", "gradient": "#101010,#4D4D4D,#171717", "time_top": "177", "image": "folder-themes/silent-film-chaplin/wallpaper.png", "ring": False},
    "html-test-lock": {"title": "NATIVE TEST LOCK", "accent": "#91F7EC", "gradient": "#081827,#155661,#0B1224", "time_top": "185", "ring": True},
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native_asset(theme_id: str, source_relative: str) -> tuple[str, str, str]:
    source = THEMES / source_relative
    if not source.is_file():
        raise SystemExit(f"Missing source asset for {theme_id}: {source_relative}")
    suffix = source.suffix.lower()
    target_relative = source_relative
    target = source
    if suffix == ".webp":
        target_relative = f"assets/{theme_id}/{source.stem}.png"
        target = THEMES / target_relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(source) as image:
            image.convert("RGBA").save(target, "PNG", optimize=True)
    return "artwork", target_relative, sha256(target)


def native_manifest(theme_id: str, spec: dict[str, object]) -> dict[str, object]:
    assets: list[dict[str, str]] = []
    placed: dict[str, dict[str, str]] = {
        "background": {"type": "wallpaper", "gradient": str(spec["gradient"])},
        "ambientLeft": {"type": "particle", "top": "126", "x": "0.17", "size": "15", "opacity": "0.40", "color": str(spec["accent"]), "motion": "drift", "motion-distance": "26", "motion-duration": "6"},
        "ambientRight": {"type": "particle", "top": "398", "x": "0.83", "size": "21", "opacity": "0.33", "color": str(spec["accent"]), "motion": "drift", "motion-distance": "33", "motion-duration": "8"},
        "title": {"type": "text", "top": "63", "width": "330", "height": "28", "font-size": "13", "font-weight": "700", "letter-spacing": "2.2", "color": str(spec["accent"]), "innerHTML": str(spec["title"]), "animation": "glow", "animation-duration": "4"},
        "clock": {"type": "clock", "top": str(spec["time_top"]), "width": "340", "height": "86", "font-size": "70", "font-weight": "700", "letter-spacing": "-1", "color": "#FFFFFF", "text-shadow": "0 2 10 rgba(0,0,0,0.72)"},
        "date": {"type": "date", "top": str(int(spec["time_top"]) + 86), "width": "330", "height": "28", "font-size": "14", "font-weight": "600", "letter-spacing": "1.4", "color": "#FFFFFF", "uppercase": "true", "text-shadow": "0 1 6 rgba(0,0,0,0.75)"},
        "nativeBadge": {"type": "panel", "top": "712", "width": "238", "height": "38", "font-size": "11", "font-weight": "700", "letter-spacing": "1.1", "color": str(spec["accent"]), "background-color": "rgba(7,7,12,0.42)", "border": "1 solid rgba(255,255,255,0.22)", "border-radius": "18", "innerHTML": "NATIVE · LOCAL · VISUAL ONLY"},
    }
    if spec.get("ring"):
        placed["orbit"] = {"type": "ring", "top": "112", "diameter": "248", "stroke-width": "1.4", "arc-start": "18", "arc-length": "308", "dash": "7 10", "rotation-duration": "18", "rotation-direction": "clockwise", "opacity": "0.62", "color": str(spec["accent"])}
    image = spec.get("image")
    if isinstance(image, str):
        asset_id, relative, digest = native_asset(theme_id, image)
        assets.append({"id": asset_id, "url": relative, "sha256": digest})
        placed["artwork"] = {"type": "image", "asset-id": asset_id, "image-role": "wallpaper", "opacity": "0.64", "animation": "breathe", "animation-duration": "8"}
    return {"schemaVersion": 2, "format": "native", "id": theme_id, "assets": assets, "placedElements": placed}


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    records = catalog.get("themes")
    if not isinstance(records, list):
        raise SystemExit("Catalog has no themes array")
    migrated = 0
    for record in records:
        theme_id = record.get("id") if isinstance(record, dict) else None
        if theme_id not in SCENES:
            continue
        record["format"] = "native"
        record["url"] = f"{theme_id}.json"
        manifest = native_manifest(theme_id, SCENES[theme_id])
        (THEMES / f"{theme_id}.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        migrated += 1
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Migrated {migrated} folder themes to native JSON manifests.")


if __name__ == "__main__":
    main()
