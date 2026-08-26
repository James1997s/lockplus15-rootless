# LockPlus 15 Rootless

**LockPlus 15 Rootless** is a clean, source-available migration scaffold for a visual lock-screen overlay on **iOS 15.0–15.8.5**. It targets rootless Dopamine/ElleKit environments and has been configured for the iPhone 7’s A10 platform through the `arm64` architecture setting. Apple identifies the iPhone 7 as an A10 Fusion device, while Dopamine documents A8–A13 support across iOS 15 and later supported versions. [1] [2]

> **Status:** This is an early visual-only port. The overlay deliberately leaves Apple’s standard lock, unlock, notification, camera, and flashlight gestures under SpringBoard control. It has not been hardware-tested; build and test on a non-essential device before relying on it.

| Area | Current implementation | Notes |
|---|---|---|
| Package scheme | Rootless Theos | Installs under `/var/jb` through `THEOS_PACKAGE_SCHEME=rootless`. [3] |
| Target | `arm64`, iOS 15.0+ | Appropriate for an iPhone 7; legacy `armv7` is intentionally not built. |
| Injection | Logos / ElleKit-compatible Substrate surface | ElleKit supports the Substrate and libhooker APIs. [4] |
| Lock-screen UI | `SBDashBoardMainPageView` visual overlay | This private interface must be tested against each supported firmware build. |
| Themes | Bundled JSON plus full GitHub catalog sync | All valid themes in `themes/catalog.json` are cached locally. |
| Legacy materials | Excluded | The repository contains no legacy binaries, third-party themes, fonts, images, or original LockPlus web assets. |

## What the project does

At attachment time, the tweak places a transparent `WKWebView` above the iOS 15 lock-screen main page. The web view is **non-interactive** so that stock SpringBoard gestures continue to function. It loads the selected JSON theme immediately from local storage and then fetches the complete HTTPS catalog from this repository. Every valid catalog theme is cached in `/var/jb/var/mobile/Library/LockPlus15/Themes/`; the web view reloads only if the active theme changed.

The synchronizer accepts only same-host, relative `.json` records from `themes/catalog.json`. It rejects non-HTTPS locations, duplicate or unsafe IDs, more than 64 catalog items, themes with external widgets, non-string properties, and `javascript:` URLs. This makes the new repository the single trusted theme source and avoids relying on the discontinued legacy theme server.

## Build prerequisites

Use a rootless-capable Theos environment with an iOS 15 SDK, `libroot`/`rootless.h`, and an arm64 toolchain. Theos states that rootless projects must be recompiled, installed beneath `/var/jb`, and configured using `THEOS_PACKAGE_SCHEME=rootless`; it also illustrates an iOS 15 `arm64` target for rootless projects. [3]

| Requirement | Expected value |
|---|---|
| Theos package scheme | `rootless` |
| Build target | `iphone:clang:latest:15.0` |
| Architecture | `arm64` |
| Runtime dependency | `ellekit` |
| Preferences dependency | `preferenceloader` |
| Build host | macOS with Xcode is recommended for the most reliable iOS toolchain support |

Build the package from the repository root:

```sh
make clean package
```

The resulting `.deb` is produced under `packages/`. Install it with a rootless package manager or transfer it to the test device and install it with the package-management workflow you normally use. After installation, open **Settings → LockPlus 15**, enable the overlay, choose a theme, and select **Sync All Themes from GitHub**. The injected process receives the change notification and refreshes its catalog cache.

## Themes

The repository contains three original, text-only sample themes: **Aurora**, **Midnight**, and **Sunset**. They use only system fonts and CSS text styling, so they do not require additional image or font assets. The theme manifest is public at [`themes/catalog.json`](themes/catalog.json), and the app synchronizes every valid entry in that file.

A theme is a JSON object using the legacy renderer’s `placedElements` structure. All theme values must be strings. Do not use `type: "widget"`, JavaScript URLs, external scripts, proprietary fonts, or assets you do not have permission to distribute. See [THEMES.md](THEMES.md) for the complete publishing format.

## Migrating local legacy web assets

The old extracted package includes resources that may be copyrighted or owned by third parties. They are intentionally **not** committed to this public repository. If you own the necessary rights, make a local copy of the repository and run the supplied tool against your own extracted asset folder:

```sh
python3 tools/migrate_assets.py /path/to/Library/LockPlus
```

The argument must contain both `LockPlus/` and `Creator/` directories. The tool copies only static resources, preserves the new public themes, rewrites the known rootful file URLs, and does **not** copy or execute Mach-O binaries. Review the resulting local changes before packaging and do not publish materials without the appropriate rights.

## Trusted public theme catalog

The initial build is configured to synchronize from the catalog in this repository:

```text
https://raw.githubusercontent.com/James1997s/lockplus15-rootless/main/themes/catalog.json
```

This is the only trusted remote theme catalog used by the synchronizer. When adding or removing a theme, update both the JSON file and `themes/catalog.json` in the same commit.

## Limitations and next work

The supplied archive is a legacy iOS 8–11 binary package. Static inspection showed rootful paths and an obsolete Cydia Substrate framework dependency, so simply repackaging it would not make it rootless-compatible. The clean port replaces that binary path with a source-level rootless implementation. The remaining work for feature parity includes implementing an explicit, safe native bridge for music metadata, weather, user-selected wallpaper/artwork, and any interactive actions after iOS 15 device testing.

## References

[1]: https://support.apple.com/en-us/111943 "Apple: iPhone 7 technical specifications"
[2]: https://ellekit.space/dopamine/ "Dopamine official compatibility and rootless guidance"
[3]: https://theos.dev/docs/rootless "Theos rootless documentation"
[4]: https://github.com/tealbathingsuit/ellekit "ElleKit: supported hook APIs"
