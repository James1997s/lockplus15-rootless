#import "LPNativeThemeRenderer.h"
#import <rootless.h>
#import <ImageIO/ImageIO.h>

static NSString * const kLPThemePreferencesDomain = @"com.example.lockplus15";

static UIImage *LPImageFromThemeAssetData(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    const unsigned char *bytes = data.bytes;
    BOOL isGIF = data.length >= 6 && bytes[0] == 'G' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == '8' && (bytes[4] == '7' || bytes[4] == '9') && bytes[5] == 'a';
    if (!isGIF) {
        return [UIImage imageWithData:data];
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source == NULL) {
        return nil;
    }
    size_t frameCount = CGImageSourceGetCount(source);
    NSDictionary *sourceProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSUInteger width = [sourceProperties[(NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [sourceProperties[(NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    BOOL safeAnimatedDimensions = width > 0 && height > 0 && width <= 1024 && height <= 1024 && ((uint64_t)width * (uint64_t)height * (uint64_t)MIN(frameCount, (size_t)48) <= 8ULL * 1024ULL * 1024ULL);
    if (frameCount == 0 || frameCount > 48 || !safeAnimatedDimensions) {
        CFRelease(source);
        return nil;
    }
    if (frameCount == 1) {
        UIImage *staticImage = [UIImage imageWithData:data];
        CFRelease(source);
        return staticImage;
    }
    if (UIAccessibilityIsReduceMotionEnabled()) {
        CGImageRef firstFrame = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        UIImage *staticImage = firstFrame ? [UIImage imageWithCGImage:firstFrame scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp] : nil;
        if (firstFrame != NULL) {
            CGImageRelease(firstFrame);
        }
        CFRelease(source);
        return staticImage;
    }
    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:MIN(frameCount, (size_t)48)];
    NSTimeInterval totalDuration = 0.0;
    for (size_t index = 0; index < frameCount; index++) {
        CGImageRef frame = CGImageSourceCreateImageAtIndex(source, index, NULL);
        if (frame == NULL) {
            continue;
        }
        NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
        NSDictionary *gifProperties = [properties[(NSString *)kCGImagePropertyGIFDictionary] isKindOfClass:NSDictionary.class] ? properties[(NSString *)kCGImagePropertyGIFDictionary] : @{};
        NSTimeInterval delay = [gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
        if (delay < 0.04) {
            delay = [gifProperties[(NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
        }
        delay = MIN(MAX(delay, 0.04), 0.50);
        totalDuration += delay;
        [frames addObject:[UIImage imageWithCGImage:frame scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]];
        CGImageRelease(frame);
    }
    CFRelease(source);
    return frames.count > 1 ? [UIImage animatedImageWithImages:frames duration:totalDuration] : frames.firstObject;
}

@interface LPGradientWallpaperView : UIView
@property (nonatomic, strong) CAGradientLayer *gradientLayer;
- (void)applyVisualAnimationFromProperties:(NSDictionary<NSString *, NSString *> *)properties;
@end

@implementation LPGradientWallpaperView

- (instancetype)initWithColors:(NSArray<UIColor *> *)colors {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _gradientLayer = [CAGradientLayer layer];
        NSMutableArray *cgColors = [NSMutableArray array];
        for (UIColor *color in colors) {
            [cgColors addObject:(__bridge id)color.CGColor];
        }
        _gradientLayer.colors = cgColors;
        _gradientLayer.startPoint = CGPointMake(0.10, 0.0);
        _gradientLayer.endPoint = CGPointMake(0.90, 1.0);
        [self.layer insertSublayer:_gradientLayer atIndex:0];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradientLayer.frame = self.bounds;
}

- (void)applyVisualAnimationFromProperties:(NSDictionary<NSString *, NSString *> *)properties {
    NSString *animation = [properties[@"animation"] isKindOfClass:NSString.class] ? properties[@"animation"] : nil;
    if (UIAccessibilityIsReduceMotionEnabled() || ![animation isEqualToString:@"gradient-shift"]) {
        return;
    }
    CGFloat duration = [properties[@"animation-duration"] doubleValue];
    duration = MIN(MAX(duration > 0.0 ? duration : 8.0, 2.0), 16.0);
    CABasicAnimation *shift = [CABasicAnimation animationWithKeyPath:@"startPoint"];
    shift.fromValue = [NSValue valueWithCGPoint:CGPointMake(0.10, 0.0)];
    shift.toValue = [NSValue valueWithCGPoint:CGPointMake(0.90, 0.15)];
    shift.duration = duration;
    shift.autoreverses = YES;
    shift.repeatCount = HUGE_VALF;
    shift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.gradientLayer addAnimation:shift forKey:@"lockplus.gradient-shift"];
}

@end

@interface LPLiquidBlobView : UIView
@property (nonatomic, strong) CAShapeLayer *blobLayer;
@property (nonatomic, assign) CGFloat normalizedX;
@property (nonatomic, assign) CGFloat top;
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, assign) CGFloat alphaValue;
@property (nonatomic, assign) CGFloat motionDistance;
@property (nonatomic, assign) CGFloat motionDuration;
@property (nonatomic, copy) NSString *motion;
@property (nonatomic, assign) BOOL motionStarted;
- (instancetype)initWithColor:(UIColor *)color
                  normalizedX:(CGFloat)normalizedX
                         top:(CGFloat)top
                        size:(CGFloat)size
                       alpha:(CGFloat)alpha
              motionDistance:(CGFloat)motionDistance
               motionDuration:(CGFloat)motionDuration
                       motion:(NSString *)motion;
@end

@implementation LPLiquidBlobView

- (instancetype)initWithColor:(UIColor *)color
                  normalizedX:(CGFloat)normalizedX
                         top:(CGFloat)top
                        size:(CGFloat)size
                       alpha:(CGFloat)alpha
              motionDistance:(CGFloat)motionDistance
               motionDuration:(CGFloat)motionDuration
                       motion:(NSString *)motion {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _normalizedX = MIN(MAX(normalizedX, 0.0), 1.0);
        _top = top;
        _diameter = MIN(MAX(size, 14.0), 340.0);
        _alphaValue = MIN(MAX(alpha, 0.08), 1.0);
        _motionDistance = MIN(MAX(motionDistance, 8.0), 260.0);
        _motionDuration = MIN(MAX(motionDuration, 2.0), 24.0);
        _motion = [motion copy] ?: @"lava";
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;

        _blobLayer = [CAShapeLayer layer];
        _blobLayer.fillColor = [color colorWithAlphaComponent:_alphaValue].CGColor;
        _blobLayer.shadowColor = color.CGColor;
        _blobLayer.shadowOpacity = MIN(0.95, _alphaValue + 0.20);
        _blobLayer.shadowRadius = MIN(MAX(_diameter * 0.20, 8.0), 42.0);
        _blobLayer.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_blobLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat centerX = self.bounds.size.width * self.normalizedX;
    CGFloat centerY = self.top + (self.diameter * 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(centerX - (self.diameter * 0.5), centerY - (self.diameter * 0.5), self.diameter, self.diameter)];
    self.blobLayer.frame = self.bounds;
    self.blobLayer.path = path.CGPath;
    if (!self.motionStarted && self.bounds.size.width > 0.0 && self.bounds.size.height > 0.0) {
        self.motionStarted = YES;
        [self startMotion];
    }
}

- (void)startMotion {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    CABasicAnimation *vertical = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    if ([self.motion isEqualToString:@"drift"]) {
        vertical.fromValue = @(-self.motionDistance * 0.35);
        vertical.toValue = @(self.motionDistance * 0.35);
    } else {
        vertical.fromValue = @(self.motionDistance);
        vertical.toValue = @(-self.motionDistance);
    }
    vertical.duration = self.motionDuration;
    vertical.autoreverses = YES;
    vertical.repeatCount = HUGE_VALF;
    vertical.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.blobLayer addAnimation:vertical forKey:@"lockplus.liquid.vertical"];

    CAKeyframeAnimation *shape = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    shape.values = @[ @0.82, @1.08, @0.94, @1.03, @0.82 ];
    shape.keyTimes = @[ @0.0, @0.28, @0.55, @0.78, @1.0 ];
    shape.duration = self.motionDuration * 0.82;
    shape.repeatCount = HUGE_VALF;
    shape.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.blobLayer addAnimation:shape forKey:@"lockplus.liquid.shape"];

    CABasicAnimation *sway = [CABasicAnimation animationWithKeyPath:@"transform.translation.x"];
    sway.fromValue = @(-self.motionDistance * 0.18);
    sway.toValue = @(self.motionDistance * 0.18);
    sway.duration = self.motionDuration * 0.66;
    sway.autoreverses = YES;
    sway.repeatCount = HUGE_VALF;
    sway.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.blobLayer addAnimation:sway forKey:@"lockplus.liquid.sway"];
}

@end

@interface LPOrbitRingView : UIView
@property (nonatomic, strong) CAShapeLayer *ringLayer;
@property (nonatomic, assign) CGFloat top;
@property (nonatomic, assign) CGFloat diameter;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat arcStartDegrees;
@property (nonatomic, assign) CGFloat arcLengthDegrees;
@property (nonatomic, assign) CGFloat rotationDuration;
@property (nonatomic, assign) BOOL clockwise;
@property (nonatomic, assign) BOOL rotationStarted;
- (instancetype)initWithColor:(UIColor *)color
                          top:(CGFloat)top
                     diameter:(CGFloat)diameter
                  strokeWidth:(CGFloat)strokeWidth
              arcStartDegrees:(CGFloat)arcStartDegrees
             arcLengthDegrees:(CGFloat)arcLengthDegrees
                         dash:(NSString *)dash
                      opacity:(CGFloat)opacity
             rotationDuration:(CGFloat)rotationDuration
                    clockwise:(BOOL)clockwise;
@end

@implementation LPOrbitRingView

- (instancetype)initWithColor:(UIColor *)color
                          top:(CGFloat)top
                     diameter:(CGFloat)diameter
                  strokeWidth:(CGFloat)strokeWidth
              arcStartDegrees:(CGFloat)arcStartDegrees
             arcLengthDegrees:(CGFloat)arcLengthDegrees
                         dash:(NSString *)dash
                      opacity:(CGFloat)opacity
             rotationDuration:(CGFloat)rotationDuration
                    clockwise:(BOOL)clockwise {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _top = top;
        _diameter = MIN(MAX(diameter, 44.0), 350.0);
        _strokeWidth = MIN(MAX(strokeWidth, 1.0), 18.0);
        _arcStartDegrees = arcStartDegrees;
        _arcLengthDegrees = MIN(MAX(arcLengthDegrees, 12.0), 360.0);
        _rotationDuration = MIN(MAX(rotationDuration, 0.65), 24.0);
        _clockwise = clockwise;
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;

        _ringLayer = [CAShapeLayer layer];
        _ringLayer.fillColor = UIColor.clearColor.CGColor;
        _ringLayer.strokeColor = [color colorWithAlphaComponent:MIN(MAX(opacity, 0.08), 1.0)].CGColor;
        _ringLayer.lineWidth = _strokeWidth;
        _ringLayer.lineCap = kCALineCapRound;
        _ringLayer.shadowColor = color.CGColor;
        _ringLayer.shadowOpacity = MIN(0.96, MAX(0.30, opacity));
        _ringLayer.shadowRadius = MIN(MAX(_strokeWidth * 2.2, 4.0), 24.0);
        _ringLayer.shadowOffset = CGSizeZero;
        if ([dash isKindOfClass:NSString.class] && dash.length > 0) {
            NSMutableArray<NSNumber *> *pattern = [NSMutableArray array];
            for (NSString *part in [dash componentsSeparatedByString:@"|"]) {
                CGFloat value = part.doubleValue;
                if (value > 0.0 && value <= 80.0) {
                    [pattern addObject:@(value)];
                }
            }
            if (pattern.count >= 2) {
                _ringLayer.lineDashPattern = pattern;
            }
        }
        [self.layer addSublayer:_ringLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat centerX = CGRectGetMidX(self.bounds);
    CGFloat centerY = self.top + (self.diameter * 0.5);
    CGFloat radius = MAX(8.0, (self.diameter - self.strokeWidth) * 0.5);
    CGFloat start = (self.arcStartDegrees - 90.0) * M_PI / 180.0;
    CGFloat end = start + (self.arcLengthDegrees * M_PI / 180.0);
    // Use a ring-sized layer positioned at the actual ring center. Rotating a
    // full-screen shape layer causes an incorrect pivot and can look static.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.ringLayer.bounds = CGRectMake(0.0, 0.0, self.diameter, self.diameter);
    self.ringLayer.position = CGPointMake(centerX, centerY);
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(self.diameter * 0.5, self.diameter * 0.5) radius:radius startAngle:start endAngle:end clockwise:YES];
    self.ringLayer.path = path.CGPath;
    [CATransaction commit];
    if (!self.rotationStarted && self.bounds.size.width > 0.0) {
        self.rotationStarted = YES;
        [self startRotation];
    }
}

- (void)startRotation {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    [self.ringLayer removeAnimationForKey:@"lockplus.orbit.rotation"];
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = @0.0;
    rotation.toValue = @(self.clockwise ? (M_PI * 2.0) : -(M_PI * 2.0));
    rotation.beginTime = 0.0;
    rotation.duration = self.rotationDuration;
    rotation.repeatCount = HUGE_VALF;
    rotation.removedOnCompletion = NO;
    rotation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.ringLayer addAnimation:rotation forKey:@"lockplus.orbit.rotation"];
}

@end

@interface LPNativeThemeElement : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *properties;
@property (nonatomic, strong) UILabel *label;
@end

@implementation LPNativeThemeElement
@end

@interface LPNativeThemeRenderer ()
@property (nonatomic, strong) NSMutableArray<LPNativeThemeElement *> *elements;
@property (nonatomic, strong) NSTimer *updateTimer;
@end

@implementation LPNativeThemeRenderer

- (instancetype)initWithThemeJSONString:(NSString *)themeJSONString {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.elements = [NSMutableArray array];
        [self reloadWithThemeJSONString:themeJSONString];
    }
    return self;
}

- (void)dealloc {
    [self stopRendering];
}

- (void)stopRendering {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
}

- (NSString *)selectedThemeID {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("theme"), (__bridge CFStringRef)kLPThemePreferencesDomain);
    NSString *themeID = nil;
    if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
        themeID = [(__bridge NSString *)value copy];
    }
    if (value != NULL) {
        CFRelease(value);
    }
    return themeID.length > 0 ? themeID : @"aurora";
}

- (UIImage *)cachedImageAssetWithID:(NSString *)assetID {
    if (assetID.length == 0 || assetID.length > 48) {
        return nil;
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"];
    if ([[assetID stringByTrimmingCharactersInSet:allowed] length] != 0) {
        return nil;
    }
    NSString *unrootedAssetPath = [[@"/var/mobile/Library/LockPlus15/Themes/Assets" stringByAppendingPathComponent:[self selectedThemeID]] stringByAppendingPathComponent:assetID];
    NSString *assetPath = ROOT_PATH_NS(unrootedAssetPath);
    return LPImageFromThemeAssetData([NSData dataWithContentsOfFile:assetPath]);
}

- (void)reloadWithThemeJSONString:(NSString *)themeJSONString {
    [self stopRendering];
    for (UIView *view in self.subviews) {
        [view removeFromSuperview];
    }
    [self.elements removeAllObjects];

    NSData *data = [themeJSONString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *theme = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *placedElements = [theme isKindOfClass:NSDictionary.class] ? theme[@"placedElements"] : nil;
    if (![placedElements isKindOfClass:NSDictionary.class] || placedElements.count == 0) {
        placedElements = @{
            @"clock": @{ @"type": @"clock", @"top": @"72px", @"color": @"#FFFFFF", @"font-size": @"60px", @"font-weight": @"700" },
            @"todaystrings": @{ @"type": @"date", @"top": @"144px", @"color": @"#FFFFFF", @"font-size": @"16px", @"font-weight": @"500" }
        };
    }

    NSArray<NSString *> *identifiers = [[placedElements allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *first, NSString *second) {
        NSDictionary *firstProperties = placedElements[first];
        NSDictionary *secondProperties = placedElements[second];
        CGFloat firstTop = [self cssNumber:firstProperties[@"top"] defaultValue:0.0];
        CGFloat secondTop = [self cssNumber:secondProperties[@"top"] defaultValue:0.0];
        if (firstTop < secondTop) return NSOrderedAscending;
        if (firstTop > secondTop) return NSOrderedDescending;
        return [first compare:second];
    }];

    for (NSString *identifier in identifiers) {
        NSDictionary *properties = placedElements[identifier];
        if (![properties isKindOfClass:NSDictionary.class]) {
            continue;
        }

        NSString *type = [properties[@"type"] isKindOfClass:NSString.class] ? properties[@"type"] : @"text";
        if ([type isEqualToString:@"wallpaper"]) {
            LPGradientWallpaperView *wallpaper = [[LPGradientWallpaperView alloc] initWithColors:[self wallpaperColorsFromProperties:properties]];
            wallpaper.translatesAutoresizingMaskIntoConstraints = NO;
            [self insertSubview:wallpaper atIndex:0];
            [NSLayoutConstraint activateConstraints:@[
                [wallpaper.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [wallpaper.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [wallpaper.topAnchor constraintEqualToAnchor:self.topAnchor],
                [wallpaper.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            ]];
            [wallpaper applyVisualAnimationFromProperties:properties];
            continue;
        }
        if ([type isEqualToString:@"image"]) {
            NSString *assetID = [properties[@"asset-id"] isKindOfClass:NSString.class] ? properties[@"asset-id"] : nil;
            UIImage *image = [self cachedImageAssetWithID:assetID];
            if (image == nil) {
                continue;
            }
            UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
            imageView.userInteractionEnabled = NO;
            imageView.clipsToBounds = YES;
            imageView.contentMode = UIViewContentModeScaleAspectFill;
            imageView.alpha = MIN(MAX([self cssNumber:properties[@"opacity"] defaultValue:1.0], 0.05), 1.0);
            imageView.translatesAutoresizingMaskIntoConstraints = NO;
            CGFloat cornerRadius = [self cssNumber:properties[@"border-radius"] defaultValue:0.0];
            imageView.layer.cornerRadius = MAX(0.0, MIN(cornerRadius, 90.0));
            imageView.layer.masksToBounds = cornerRadius > 0.0;
            imageView.layer.zPosition = [self cssNumber:properties[@"z-index"] defaultValue:0.0];
            NSString *role = [properties[@"image-role"] isKindOfClass:NSString.class] ? properties[@"image-role"] : @"panel";
            if ([role isEqualToString:@"wallpaper"]) {
                [self insertSubview:imageView atIndex:MIN((NSUInteger)1, self.subviews.count)];
                [NSLayoutConstraint activateConstraints:@[
                    [imageView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                    [imageView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                    [imageView.topAnchor constraintEqualToAnchor:self.topAnchor],
                    [imageView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                ]];
            } else {
                [self addSubview:imageView];
                CGFloat top = [self cssNumber:properties[@"top"] defaultValue:160.0];
                CGFloat width = MIN(MAX([self cssNumber:properties[@"width"] defaultValue:320.0], 40.0), 360.0);
                CGFloat height = MIN(MAX([self cssNumber:properties[@"height"] defaultValue:180.0], 24.0), 540.0);
                [NSLayoutConstraint activateConstraints:@[
                    [imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                    [imageView.topAnchor constraintEqualToAnchor:self.topAnchor constant:top],
                    [imageView.widthAnchor constraintEqualToConstant:width],
                    [imageView.heightAnchor constraintEqualToConstant:height],
                ]];
            }
            [self applyVisualAnimationFromProperties:properties toView:imageView];
            continue;
        }
        if ([type isEqualToString:@"ring"]) {
            UIColor *ringColor = [self colorFromCSS:properties[@"color"] fallback:UIColor.cyanColor];
            CGFloat top = [self cssNumber:properties[@"top"] defaultValue:150.0];
            CGFloat diameter = [self cssNumber:properties[@"diameter"] defaultValue:230.0];
            CGFloat strokeWidth = [self cssNumber:properties[@"stroke-width"] defaultValue:3.0];
            CGFloat arcStart = [self cssNumber:properties[@"arc-start"] defaultValue:0.0];
            CGFloat arcLength = [self cssNumber:properties[@"arc-length"] defaultValue:360.0];
            CGFloat opacity = [self cssNumber:properties[@"opacity"] defaultValue:0.82];
            CGFloat duration = [self cssNumber:properties[@"rotation-duration"] defaultValue:3.0];
            NSString *direction = [properties[@"rotation-direction"] isKindOfClass:NSString.class] ? properties[@"rotation-direction"] : @"clockwise";
            NSString *dash = [properties[@"dash"] isKindOfClass:NSString.class] ? properties[@"dash"] : nil;
            LPOrbitRingView *ring = [[LPOrbitRingView alloc] initWithColor:ringColor
                                                                         top:top
                                                                    diameter:diameter
                                                                 strokeWidth:strokeWidth
                                                             arcStartDegrees:arcStart
                                                            arcLengthDegrees:arcLength
                                                                        dash:dash
                                                                     opacity:opacity
                                                            rotationDuration:duration
                                                                   clockwise:![direction isEqualToString:@"counterclockwise"]];
            ring.translatesAutoresizingMaskIntoConstraints = NO;
            [self insertSubview:ring atIndex:MIN((NSUInteger)1, self.subviews.count)];
            [NSLayoutConstraint activateConstraints:@[
                [ring.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [ring.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [ring.topAnchor constraintEqualToAnchor:self.topAnchor],
                [ring.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            ]];
            continue;
        }
        if ([type isEqualToString:@"blob"] || [type isEqualToString:@"particle"]) {
            UIColor *effectColor = [self colorFromCSS:properties[@"color"] fallback:UIColor.whiteColor];
            CGFloat normalizedX = [self cssNormalizedPosition:properties[@"x"] defaultValue:0.5];
            CGFloat top = [self cssNumber:properties[@"top"] defaultValue:180.0];
            CGFloat size = [self cssNumber:properties[@"size"] defaultValue:[type isEqualToString:@"particle"] ? 18.0 : 96.0];
            CGFloat alpha = [self cssNumber:properties[@"opacity"] defaultValue:[type isEqualToString:@"particle"] ? 0.42 : 0.58];
            CGFloat motionDistance = [self cssNumber:properties[@"motion-distance"] defaultValue:[type isEqualToString:@"particle"] ? 36.0 : 124.0];
            CGFloat motionDuration = [self cssNumber:properties[@"motion-duration"] defaultValue:[type isEqualToString:@"particle"] ? 7.0 : 11.0];
            NSString *motion = [properties[@"motion"] isKindOfClass:NSString.class] ? properties[@"motion"] : @"lava";
            LPLiquidBlobView *effect = [[LPLiquidBlobView alloc] initWithColor:effectColor
                                                                    normalizedX:normalizedX
                                                                           top:top
                                                                          size:size
                                                                         alpha:alpha
                                                                motionDistance:motionDistance
                                                                 motionDuration:motionDuration
                                                                         motion:motion];
            effect.translatesAutoresizingMaskIntoConstraints = NO;
            // Background effects are inserted below all text and panels, and are
            // permanently noninteractive so SpringBoard retains every gesture.
            [self insertSubview:effect atIndex:MIN((NSUInteger)1, self.subviews.count)];
            [NSLayoutConstraint activateConstraints:@[
                [effect.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [effect.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
                [effect.topAnchor constraintEqualToAnchor:self.topAnchor],
                [effect.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            ]];
            continue;
        }

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.userInteractionEnabled = NO;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.55;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self applyAppearanceFromProperties:properties toLabel:label];
        [self applyVisualAnimationFromProperties:properties toView:label];

        [self addSubview:label];
        CGFloat padding = [self cssNumber:properties[@"padding"] defaultValue:0.0];
        CGFloat top = [self cssNumber:properties[@"top"] defaultValue:72.0];
        CGFloat defaultHeight = [type isEqualToString:@"clock"] ? 76.0 : ([type isEqualToString:@"word-clock"] ? 84.0 : (([type isEqualToString:@"panel"] || [type isEqualToString:@"widget"] || [type isEqualToString:@"overlay"]) ? 72.0 : 34.0));
        CGFloat width = [self cssNumber:properties[@"width"] defaultValue:320.0] + (padding * 2.0);
        CGFloat height = [self cssNumber:properties[@"height"] defaultValue:defaultHeight] + (padding * 2.0);
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:top],
            [label.widthAnchor constraintEqualToConstant:MIN(MAX(width, 40.0), 360.0)],
            [label.heightAnchor constraintEqualToConstant:MAX(height, 20.0)],
        ]];

        LPNativeThemeElement *element = [[LPNativeThemeElement alloc] init];
        element.identifier = identifier;
        element.type = type;
        element.properties = properties;
        element.label = label;
        [self.elements addObject:element];
        if ([type isEqualToString:@"text"] || [type isEqualToString:@"panel"] || [type isEqualToString:@"widget"] || [type isEqualToString:@"overlay"]) {
            [self applyText:[properties[@"innerHTML"] isKindOfClass:NSString.class] ? properties[@"innerHTML"] : @"" toElement:element];
        }
    }

    [self updateDynamicLabels];
    __weak typeof(self) weakSelf = self;
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updateDynamicLabels];
    }];
}

- (NSString *)wordClockTextForDate:(NSDate *)date {
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    static NSArray<NSString *> *numbers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        numbers = @[ @"TWELVE", @"ONE", @"TWO", @"THREE", @"FOUR", @"FIVE", @"SIX", @"SEVEN", @"EIGHT", @"NINE", @"TEN", @"ELEVEN" ];
    });
    NSInteger hour = components.hour % 12;
    NSInteger minute = components.minute;
    NSString *minuteWords = nil;
    if (minute == 0) {
        minuteWords = @"O'CLOCK";
    } else if (minute < 10) {
        minuteWords = [NSString stringWithFormat:@"OH %ld", (long)minute];
    } else if (minute < 20) {
        NSArray<NSString *> *teens = @[ @"TEN", @"ELEVEN", @"TWELVE", @"THIRTEEN", @"FOURTEEN", @"FIFTEEN", @"SIXTEEN", @"SEVENTEEN", @"EIGHTEEN", @"NINETEEN" ];
        minuteWords = teens[(NSUInteger)(minute - 10)];
    } else {
        NSArray<NSString *> *tens = @[ @"", @"", @"TWENTY", @"THIRTY", @"FORTY", @"FIFTY" ];
        NSString *tensWord = tens[(NSUInteger)(minute / 10)];
        NSInteger remainder = minute % 10;
        minuteWords = remainder == 0 ? tensWord : [NSString stringWithFormat:@"%@ %@", tensWord, numbers[(NSUInteger)remainder]];
    }
    return [NSString stringWithFormat:@"IT IS\n%@ %@", numbers[(NSUInteger)hour], minuteWords];
}

- (void)updateDynamicLabels {
    NSDate *now = [NSDate date];
    for (LPNativeThemeElement *element in self.elements) {
        if ([element.type isEqualToString:@"word-clock"]) {
            [self applyText:[self wordClockTextForDate:now] toElement:element];
        } else if ([element.type isEqualToString:@"clock"] || [element.type isEqualToString:@"date"]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = NSLocale.currentLocale;
            NSString *defaultFormat = [element.type isEqualToString:@"clock"] ? @"HH:mm" : @"EEEE, MMMM d";
            NSString *format = [element.properties[@"time-format"] isKindOfClass:NSString.class] ? element.properties[@"time-format"] : defaultFormat;
            // Restrict formatting input to normal Unicode date pattern characters.
            NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz :/,-."];
            if (format.length == 0 || format.length > 48 || [[format stringByTrimmingCharactersInSet:allowed] length] != 0) {
                format = defaultFormat;
            }
            formatter.dateFormat = format;
            NSString *text = [formatter stringFromDate:now];
            if ([element.properties[@"uppercase"] isEqualToString:@"true"]) {
                text = text.uppercaseString;
            }
            [self applyText:text toElement:element];
        }
    }
}

- (NSArray<UIColor *> *)wallpaperColorsFromProperties:(NSDictionary<NSString *, NSString *> *)properties {
    NSString *gradient = properties[@"gradient"];
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    if ([gradient isKindOfClass:NSString.class]) {
        for (NSString *part in [gradient componentsSeparatedByString:@"|"]) {
            UIColor *color = [self colorFromCSS:part fallback:nil];
            if (color != nil) {
                [colors addObject:color];
            }
        }
    }
    if (colors.count == 0) {
        UIColor *base = [self colorFromCSS:properties[@"background-color"] fallback:nil];
        if (base != nil) {
            [colors addObject:base];
        }
    }
    if (colors.count == 0) {
        [colors addObjectsFromArray:@[
            [UIColor colorWithRed:0.05 green:0.07 blue:0.16 alpha:1.0],
            [UIColor colorWithRed:0.19 green:0.13 blue:0.37 alpha:1.0],
            [UIColor colorWithRed:0.48 green:0.20 blue:0.50 alpha:1.0],
        ]];
    }
    return colors;
}

- (void)applyText:(NSString *)text toElement:(LPNativeThemeElement *)element {
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text ?: @""];
    if (attributed.length > 0) {
        [attributed addAttribute:NSFontAttributeName value:element.label.font range:NSMakeRange(0, attributed.length)];
        [attributed addAttribute:NSForegroundColorAttributeName value:element.label.textColor range:NSMakeRange(0, attributed.length)];
        CGFloat kern = [self cssNumber:element.properties[@"letter-spacing"] defaultValue:0.0];
        if (kern != 0.0) {
            [attributed addAttribute:NSKernAttributeName value:@(kern) range:NSMakeRange(0, attributed.length)];
        }
    }
    element.label.attributedText = attributed;
}

- (void)applyAppearanceFromProperties:(NSDictionary<NSString *, NSString *> *)properties toLabel:(UILabel *)label {
    CGFloat fontSize = [self cssNumber:properties[@"font-size"] defaultValue:16.0];
    NSString *fontName = properties[@"font-family"];
    UIFont *font = [fontName isKindOfClass:NSString.class] ? [UIFont fontWithName:fontName size:fontSize] : nil;
    label.font = font ?: [UIFont systemFontOfSize:fontSize weight:[self fontWeight:properties[@"font-weight"]]];
    label.textColor = [self colorFromCSS:properties[@"color"] fallback:UIColor.whiteColor];
    label.backgroundColor = [self colorFromCSS:properties[@"background-color"] fallback:UIColor.clearColor];

    CGFloat cornerRadius = [self cssNumber:properties[@"border-radius"] defaultValue:0.0];
    if (cornerRadius > 0.0) {
        label.layer.cornerRadius = cornerRadius;
        label.layer.masksToBounds = YES;
    }

    NSString *border = properties[@"border"];
    if ([border isKindOfClass:NSString.class]) {
        label.layer.borderWidth = [self cssNumber:border defaultValue:0.0];
        label.layer.borderColor = [self colorEmbeddedInCSS:border fallback:UIColor.clearColor].CGColor;
    }

    NSString *shadow = properties[@"text-shadow"] ?: properties[@"box-shadow"];
    if ([shadow isKindOfClass:NSString.class]) {
        UIColor *shadowColor = [self colorEmbeddedInCSS:shadow fallback:UIColor.clearColor];
        if (shadowColor != UIColor.clearColor) {
            label.layer.shadowColor = shadowColor.CGColor;
            label.layer.shadowOpacity = 1.0;
            label.layer.shadowRadius = MAX(2.0, [self cssNumber:shadow defaultValue:5.0]);
            label.layer.shadowOffset = CGSizeMake(0.0, 1.0);
            label.layer.masksToBounds = NO;
        }
    }
    label.layer.zPosition = [self cssNumber:properties[@"z-index"] defaultValue:0.0];
}

- (void)applyVisualAnimationFromProperties:(NSDictionary<NSString *, NSString *> *)properties toView:(UIView *)view {
    NSString *animation = [properties[@"animation"] isKindOfClass:NSString.class] ? properties[@"animation"] : nil;
    if (UIAccessibilityIsReduceMotionEnabled() || animation.length == 0) {
        return;
    }
    CGFloat duration = [self cssNumber:properties[@"animation-duration"] defaultValue:3.2];
    duration = MIN(MAX(duration, 1.2), 12.0);
    CABasicAnimation *effect = nil;
    if ([animation isEqualToString:@"pulse"] || [animation isEqualToString:@"breathe"]) {
        effect = [CABasicAnimation animationWithKeyPath:@"opacity"];
        effect.fromValue = @1.0;
        effect.toValue = @0.58;
    } else if ([animation isEqualToString:@"float"]) {
        effect = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
        effect.fromValue = @(-4.0);
        effect.toValue = @(4.0);
    } else if ([animation isEqualToString:@"glow"]) {
        effect = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        effect.fromValue = @(view.layer.shadowOpacity > 0.0 ? view.layer.shadowOpacity : 0.35);
        effect.toValue = @1.0;
    }
    if (effect == nil) {
        return;
    }
    effect.duration = duration;
    effect.autoreverses = YES;
    effect.repeatCount = HUGE_VALF;
    effect.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:effect forKey:[@"lockplus." stringByAppendingString:animation]];
}

- (CGFloat)cssNormalizedPosition:(id)value defaultValue:(CGFloat)defaultValue {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) {
        return defaultValue;
    }
    if ([value isKindOfClass:NSString.class] && [(NSString *)value hasSuffix:@"%"]) {
        return MIN(MAX([(NSString *)value doubleValue] / 100.0, 0.0), 1.0);
    }
    CGFloat parsed = [value doubleValue];
    return MIN(MAX(parsed, 0.0), 1.0);
}

- (CGFloat)cssNumber:(id)value defaultValue:(CGFloat)defaultValue {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) {
        return defaultValue;
    }
    CGFloat parsed = [value doubleValue];
    return isfinite(parsed) ? parsed : defaultValue;
}

- (UIFontWeight)fontWeight:(id)value {
    CGFloat numeric = [self cssNumber:value defaultValue:400.0];
    if (numeric >= 700.0) return UIFontWeightBold;
    if (numeric >= 600.0) return UIFontWeightSemibold;
    if (numeric <= 250.0) return UIFontWeightUltraLight;
    if (numeric <= 350.0) return UIFontWeightLight;
    return UIFontWeightRegular;
}

- (UIColor *)colorEmbeddedInCSS:(NSString *)css fallback:(UIColor *)fallback {
    if (![css isKindOfClass:NSString.class]) {
        return fallback;
    }
    NSRange rgbaStart = [css rangeOfString:@"rgba("];
    if (rgbaStart.location != NSNotFound) {
        NSRange close = [css rangeOfString:@")" options:0 range:NSMakeRange(rgbaStart.location, css.length - rgbaStart.location)];
        if (close.location != NSNotFound) {
            return [self colorFromCSS:[css substringWithRange:NSMakeRange(rgbaStart.location, NSMaxRange(close) - rgbaStart.location)] fallback:fallback];
        }
    }
    NSRange hexStart = [css rangeOfString:@"#"];
    if (hexStart.location != NSNotFound && css.length >= hexStart.location + 7) {
        return [self colorFromCSS:[css substringWithRange:NSMakeRange(hexStart.location, 7)] fallback:fallback];
    }
    return fallback;
}

- (UIColor *)colorFromCSS:(id)value fallback:(UIColor *)fallback {
    if (![value isKindOfClass:NSString.class]) {
        return fallback;
    }
    NSString *css = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([css hasPrefix:@"#"] && css.length == 7) {
        unsigned int rgb = 0;
        [[NSScanner scannerWithString:[css substringFromIndex:1]] scanHexInt:&rgb];
        return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1.0];
    }
    if ([css hasPrefix:@"rgba("] && [css hasSuffix:@")"]) {
        NSString *body = [css substringWithRange:NSMakeRange(5, css.length - 6)];
        NSArray<NSString *> *parts = [body componentsSeparatedByString:@","];
        if (parts.count == 4) {
            return [UIColor colorWithRed:MAX(0.0, MIN(255.0, parts[0].doubleValue)) / 255.0
                                   green:MAX(0.0, MIN(255.0, parts[1].doubleValue)) / 255.0
                                    blue:MAX(0.0, MIN(255.0, parts[2].doubleValue)) / 255.0
                                   alpha:MAX(0.0, MIN(1.0, parts[3].doubleValue))];
        }
    }
    return fallback;
}

@end
