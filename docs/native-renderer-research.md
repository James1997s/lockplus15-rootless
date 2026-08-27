# SpecialLock Native Renderer Research

## Objective

Replace package-local HTML/WebKit theme execution with **UIKit, Core Animation, Core Graphics, and ImageIO-backed assets**. The implementation remains a visual-only subview of the established SpringBoard date-host hierarchy, with no `UIWindow`, no touch handling, no remote content, and no background downloading.

## Platform findings

Apple documents `CALayer` as the visual-content and geometry object that can animate its own presentation properties. `UIView` provides a non-nil backing `CALayer`; custom sublayers should therefore be attached to the renderer view rather than using an additional window. This maps directly to SpecialLock backgrounds, frames, opacity, transforms, shadows, and overlay composition.[^calayer] [^uiview]

`CAShapeLayer` renders resolution-independent Bezier paths and exposes path, fill, stroke, line width, dash, and stroke start/end properties. It is the appropriate native primitive for ECG lines, rings, brush paths, stars, decorative outlines, and basic geometric artwork.[^shape]

`CAGradientLayer` provides multi-stop gradients and animatable color-position geometry. It can replace most CSS linear and radial gradient backgrounds without a browser.[^gradient]

`CADisplayLink` synchronizes custom drawing to display refresh and can be paused or invalidated. Its documentation recommends selecting a slower consistent rate when a full refresh rate cannot be met. For the iPhone 7 target, the renderer should use Core Animation for repeating movement and reserve a **1 Hz timer** for clock/date text; any truly procedural drawing should be capped at **30 fps** and be paused immediately when the lock hierarchy is not visible.[^displaylink]

`UIImageView` supports an image sequence, duration, repeat count, start, and stop methods. It can provide native image-sequence animations when a theme declares small embedded frame sequences, but the initial migration should keep one decoded image per image-view asset and use layer transforms/opacity to avoid unnecessary memory pressure.[^imageview]

## Native conversion rules

| HTML/Web capability | Native replacement |
|---|---|
| CSS gradient/background | `CAGradientLayer`, solid `CALayer`, or local `UIImageView` |
| CSS transform/opacity animation | `CABasicAnimation`, `CAKeyframeAnimation`, `CAAnimationGroup` |
| CSS radial dots, shapes, outlines | `CAShapeLayer` paths and repeat/transform layers |
| Live time/date text | `UILabel` with a 1 Hz `NSTimer` |
| ECG/brushstroke clock | Existing `CAShapeLayer` native renderer views |
| Local JPEG/PNG/WebP artwork | Embedded `UIImageView` decoded from the package path |
| HTML page, JavaScript, CSS, `WKWebView` | Removed from active rendering path |

## Migration outcome

The revised package should use **native JSON manifests only**. The catalog may retain each theme’s name and identifier, but all former folder themes will be represented as native scene manifests. The runtime will remove `WebKit` linking, `WKWebView`, JavaScript execution, and HTML folder loading. The package builder will embed only the native manifests and referenced local assets.

[^calayer]: [Apple Developer — CALayer](https://developer.apple.com/documentation/quartzcore/calayer)
[^uiview]: [Apple Developer — UIView.layer](https://developer.apple.com/documentation/uikit/uiview/layer)
[^shape]: [Apple Developer — CAShapeLayer](https://developer.apple.com/documentation/quartzcore/cashapelayer)
[^gradient]: [Apple Developer — CAGradientLayer](https://developer.apple.com/documentation/quartzcore/cagradientlayer)
[^displaylink]: [Apple Developer — CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink)
[^imageview]: [Apple Developer — UIImageView.animationImages](https://developer.apple.com/documentation/uikit/uiimageview/animationimages)
