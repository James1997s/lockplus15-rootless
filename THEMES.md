# Theme Catalog Guide

The project treats the repository’s `themes/catalog.json` as the **single trusted catalog**. A catalog refresh downloads and validates every entry, then stores the valid JSON files locally under:

```text
/var/jb/var/mobile/Library/LockPlus15/Themes/
```

The Preferences selector lists both the bundled themes and all downloaded themes. A selected theme is loaded from the local cache, so the lock screen does not depend on a network connection after a successful synchronization.

## Manifest format

`themes/catalog.json` must contain an object with a `themes` array. The synchronizer accepts at most **64** entries. Each entry requires an ID and a relative JSON URL.

```json
{
  "schemaVersion": 1,
  "catalogName": "LockPlus 15 Community Themes",
  "themes": [
    {
      "id": "aurora",
      "name": "Aurora",
      "url": "aurora.json"
    }
  ]
}
```

| Field | Requirement |
|---|---|
| `id` | 1–48 characters using only letters, digits, `_`, or `-`; must be unique. |
| `name` | Optional human-readable metadata for repository users. The current Preferences selector displays the title-cased ID. |
| `url` | A relative `.json` file path in the same GitHub raw-content directory. Absolute URLs and path traversal are rejected. |

## Theme format

Each theme must be a JSON object with a non-empty `placedElements` object. The element names follow the legacy LockPlus renderer identifiers, such as `clock`, `todaystrings`, `datestring`, or `daydatemonth`.

```json
{
  "placedElements": {
    "clock": {
      "type": "clock",
      "position": "absolute",
      "left": "50%",
      "top": "74px",
      "transform": "translateX(-50%)",
      "color": "#FFFFFF",
      "font-family": "HelveticaNeue-UltraLight",
      "font-size": "64px",
      "z-index": "10"
    }
  }
}
```

The current validator requires each property key and value to be a string. It rejects `type: "widget"` and any value containing `javascript:`. This is intentional: a public catalog should contain declarative visual data, not downloaded code.

## Publishing rules

Only publish themes that you created yourself or for which you have explicit redistribution permission. Do not commit paid themes, third-party fonts, copyrighted images, proprietary artwork, or copied legacy theme bundles. Prefer system fonts and CSS-only layouts, as demonstrated by Aurora, Midnight, and Sunset.

Test a new theme from a local copy before adding it to `catalog.json`. A malformed JSON file is ignored by the device synchronizer, but invalid entries should still be removed from the public manifest promptly.
