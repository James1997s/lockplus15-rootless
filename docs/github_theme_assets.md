# GitHub theme assets

LockPlus 15 uses GitHub as the theme source of truth. Refreshing Theme Manager downloads only the catalog; selecting a theme downloads that theme JSON and any declared assets. The downloaded files are cached locally and may be removed without changing the public repository.

A theme may declare a bounded `assets` array at its root. Each entry needs a safe `id`, a repository-relative image `url`, and the asset file's SHA-256 digest. The downloader accepts only `.jpg`, `.jpeg`, `.png`, or `.gif` image paths, rejects absolute paths and traversal sequences, checks that the URL resolves under the same trusted GitHub host as the catalog, verifies image data and its SHA-256 digest, and stores it under the selected theme's cache directory. Assets are limited to 2 MiB and image dimensions up to 4096 pixels.

```json
{
  "assets": [
    {
      "id": "wall-art",
      "url": "assets/example/wall-art.jpg",
      "sha256": "64-character lowercase SHA-256 digest"
    }
  ],
  "placedElements": {
    "wallArt": {
      "type": "image",
      "asset-id": "wall-art",
      "top": "170px",
      "width": "320px",
      "height": "180px",
      "opacity": "0.72",
      "border-radius": "20px",
      "z-index": "1"
    }
  }
}
```

Image elements are visual-only. They never enable touch interaction and remain inside the lock-screen date hierarchy, so the passcode, notifications, unlock gesture, camera, and flashlight controls remain system-owned. An image is available only after its selected theme and every declared asset finish validation and cache writing.

GIF assets are decoded locally after validation into a looping UIKit animated image. The downloader and renderer accept at most 48 frames, a maximum animated-image dimension of 1024 pixels, and a total decoded-frame budget of eight million pixels. Each frame delay is clamped to a conservative 0.04–0.50 second range, avoiding remote code, video playback, or network activity at render time. When iOS Reduce Motion is enabled, the renderer displays only the first GIF frame.

For new themes that use existing element types and this asset contract, publish the JSON and assets to the GitHub repository, add the record to `themes/catalog.json`, and refresh Theme Manager. No new Debian package is required.

## Visual widgets, animated wallpapers, and overlays

The GitHub contract also supports native visual widgets and wallpaper effects. A widget is a noninteractive informational panel rendered by the existing native label/panel primitives. Themes can set its position, colors, font, border, shadow, and safe animation fields. Widgets never receive touch input and do not run remote JavaScript or third-party widget code.

Animated wallpapers may combine a validated local image asset with gradient, blob, particle, ring, and pulse effects. The renderer treats each wallpaper/effect element as a visual-only layer. It honors iOS Reduce Motion for continuous movement.

Overlay elements are restricted to the same lock-screen content hierarchy used by LockPlus. They must remain noninteractive and use a conservative visual z-order. They do not create a separate UIWindow, do not attach above SpringBoard notification views, and do not cover the passcode, camera, flashlight, or unlock transition. Notifications therefore remain system-owned and visible when SpringBoard presents them.


## Expanded visual-only capability set

The theme engine may be extended with deterministic, noninteractive visual primitives such as shapes, progress/meter displays, orbiting accents, shimmer, slide, and spin animations. These are configured only through bounded JSON properties and are rendered in the existing safe lock-screen content hierarchy.

The engine does not execute remote JavaScript, load remote plug-ins, attach a new window above SpringBoard, or expose touch-interactive widgets. It also does not take ownership of the passcode, notifications, camera, flashlight, media controls, or unlock gesture. Those remain iOS system controls rather than theme elements.
