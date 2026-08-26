#!/usr/bin/env python3
"""Add safe native animations and a status UI layer to every public LockPlus theme.

The script operates solely on the repository's own declarative JSON themes. It
creates no third-party assets and copies no code or content from reference bundles.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEMES = ROOT / "themes"
CATALOG = THEMES / "catalog.json"


def set_if_missing(properties: dict[str, str], key: str, value: str) -> None:
    if not properties.get(key):
        properties[key] = value


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    updated = 0
    created_status_panels = 0

    for record in catalog["themes"]:
        theme_path = THEMES / record["url"]
        theme = json.loads(theme_path.read_text(encoding="utf-8"))
        elements: dict[str, dict[str, str]] = theme["placedElements"]

        wallpaper = elements.get("wallpaper")
        if isinstance(wallpaper, dict):
            set_if_missing(wallpaper, "animation", "gradient-shift")
            set_if_missing(wallpaper, "animation-duration", "9.0")

        clock = elements.get("clock")
        if isinstance(clock, dict):
            set_if_missing(clock, "animation", "breathe")
            set_if_missing(clock, "animation-duration", "4.2")

        date = elements.get("todaystrings")
        if isinstance(date, dict):
            set_if_missing(date, "animation", "pulse")
            set_if_missing(date, "animation-duration", "5.2")

        banner = elements.get("themeBanner")
        if isinstance(banner, dict):
            set_if_missing(banner, "animation", "float")
            set_if_missing(banner, "animation-duration", "5.8")

        footer = elements.get("themeFooter")
        if isinstance(footer, dict):
            set_if_missing(footer, "animation", "glow")
            set_if_missing(footer, "animation-duration", "3.8")

        if "themeStatus" not in elements:
            panel_background = banner.get("background-color", "rgba(12,18,38,0.62)") if isinstance(banner, dict) else "rgba(12,18,38,0.62)"
            panel_border = banner.get("border", "1px solid rgba(210,240,255,0.48)") if isinstance(banner, dict) else "1px solid rgba(210,240,255,0.48)"
            panel_color = banner.get("color", "#F2FBFF") if isinstance(banner, dict) else "#F2FBFF"
            elements["themeStatus"] = {
                "type": "panel",
                "position": "absolute",
                "left": "50%",
                "top": "312px",
                "transform": "translateX(-50%)",
                "width": "206px",
                "height": "28px",
                "padding": "0px",
                "background-color": panel_background,
                "border": panel_border,
                "border-radius": "14px",
                "box-shadow": "0 4px 14px rgba(0,0,0,0.28)",
                "innerHTML": "LOCK  •  THEME READY",
                "color": panel_color,
                "font-family": "HelveticaNeue-Medium",
                "font-size": "9px",
                "font-weight": "700",
                "letter-spacing": "1.3px",
                "animation": "glow",
                "animation-duration": "4.6",
                "z-index": "4",
            }
            created_status_panels += 1

        theme_path.write_text(json.dumps(theme, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        updated += 1

    print(f"Updated {updated} themes; added {created_status_panels} native status panels.")


if __name__ == "__main__":
    main()
