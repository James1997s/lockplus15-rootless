# Native-only SpecialLock Theme Schema

## Runtime contract

Every selectable theme is a native JSON manifest with `format: "native"`. The renderer accepts only native declarations and draws them with `UIView`, `UILabel`, `UIImageView`, `CAGradientLayer`, `CAShapeLayer`, and Core Animation. No catalog record or manifest may refer to `folder`, HTML, CSS, JavaScript, a `WKWebView`, or a browser URL.

```json
{
  "schemaVersion": 2,
  "format": "native",
  "id": "theme-id",
  "assets": [
    {"id": "wallpaper", "url": "assets/theme-id/wallpaper.jpg", "sha256": "..."}
  ],
  "placedElements": {
    "background": {"type": "wallpaper", "gradient": "#111111,#222222"},
    "art": {"type": "image", "asset-id": "wallpaper", "image-role": "wallpaper", "opacity": "0.86"},
    "orbit": {"type": "ring", "top": "120", "diameter": "244", "stroke-width": "2", "color": "#ffffff", "rotation-duration": "12"},
    "clock": {"type": "clock", "top": "188", "font-size": "68", "font-weight": "700", "color": "#ffffff"},
    "date": {"type": "date", "top": "264", "font-size": "14", "font-weight": "600", "color": "#ffffff"}
  }
}
```

## Native element vocabulary

| Element type | Native implementation | Intended use |
|---|---|---|
| `wallpaper` | `CAGradientLayer`-backed `UIView` | Gradient base layer |
| `image` | `UIImageView` from a hashed package asset | Full wallpaper or framed artwork |
| `clock`, `date`, `word-clock`, `text`, `panel`, `widget`, `overlay` | `UILabel` | Live or static typography |
| `ring` | `CAShapeLayer` and `CABasicAnimation` | Orbit, segmented circle, and line motifs |
| `blob`, `particle` | Existing native effect views plus Core Animation | Ambient motion and color accents |
| `ecg-time`, `brushstroke-time` | Existing custom `CAShapeLayer` renderer views | High-value bespoke animated clocks |

## Conversion strategy

The 14 historical folder/HTML catalog records are converted in place to `format: "native"`. Their names and identifiers remain unchanged, preserving the Theme Manager’s selected preference. Existing artwork files become hashes in `assets`; themes without artwork receive native gradients, rings, particles, and labels. Local wallpapers remain native `UIImageView` assets.

| Former folder theme group | Native replacement |
|---|---|
| Image-backed designs: One UI, Aurora, Ink Garden, Desert, Ocean, Geometric, Purple Anime, Silent Film, Stencil | Gradient base, package-local wallpaper/art view, native clock/date, optional ring or particles |
| CSS/vector designs: Cat, iOS 26, Neon, HTML Test Lock, Xen Cat | Gradient and native effect layers, text/ring/particle composition, native clock/date |
| Existing JSON designs: Animated Art Gallery, Pulse Timeline, Brushstroke Time | Preserved as already-native renderers |

## Performance policy

The renderer has no `WKWebView`, no JavaScript runtime, no web-process lifecycle, no browser document reloads, and no persistent 60 Hz timer. Time/date text updates once per second. Core Animation owns repeating opacity, transform, ring, and gradient effects. The coordinator hides the native renderer synchronously at dashboard departure and disposes it after the transition completes.
