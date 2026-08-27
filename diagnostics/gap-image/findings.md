# Bottom-gap findings

The supplied screenshot is 750 x 141 pixels, landscape, aspect ratio 250:47. Ordered horizontal crops confirm the same continuous dark-blue strip spans the full width at the bottom. The strip contains the lock-screen controls/icons and is not a localized wallpaper or clock asset defect. The visible theme artwork ends above this strip, indicating the shared overlay/host view or renderer height is shorter than the full lock-screen visual region.

Relevant source locations inspected:

- `LPOverlayCoordinator.m`, `attachToHostView:` creates the overlay using `hostView.bounds` and reuses it without explicitly refreshing the frame when the host bounds change.
- `LPNativeThemeRenderer.m`, folder WebView is initialized with `self.bounds` and flexible width/height autoresizing, but there is no explicit safe-area or scroll-view inset neutralization in the inspected section.
- `Tweak.xm` attaches to `self.superview` of `SBFLockScreenDateView`, so the chosen visual host may be the date container’s bounded region rather than the full lock-screen window.

The likely global remedy is to keep the existing host attachment but force the overlay and renderer/WebView to fill the host’s actual bounds, disable safe-area-induced insets, and expand the visual background beyond the host’s bottom inset where the hierarchy permits. This must be validated against representative folder themes without changing their internal clock positioning.
