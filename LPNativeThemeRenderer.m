#import "LPNativeThemeRenderer.h"
#import <rootless.h>
#import <ImageIO/ImageIO.h>
#import <WebKit/WebKit.h>

static NSString * const kLPThemePreferencesDomain = @"com.example.speciallock";

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

@interface LPBrushstrokeTimeView : UIView
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *strokeLayers;
@property (nonatomic, strong) NSMutableArray<CALayer *> *brushLayers;
@property (nonatomic, strong) UIColor *paintColor;
@property (nonatomic, strong) UIImage *brushImage;
@property (nonatomic, strong) NSArray<UIImage *> *paintingImages;
@property (nonatomic, strong) CALayer *paintingLayer;
@property (nonatomic, strong) CAShapeLayer *paintingMaskLayer;
@property (nonatomic, strong) CALayer *paintingBrushLayer;
@property (nonatomic, strong) NSTimer *paintingCycleTimer;
@property (nonatomic, assign) NSInteger paintingIndex;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat animationDuration;
@property (nonatomic, copy) NSString *lastTimeKey;
- (instancetype)initWithPaintColor:(UIColor *)paintColor
                        brushImage:(UIImage *)brushImage
                    paintingImages:(NSArray<UIImage *> *)paintingImages
                       strokeWidth:(CGFloat)strokeWidth
                 animationDuration:(CGFloat)animationDuration;
- (void)updateForDate:(NSDate *)date;
@end

@implementation LPBrushstrokeTimeView

- (instancetype)initWithPaintColor:(UIColor *)paintColor
                        brushImage:(UIImage *)brushImage
                    paintingImages:(NSArray<UIImage *> *)paintingImages
                       strokeWidth:(CGFloat)strokeWidth
                 animationDuration:(CGFloat)animationDuration {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _paintColor = paintColor ?: [UIColor colorWithRed:0.06 green:0.20 blue:0.69 alpha:1.0];
        _brushImage = brushImage;
        _paintingImages = [paintingImages copy] ?: @[];
        _paintingIndex = -1;
        _strokeWidth = MIN(MAX(strokeWidth, 5.0), 22.0);
        _animationDuration = MIN(MAX(animationDuration, 12.0), 22.0);
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;

        _strokeLayers = [NSMutableArray array];
        _brushLayers = [NSMutableArray array];
        if (_paintingImages.count > 0) {
            _paintingLayer = [CALayer layer];
            _paintingLayer.backgroundColor = [UIColor colorWithRed:0.965 green:0.945 blue:0.900 alpha:1.0].CGColor;
            _paintingLayer.borderColor = [UIColor colorWithRed:0.49 green:0.42 blue:0.30 alpha:0.55].CGColor;
            _paintingLayer.borderWidth = 1.0;
            _paintingLayer.cornerRadius = 3.0;
            _paintingLayer.masksToBounds = YES;
            _paintingLayer.contentsGravity = kCAGravityResizeAspect;
            _paintingMaskLayer = [CAShapeLayer layer];
            _paintingMaskLayer.fillColor = UIColor.clearColor.CGColor;
            _paintingMaskLayer.strokeColor = UIColor.blackColor.CGColor;
            _paintingMaskLayer.lineCap = kCALineCapRound;
            _paintingMaskLayer.lineJoin = kCALineJoinRound;
            _paintingLayer.mask = _paintingMaskLayer;
            [self.layer addSublayer:_paintingLayer];
            if (_brushImage != nil) {
                _paintingBrushLayer = [self newBrushLayer];
            }
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.lastTimeKey = nil;
    if (self.paintingLayer != nil) {
        self.paintingLayer.bounds = CGRectMake(0.0, 0.0, MIN(self.bounds.size.width - 28.0, 260.0), 150.0);
        self.paintingLayer.position = CGPointMake(CGRectGetMidX(self.bounds), self.bounds.size.height * 0.77);
        self.paintingMaskLayer.frame = self.paintingLayer.bounds;
        UIBezierPath *maskPath = [UIBezierPath bezierPath];
        CGFloat rows = 7.0;
        CGFloat inset = 10.0;
        CGFloat usableWidth = MAX(1.0, self.paintingLayer.bounds.size.width - (inset * 2.0));
        CGFloat usableHeight = MAX(1.0, self.paintingLayer.bounds.size.height - (inset * 2.0));
        for (NSUInteger row = 0; row < (NSUInteger)rows; row++) {
            CGFloat y = inset + ((usableHeight / (rows - 1.0)) * row);
            [maskPath moveToPoint:CGPointMake(inset, y)];
            [maskPath addCurveToPoint:CGPointMake(inset + usableWidth, y + ((row % 2 == 0) ? 4.0 : -4.0)) controlPoint1:CGPointMake(inset + (usableWidth * 0.33), y - 3.0) controlPoint2:CGPointMake(inset + (usableWidth * 0.68), y + 3.0)];
        }
        self.paintingMaskLayer.path = maskPath.CGPath;
        self.paintingMaskLayer.lineWidth = MAX(14.0, usableHeight / rows + 8.0);
    }
    [self updateForDate:[NSDate date]];
}

- (void)appendDigit:(unichar)digit x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width height:(CGFloat)height toPath:(UIBezierPath *)path {
    CGFloat left = x;
    CGFloat right = x + width;
    CGFloat middle = y + (height * 0.50);
    CGFloat bottom = y + height;
    switch (digit) {
        case '0':
            [path moveToPoint:CGPointMake(left + (width * 0.53), y + 2.0)];
            [path addCurveToPoint:CGPointMake(right - 2.0, middle) controlPoint1:CGPointMake(right, y + (height * 0.04)) controlPoint2:CGPointMake(right + 2.0, y + (height * 0.31))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.47), bottom - 2.0) controlPoint1:CGPointMake(right - (width * 0.02), bottom - (height * 0.10)) controlPoint2:CGPointMake(right - (width * 0.08), bottom)];
            [path addCurveToPoint:CGPointMake(left + 2.0, middle) controlPoint1:CGPointMake(left + (width * 0.15), bottom + 2.0) controlPoint2:CGPointMake(left - 2.0, bottom - (height * 0.28))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.53), y + 2.0) controlPoint1:CGPointMake(left + (width * 0.02), y + (height * 0.22)) controlPoint2:CGPointMake(left + (width * 0.18), y + (height * 0.03))];
            break;
        case '1':
            [path moveToPoint:CGPointMake(left + (width * 0.18), y + (height * 0.20))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.50), y + (height * 0.06)) controlPoint1:CGPointMake(left + (width * 0.32), y + (height * 0.16)) controlPoint2:CGPointMake(left + (width * 0.43), y + (height * 0.07))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.50), bottom - 2.0) controlPoint1:CGPointMake(left + (width * 0.50), middle) controlPoint2:CGPointMake(left + (width * 0.50), bottom - (height * 0.22))];
            break;
        case '2':
            [path moveToPoint:CGPointMake(left + 1.0, y + (height * 0.25))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.06), y + (height * 0.20)) controlPoint1:CGPointMake(left + (width * 0.22), y - 1.0) controlPoint2:CGPointMake(right - (width * 0.10), y + (height * 0.03))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.12), bottom - (height * 0.12)) controlPoint1:CGPointMake(right + 2.0, middle) controlPoint2:CGPointMake(left + (width * 0.37), middle + (height * 0.18))];
            [path addCurveToPoint:CGPointMake(right, bottom - 1.0) controlPoint1:CGPointMake(left + (width * 0.36), bottom) controlPoint2:CGPointMake(left + (width * 0.72), bottom)];
            break;
        case '3':
            [path moveToPoint:CGPointMake(left + (width * 0.10), y + (height * 0.13))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.10), y + (height * 0.13)) controlPoint1:CGPointMake(left + (width * 0.38), y - 1.0) controlPoint2:CGPointMake(right - (width * 0.12), y + (height * 0.02))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.48), middle - (height * 0.04)) controlPoint1:CGPointMake(right + 2.0, y + (height * 0.30)) controlPoint2:CGPointMake(right - (width * 0.05), middle - (height * 0.08))];
            [path moveToPoint:CGPointMake(left + (width * 0.48), middle + (height * 0.05))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.06), middle + (height * 0.04)) controlPoint1:CGPointMake(left + (width * 0.68), middle + (height * 0.10)) controlPoint2:CGPointMake(right - (width * 0.13), middle - (height * 0.02))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.12), bottom - (height * 0.11)) controlPoint1:CGPointMake(right + 2.0, middle + (height * 0.23)) controlPoint2:CGPointMake(right, bottom - (height * 0.22))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.10), bottom - (height * 0.09)) controlPoint1:CGPointMake(right - (width * 0.36), bottom + 1.0) controlPoint2:CGPointMake(left + (width * 0.30), bottom)];
            break;
        case '4':
            [path moveToPoint:CGPointMake(right - (width * 0.16), y + 1.0)];
            [path addCurveToPoint:CGPointMake(left + (width * 0.12), middle + (height * 0.05)) controlPoint1:CGPointMake(left + (width * 0.58), y + (height * 0.30)) controlPoint2:CGPointMake(left + (width * 0.34), middle)];
            [path addCurveToPoint:CGPointMake(right, middle + (height * 0.05)) controlPoint1:CGPointMake(left + (width * 0.40), middle + (height * 0.07)) controlPoint2:CGPointMake(left + (width * 0.72), middle + (height * 0.05))];
            [path moveToPoint:CGPointMake(right - (width * 0.16), y + 1.0)];
            [path addCurveToPoint:CGPointMake(right - (width * 0.12), bottom - 1.0) controlPoint1:CGPointMake(right - (width * 0.08), middle) controlPoint2:CGPointMake(right - (width * 0.15), bottom - (height * 0.20))];
            break;
        case '5':
            [path moveToPoint:CGPointMake(right - (width * 0.03), y + (height * 0.06))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.15), y + (height * 0.05)) controlPoint1:CGPointMake(left + (width * 0.60), y) controlPoint2:CGPointMake(left + (width * 0.30), y + (height * 0.04))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.14), middle) controlPoint1:CGPointMake(left + (width * 0.11), y + (height * 0.23)) controlPoint2:CGPointMake(left + (width * 0.14), middle - (height * 0.08))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.04), bottom - (height * 0.11)) controlPoint1:CGPointMake(right - (width * 0.02), middle - (height * 0.13)) controlPoint2:CGPointMake(right, bottom - (height * 0.22))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.10), bottom - (height * 0.08)) controlPoint1:CGPointMake(right - (width * 0.25), bottom + 1.0) controlPoint2:CGPointMake(left + (width * 0.40), bottom)];
            break;
        case '6':
            [path moveToPoint:CGPointMake(right - (width * 0.04), y + (height * 0.10))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.15), middle) controlPoint1:CGPointMake(left + (width * 0.52), y + (height * 0.24)) controlPoint2:CGPointMake(left + (width * 0.08), middle - (height * 0.12))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.08), bottom - (height * 0.13)) controlPoint1:CGPointMake(left + (width * 0.15), bottom - (height * 0.10)) controlPoint2:CGPointMake(right - (width * 0.12), bottom)];
            [path addCurveToPoint:CGPointMake(left + (width * 0.18), middle + (height * 0.02)) controlPoint1:CGPointMake(right + 1.0, middle + (height * 0.12)) controlPoint2:CGPointMake(left + (width * 0.53), middle - (height * 0.06))];
            break;
        case '7':
            [path moveToPoint:CGPointMake(left + (width * 0.04), y + (height * 0.06))];
            [path addCurveToPoint:CGPointMake(right - (width * 0.04), y + (height * 0.05)) controlPoint1:CGPointMake(left + (width * 0.38), y) controlPoint2:CGPointMake(right - (width * 0.26), y + (height * 0.04))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.34), bottom - 1.0) controlPoint1:CGPointMake(right - (width * 0.38), middle) controlPoint2:CGPointMake(left + (width * 0.51), bottom - (height * 0.20))];
            break;
        case '8':
            [path moveToPoint:CGPointMake(left + (width * 0.52), y + 1.0)];
            [path addCurveToPoint:CGPointMake(left + (width * 0.18), middle) controlPoint1:CGPointMake(right, y + (height * 0.08)) controlPoint2:CGPointMake(left + (width * 0.02), y + (height * 0.28))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.52), bottom - 1.0) controlPoint1:CGPointMake(right - (width * 0.02), middle + (height * 0.15)) controlPoint2:CGPointMake(right - (width * 0.08), bottom)];
            [path addCurveToPoint:CGPointMake(right - (width * 0.12), middle) controlPoint1:CGPointMake(left + (width * 0.12), bottom) controlPoint2:CGPointMake(right + 1.0, bottom - (height * 0.20))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.52), y + 1.0) controlPoint1:CGPointMake(left + (width * 0.05), y + (height * 0.30)) controlPoint2:CGPointMake(left + (width * 0.15), y + (height * 0.02))];
            break;
        case '9':
            [path moveToPoint:CGPointMake(left + (width * 0.16), middle)];
            [path addCurveToPoint:CGPointMake(right - (width * 0.16), y + (height * 0.08)) controlPoint1:CGPointMake(left + (width * 0.06), y + (height * 0.07)) controlPoint2:CGPointMake(right - (width * 0.08), y)];
            [path addCurveToPoint:CGPointMake(left + (width * 0.26), middle) controlPoint1:CGPointMake(right, middle - (height * 0.02)) controlPoint2:CGPointMake(left + (width * 0.65), middle + (height * 0.14))];
            [path addCurveToPoint:CGPointMake(left + (width * 0.08), bottom - 1.0) controlPoint1:CGPointMake(left + (width * 0.40), middle + (height * 0.24)) controlPoint2:CGPointMake(left + (width * 0.19), bottom - (height * 0.14))];
            break;
        default:
            break;
    }
}

- (NSArray<UIBezierPath *> *)paintPathsForDate:(NSDate *)date width:(CGFloat)width height:(CGFloat)height {
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSString *digits = [NSString stringWithFormat:@"%02ld%02ld", (long)components.hour, (long)components.minute];
    CGFloat digitHeight = MIN(MAX(height * 0.53, 72.0), 124.0);
    CGFloat digitWidth = digitHeight * 0.43;
    CGFloat gap = digitWidth * 0.16;
    CGFloat colonWidth = digitWidth * 0.38;
    CGFloat totalWidth = (digitWidth * 4.0) + (gap * 3.0) + colonWidth;
    CGFloat x = MAX(10.0, (width - totalWidth) * 0.5);
    CGFloat y = MAX(10.0, (height - digitHeight) * 0.42);
    NSMutableArray<UIBezierPath *> *paths = [NSMutableArray array];
    for (NSUInteger index = 0; index < digits.length; index++) {
        UIBezierPath *digitPath = [UIBezierPath bezierPath];
        [self appendDigit:[digits characterAtIndex:index] x:x y:y width:digitWidth height:digitHeight toPath:digitPath];
        [paths addObject:digitPath];
        x += digitWidth;
        if (index == 1) {
            CGFloat colonX = x + (colonWidth * 0.52);
            CGFloat dotSize = MAX(2.8, self.strokeWidth * 0.48);
            UIBezierPath *topDot = [UIBezierPath bezierPath];
            [topDot moveToPoint:CGPointMake(colonX - dotSize, y + (digitHeight * 0.34))];
            [topDot addLineToPoint:CGPointMake(colonX + dotSize, y + (digitHeight * 0.34))];
            [paths addObject:topDot];
            UIBezierPath *bottomDot = [UIBezierPath bezierPath];
            [bottomDot moveToPoint:CGPointMake(colonX - dotSize, y + (digitHeight * 0.69))];
            [bottomDot addLineToPoint:CGPointMake(colonX + dotSize, y + (digitHeight * 0.69))];
            [paths addObject:bottomDot];
            x += colonWidth;
        } else if (index < digits.length - 1) {
            x += gap;
        }
    }
    return paths;
}

- (CAShapeLayer *)newStrokeLayerForPath:(UIBezierPath *)path {
    CAShapeLayer *stroke = [CAShapeLayer layer];
    stroke.fillColor = UIColor.clearColor.CGColor;
    stroke.strokeColor = self.paintColor.CGColor;
    stroke.lineWidth = self.strokeWidth;
    stroke.lineCap = kCALineCapRound;
    stroke.lineJoin = kCALineJoinRound;
    stroke.shadowColor = self.paintColor.CGColor;
    stroke.shadowOpacity = 0.22;
    stroke.shadowRadius = MIN(MAX(self.strokeWidth * 0.72, 3.0), 14.0);
    stroke.shadowOffset = CGSizeMake(0.0, 1.0);
    stroke.path = path.CGPath;
    stroke.strokeStart = 0.0;
    stroke.strokeEnd = 1.0;
    [self.layer addSublayer:stroke];
    return stroke;
}

- (CALayer *)newBrushLayer {
    CALayer *brush = [CALayer layer];
    brush.contents = (__bridge id)self.brushImage.CGImage;
    brush.contentsGravity = kCAGravityResizeAspect;
    brush.contentsScale = UIScreen.mainScreen.scale;
    brush.bounds = CGRectMake(0.0, 0.0, 200.0, 100.0);
    brush.anchorPoint = CGPointMake(0.03, 0.50);
    brush.opacity = 0.0;
    brush.shadowColor = UIColor.blackColor.CGColor;
    brush.shadowOpacity = 0.18;
    brush.shadowRadius = 3.0;
    brush.shadowOffset = CGSizeMake(1.0, 2.0);
    [self.layer addSublayer:brush];
    return brush;
}

- (void)startLoop {
    [self.paintingCycleTimer invalidate];
    self.paintingCycleTimer = nil;
    CFTimeInterval duration = MIN(MAX(self.animationDuration, 12.0), 22.0);
    NSUInteger count = self.strokeLayers.count;
    if (self.paintingImages.count > 0) {
        if (self.paintingIndex < 0) {
            self.paintingIndex = 0;
        }
        self.paintingLayer.contents = (__bridge id)self.paintingImages[(NSUInteger)self.paintingIndex % self.paintingImages.count].CGImage;
    }
    if (UIAccessibilityIsReduceMotionEnabled()) {
        for (CALayer *brush in self.brushLayers) {
            brush.hidden = YES;
        }
        self.paintingBrushLayer.hidden = YES;
        self.paintingMaskLayer.strokeStart = 0.0;
        self.paintingMaskLayer.strokeEnd = 1.0;
        return;
    }
    CFTimeInterval startOffset = duration * 0.07;
    CFTimeInterval paintingSpan = duration * 0.45;
    CFTimeInterval slot = paintingSpan / MAX((NSUInteger)1, count);
    CFTimeInterval holdEnd = duration * 0.90;
    for (NSUInteger index = 0; index < count; index++) {
        CAShapeLayer *stroke = self.strokeLayers[index];
        CALayer *brush = index < self.brushLayers.count ? self.brushLayers[index] : nil;
        [stroke removeAllAnimations];
        [brush removeAllAnimations];
        CFTimeInterval strokeStart = startOffset + (slot * index);
        CFTimeInterval strokeEnd = strokeStart + (slot * 0.76);

        CAKeyframeAnimation *drawEnd = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
        drawEnd.values = @[ @0.0, @0.0, @1.0, @1.0, @1.0 ];
        drawEnd.keyTimes = @[ @0.0, @(strokeStart / duration), @(strokeEnd / duration), @(holdEnd / duration), @1.0 ];
        CAKeyframeAnimation *clearStart = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
        clearStart.values = @[ @0.0, @0.0, @0.0, @0.0, @1.0 ];
        clearStart.keyTimes = @[ @0.0, @(strokeStart / duration), @(strokeEnd / duration), @(duration * 0.93 / duration), @1.0 ];
        CAAnimationGroup *paintCycle = [CAAnimationGroup animation];
        paintCycle.animations = @[ drawEnd, clearStart ];
        paintCycle.duration = duration;
        paintCycle.repeatCount = 0.0;
        paintCycle.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [stroke addAnimation:paintCycle forKey:@"speciallock.brushstroke.paint.mark"];

        if (brush != nil) {
            brush.hidden = NO;
            CAKeyframeAnimation *travel = [CAKeyframeAnimation animationWithKeyPath:@"position"];
            travel.path = stroke.path;
            travel.calculationMode = kCAAnimationPaced;
            travel.rotationMode = kCAAnimationRotateAutoReverse;
            travel.beginTime = strokeStart;
            travel.duration = strokeEnd - strokeStart;
            CAKeyframeAnimation *opacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            opacity.values = @[ @0.0, @0.0, @1.0, @1.0, @0.0, @0.0 ];
            opacity.keyTimes = @[ @0.0, @(MAX(0.0, (strokeStart - (duration * 0.02)) / duration)), @(strokeStart / duration), @(strokeEnd / duration), @(MIN(1.0, (strokeEnd + (duration * 0.02)) / duration)), @1.0 ];
            CAAnimationGroup *brushCycle = [CAAnimationGroup animation];
            brushCycle.animations = @[ travel, opacity ];
            brushCycle.duration = duration;
            brushCycle.repeatCount = 0.0;
            [brush addAnimation:brushCycle forKey:@"speciallock.brushstroke.brush.mark"];
        }
    }

    if (self.paintingLayer != nil && self.paintingMaskLayer.path != nil) {
        [self.paintingMaskLayer removeAllAnimations];
        [self.paintingBrushLayer removeAllAnimations];
        self.paintingBrushLayer.hidden = (self.brushImage == nil);
        CFTimeInterval artStart = duration * 0.55;
        CFTimeInterval artEnd = duration * 0.82;
        CAKeyframeAnimation *artReveal = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
        artReveal.values = @[ @0.0, @0.0, @1.0, @1.0, @1.0 ];
        artReveal.keyTimes = @[ @0.0, @(artStart / duration), @(artEnd / duration), @(holdEnd / duration), @1.0 ];
        CAKeyframeAnimation *artClear = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
        artClear.values = @[ @0.0, @0.0, @0.0, @0.0, @1.0 ];
        artClear.keyTimes = @[ @0.0, @(artStart / duration), @(artEnd / duration), @(duration * 0.95 / duration), @1.0 ];
        CAAnimationGroup *artCycle = [CAAnimationGroup animation];
        artCycle.animations = @[ artReveal, artClear ];
        artCycle.duration = duration;
        [self.paintingMaskLayer addAnimation:artCycle forKey:@"speciallock.brushstroke.paint.study"];

        if (self.paintingBrushLayer != nil) {
            UIBezierPath *studyPath = [UIBezierPath bezierPathWithCGPath:self.paintingMaskLayer.path];
            [studyPath applyTransform:CGAffineTransformMakeTranslation(CGRectGetMinX(self.paintingLayer.frame), CGRectGetMinY(self.paintingLayer.frame))];
            CAKeyframeAnimation *travel = [CAKeyframeAnimation animationWithKeyPath:@"position"];
            travel.path = studyPath.CGPath;
            travel.calculationMode = kCAAnimationPaced;
            travel.rotationMode = kCAAnimationRotateAutoReverse;
            travel.beginTime = artStart;
            travel.duration = artEnd - artStart;
            CAKeyframeAnimation *opacity = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
            opacity.values = @[ @0.0, @0.0, @1.0, @1.0, @0.0, @0.0 ];
            opacity.keyTimes = @[ @0.0, @(MAX(0.0, (artStart - (duration * 0.02)) / duration)), @(artStart / duration), @(artEnd / duration), @(MIN(1.0, (artEnd + (duration * 0.02)) / duration)), @1.0 ];
            CAAnimationGroup *brushCycle = [CAAnimationGroup animation];
            brushCycle.animations = @[ travel, opacity ];
            brushCycle.duration = duration;
            [self.paintingBrushLayer addAnimation:brushCycle forKey:@"speciallock.brushstroke.brush.study"];
        }
    }
    if (self.paintingImages.count > 1) {
        self.paintingCycleTimer = [NSTimer scheduledTimerWithTimeInterval:duration target:self selector:@selector(advancePaintingStudy) userInfo:nil repeats:NO];
    }
}

- (void)advancePaintingStudy {
    if (self.paintingImages.count > 1) {
        self.paintingIndex = (self.paintingIndex + 1) % self.paintingImages.count;
    }
    [self startLoop];
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    if (newSuperview == nil) {
        [self.paintingCycleTimer invalidate];
        self.paintingCycleTimer = nil;
    }
    [super willMoveToSuperview:newSuperview];
}

- (void)dealloc {
    [self.paintingCycleTimer invalidate];
}

- (void)updateForDate:(NSDate *)date {
    if (self.bounds.size.width < 120.0 || self.bounds.size.height < 100.0) {
        return;
    }
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSString *timeKey = [NSString stringWithFormat:@"%02ld%02ld", (long)components.hour, (long)components.minute];
    if ([timeKey isEqualToString:self.lastTimeKey]) {
        return;
    }
    self.lastTimeKey = timeKey;
    for (CALayer *layer in self.strokeLayers) {
        [layer removeFromSuperlayer];
    }
    for (CALayer *layer in self.brushLayers) {
        [layer removeFromSuperlayer];
    }
    [self.strokeLayers removeAllObjects];
    [self.brushLayers removeAllObjects];
    for (UIBezierPath *path in [self paintPathsForDate:date width:self.bounds.size.width height:self.bounds.size.height]) {
        [self.strokeLayers addObject:[self newStrokeLayerForPath:path]];
        if (self.brushImage != nil) {
            [self.brushLayers addObject:[self newBrushLayer]];
        }
    }
    [self startLoop];
}

@end

@interface LPECGTimeView : UIView
@property (nonatomic, strong) CAShapeLayer *gridLayer;
@property (nonatomic, strong) CAShapeLayer *leadLayer;
@property (nonatomic, strong) CAShapeLayer *heartbeatLayer;
@property (nonatomic, strong) CAShapeLayer *timeLayer;
@property (nonatomic, strong) UIColor *traceColor;
@property (nonatomic, strong) UIColor *gridColor;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat animationDuration;
@property (nonatomic, copy) NSString *lastTimeKey;
@property (nonatomic, assign) BOOL hasRendered;
- (instancetype)initWithTraceColor:(UIColor *)traceColor
                         gridColor:(UIColor *)gridColor
                       strokeWidth:(CGFloat)strokeWidth
                 animationDuration:(CGFloat)animationDuration;
- (void)updateForDate:(NSDate *)date;
@end

@implementation LPECGTimeView

- (instancetype)initWithTraceColor:(UIColor *)traceColor
                         gridColor:(UIColor *)gridColor
                       strokeWidth:(CGFloat)strokeWidth
                 animationDuration:(CGFloat)animationDuration {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _traceColor = traceColor ?: UIColor.systemGreenColor;
        _gridColor = gridColor ?: [UIColor colorWithRed:0.04 green:0.16 blue:0.17 alpha:1.0];
        _strokeWidth = MIN(MAX(strokeWidth, 1.0), 8.0);
        _animationDuration = MIN(MAX(animationDuration, 1.2), 5.0);
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;

        _gridLayer = [CAShapeLayer layer];
        _gridLayer.fillColor = UIColor.clearColor.CGColor;
        _gridLayer.strokeColor = _gridColor.CGColor;
        _gridLayer.lineWidth = 0.65;
        [self.layer addSublayer:_gridLayer];

        _leadLayer = [self newTraceLayer];
        _leadLayer.opacity = 0.42;
        _heartbeatLayer = [self newTraceLayer];
        _timeLayer = [self newTraceLayer];
        [self.layer addSublayer:_leadLayer];
        [self.layer addSublayer:_heartbeatLayer];
        [self.layer addSublayer:_timeLayer];
    }
    return self;
}

- (CAShapeLayer *)newTraceLayer {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.fillColor = UIColor.clearColor.CGColor;
    layer.strokeColor = self.traceColor.CGColor;
    layer.lineWidth = self.strokeWidth;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;
    layer.shadowColor = self.traceColor.CGColor;
    layer.shadowOpacity = 0.82;
    layer.shadowRadius = MIN(MAX(self.strokeWidth * 2.6, 3.0), 16.0);
    layer.shadowOffset = CGSizeZero;
    return layer;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.gridLayer.frame = self.bounds;
    self.leadLayer.frame = self.bounds;
    self.heartbeatLayer.frame = self.bounds;
    self.timeLayer.frame = self.bounds;
    self.lastTimeKey = nil;
    [self updateForDate:[NSDate date]];
}

- (NSArray<NSString *> *)segmentsForDigit:(unichar)digit {
    switch (digit) {
        case '0': return @[ @"a", @"b", @"c", @"d", @"e", @"f" ];
        case '1': return @[ @"b", @"c" ];
        case '2': return @[ @"a", @"b", @"g", @"e", @"d" ];
        case '3': return @[ @"a", @"b", @"g", @"c", @"d" ];
        case '4': return @[ @"f", @"g", @"b", @"c" ];
        case '5': return @[ @"a", @"f", @"g", @"c", @"d" ];
        case '6': return @[ @"a", @"f", @"g", @"e", @"c", @"d" ];
        case '7': return @[ @"a", @"b", @"c" ];
        case '8': return @[ @"a", @"b", @"c", @"d", @"e", @"f", @"g" ];
        case '9': return @[ @"a", @"b", @"c", @"d", @"f", @"g" ];
        default: return @[];
    }
}

- (void)appendSegment:(NSString *)segment x:(CGFloat)x top:(CGFloat)top width:(CGFloat)width height:(CGFloat)height toPath:(UIBezierPath *)path {
    CGFloat midY = top + (height * 0.5);
    CGPoint start = CGPointZero;
    CGPoint end = CGPointZero;
    if ([segment isEqualToString:@"a"]) { start = CGPointMake(x, top); end = CGPointMake(x + width, top); }
    else if ([segment isEqualToString:@"b"]) { start = CGPointMake(x + width, top); end = CGPointMake(x + width, midY); }
    else if ([segment isEqualToString:@"c"]) { start = CGPointMake(x + width, midY); end = CGPointMake(x + width, top + height); }
    else if ([segment isEqualToString:@"d"]) { start = CGPointMake(x, top + height); end = CGPointMake(x + width, top + height); }
    else if ([segment isEqualToString:@"e"]) { start = CGPointMake(x, midY); end = CGPointMake(x, top + height); }
    else if ([segment isEqualToString:@"f"]) { start = CGPointMake(x, top); end = CGPointMake(x, midY); }
    else { start = CGPointMake(x, midY); end = CGPointMake(x + width, midY); }
    [path moveToPoint:start];
    [path addLineToPoint:end];
}

- (UIBezierPath *)gridPathForWidth:(CGFloat)width height:(CGFloat)height {
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (CGFloat x = 0.0; x <= width; x += 17.0) {
        [path moveToPoint:CGPointMake(x, 0.0)];
        [path addLineToPoint:CGPointMake(x, height)];
    }
    for (CGFloat y = 0.0; y <= height; y += 17.0) {
        [path moveToPoint:CGPointMake(0.0, y)];
        [path addLineToPoint:CGPointMake(width, y)];
    }
    return path;
}

- (UIBezierPath *)leadPathForWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat baseline = height * 0.72;
    CGFloat origin = 12.0;
    CGFloat pulse = MIN(MAX(width * 0.22, 60.0), 88.0);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(origin, baseline)];
    [path addLineToPoint:CGPointMake(pulse - 24.0, baseline)];
    [path addLineToPoint:CGPointMake(pulse - 16.0, baseline - 7.0)];
    [path addLineToPoint:CGPointMake(pulse - 8.0, baseline)];
    [path addLineToPoint:CGPointMake(pulse, baseline)];
    [path addLineToPoint:CGPointMake(pulse + 7.0, baseline + 16.0)];
    [path addLineToPoint:CGPointMake(pulse + 14.0, baseline - MIN(height * 0.45, 88.0))];
    [path addLineToPoint:CGPointMake(pulse + 23.0, baseline + 23.0)];
    [path addLineToPoint:CGPointMake(pulse + 34.0, baseline)];
    [path addLineToPoint:CGPointMake(pulse + 52.0, baseline - 13.0)];
    [path addLineToPoint:CGPointMake(pulse + 70.0, baseline)];
    return path;
}

- (UIBezierPath *)timePathForDate:(NSDate *)date width:(CGFloat)width height:(CGFloat)height {
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSString *digits = [NSString stringWithFormat:@"%02ld%02ld", (long)components.hour, (long)components.minute];
    CGFloat digitHeight = MIN(MAX(height * 0.42, 72.0), 118.0);
    CGFloat digitWidth = digitHeight * 0.44;
    CGFloat top = MAX(12.0, (height * 0.12));
    CGFloat colonWidth = digitWidth * 0.36;
    CGFloat gap = digitWidth * 0.22;
    CGFloat totalWidth = (digitWidth * 4.0) + (gap * 3.0) + colonWidth;
    CGFloat startX = MAX(12.0, (width - totalWidth) * 0.5);
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat x = startX;
    for (NSUInteger index = 0; index < digits.length; index++) {
        unichar digit = [digits characterAtIndex:index];
        for (NSString *segment in [self segmentsForDigit:digit]) {
            [self appendSegment:segment x:x top:top width:digitWidth height:digitHeight toPath:path];
        }
        x += digitWidth;
        if (index == 1) {
            CGFloat colonX = x + (colonWidth * 0.5);
            CGFloat dot = MAX(2.0, self.strokeWidth * 0.8);
            [path moveToPoint:CGPointMake(colonX - dot, top + (digitHeight * 0.33))];
            [path addLineToPoint:CGPointMake(colonX + dot, top + (digitHeight * 0.33))];
            [path moveToPoint:CGPointMake(colonX - dot, top + (digitHeight * 0.68))];
            [path addLineToPoint:CGPointMake(colonX + dot, top + (digitHeight * 0.68))];
            x += colonWidth;
        } else if (index < digits.length - 1) {
            x += gap;
        }
    }
    return path;
}

- (void)animateLayer:(CAShapeLayer *)layer key:(NSString *)key beginTime:(CFTimeInterval)beginTime duration:(CFTimeInterval)duration {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        return;
    }
    [layer removeAnimationForKey:key];
    CABasicAnimation *draw = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    draw.fromValue = @0.0;
    draw.toValue = @1.0;
    draw.beginTime = beginTime;
    draw.duration = duration;
    draw.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    draw.fillMode = kCAFillModeBoth;
    draw.removedOnCompletion = YES;
    [layer addAnimation:draw forKey:key];
}

- (void)startFullSequenceLoop {
    [self.heartbeatLayer removeAnimationForKey:@"speciallock.ecg.heartbeat"];
    [self.timeLayer removeAnimationForKey:@"speciallock.ecg.time-loop"];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.heartbeatLayer.hidden = YES;
        self.timeLayer.hidden = NO;
        return;
    }
    self.heartbeatLayer.hidden = NO;
    self.timeLayer.hidden = NO;
    CFTimeInterval cycleDuration = MIN(MAX(self.animationDuration, 2.4), 5.0);

    CAKeyframeAnimation *leadEnd = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
    leadEnd.values = @[ @0.0, @1.0, @1.0 ];
    leadEnd.keyTimes = @[ @0.0, @0.38, @1.0 ];
    CAKeyframeAnimation *leadStart = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
    leadStart.values = @[ @0.0, @0.0, @1.0 ];
    leadStart.keyTimes = @[ @0.0, @0.49, @1.0 ];
    CAAnimationGroup *heartbeat = [CAAnimationGroup animation];
    heartbeat.animations = @[ leadEnd, leadStart ];
    heartbeat.duration = cycleDuration;
    heartbeat.repeatCount = HUGE_VALF;
    heartbeat.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.heartbeatLayer addAnimation:heartbeat forKey:@"speciallock.ecg.heartbeat"];

    CAKeyframeAnimation *timeEnd = [CAKeyframeAnimation animationWithKeyPath:@"strokeEnd"];
    timeEnd.values = @[ @0.0, @0.0, @1.0, @1.0, @1.0 ];
    timeEnd.keyTimes = @[ @0.0, @0.36, @0.72, @0.88, @1.0 ];
    CAKeyframeAnimation *timeStart = [CAKeyframeAnimation animationWithKeyPath:@"strokeStart"];
    timeStart.values = @[ @0.0, @0.0, @0.0, @0.0, @1.0 ];
    timeStart.keyTimes = @[ @0.0, @0.36, @0.79, @0.91, @1.0 ];
    CAAnimationGroup *timeLoop = [CAAnimationGroup animation];
    timeLoop.animations = @[ timeEnd, timeStart ];
    timeLoop.duration = cycleDuration;
    timeLoop.repeatCount = HUGE_VALF;
    timeLoop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.timeLayer addAnimation:timeLoop forKey:@"speciallock.ecg.time-loop"];
}

- (void)updateForDate:(NSDate *)date {
    if (self.bounds.size.width < 120.0 || self.bounds.size.height < 100.0) {
        return;
    }
    NSDateComponents *components = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    NSString *timeKey = [NSString stringWithFormat:@"%02ld%02ld", (long)components.hour, (long)components.minute];
    if ([timeKey isEqualToString:self.lastTimeKey]) {
        return;
    }
    self.lastTimeKey = timeKey;
    self.hasRendered = YES;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gridLayer.path = [self gridPathForWidth:self.bounds.size.width height:self.bounds.size.height].CGPath;
    CGPathRef leadPath = [self leadPathForWidth:self.bounds.size.width height:self.bounds.size.height].CGPath;
    self.leadLayer.path = leadPath;
    self.heartbeatLayer.path = leadPath;
    self.timeLayer.path = [self timePathForDate:date width:self.bounds.size.width height:self.bounds.size.height].CGPath;
    self.leadLayer.strokeStart = 0.0;
    self.leadLayer.strokeEnd = 1.0;
    self.heartbeatLayer.strokeStart = 0.0;
    self.heartbeatLayer.strokeEnd = 1.0;
    self.timeLayer.strokeEnd = 1.0;
    [CATransaction commit];
    [self startFullSequenceLoop];
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

@interface LPNativeThemeRenderer () <WKNavigationDelegate>
@property (nonatomic, strong) NSMutableArray<LPNativeThemeElement *> *elements;
@property (nonatomic, strong) NSMutableArray<LPECGTimeView *> *ecgTimeViews;
@property (nonatomic, strong) NSMutableArray<LPBrushstrokeTimeView *> *brushstrokeTimeViews;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) WKWebView *folderWebView;
@property (nonatomic, copy) NSString *folderReadRoot;
@property (nonatomic, assign) NSUInteger folderLoadGeneration;
@end

@implementation LPNativeThemeRenderer

- (void)layoutSubviews {
    [super layoutSubviews];

    // Folder themes own the complete visual canvas. Reassert the WebView
    // frame on every host reparent/layout pass because SpringBoard can change
    // the date hierarchy bounds during lock/unlock without rebuilding us.
    if (self.folderWebView != nil) {
        self.folderWebView.frame = self.bounds;
        self.folderWebView.scrollView.contentInset = UIEdgeInsetsZero;
        self.folderWebView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }
}

- (instancetype)initWithThemeJSONString:(NSString *)themeJSONString {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.clipsToBounds = NO;
        self.userInteractionEnabled = NO;
        self.elements = [NSMutableArray array];
        self.ecgTimeViews = [NSMutableArray array];
        self.brushstrokeTimeViews = [NSMutableArray array];
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
    self.folderLoadGeneration += 1;
    self.folderWebView.navigationDelegate = nil;
    [self.folderWebView stopLoading];
    [self.folderWebView removeFromSuperview];
    self.folderWebView = nil;
    self.folderReadRoot = nil;
}

- (void)clearNativeRenderedContent {
    [self stopRendering];
    for (UIView *view in [self.subviews copy]) {
        [view removeFromSuperview];
    }
    [self.elements removeAllObjects];
    [self.ecgTimeViews removeAllObjects];
    [self.brushstrokeTimeViews removeAllObjects];
}

- (void)loadFolderThemeWithID:(NSString *)themeID {
    if (themeID.length == 0) return;
    NSString *relativeRoot = [@"/var/mobile/Library/SpecialLock/Themes/Assets" stringByAppendingPathComponent:themeID];
    NSString *rootPath = ROOT_PATH_NS(relativeRoot);
    NSString *entryPath = [rootPath stringByAppendingPathComponent:@"LockBackground.html"];
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:entryPath isDirectory:&isDirectory] || isDirectory) return;

    // Update the security/read boundary before starting navigation. This lets
    // one retained WebView move between complete XenHTML-style folders.
    self.folderReadRoot = rootPath;
    WKWebView *webView = self.folderWebView;
    if (webView == nil) {
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
        configuration.allowsInlineMediaPlayback = NO;
        configuration.suppressesIncrementalRendering = NO;
        configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
        webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:configuration];
        webView.navigationDelegate = self;
        webView.backgroundColor = UIColor.clearColor;
        webView.opaque = NO;
        webView.clipsToBounds = NO;
        webView.scrollView.scrollEnabled = NO;
        webView.scrollView.bounces = NO;
        webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        webView.scrollView.contentInset = UIEdgeInsetsZero;
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
        webView.userInteractionEnabled = NO;
        webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:webView];
        self.folderWebView = webView;
    } else {
        webView.navigationDelegate = self;
    }

    // A changing query is understood by WebKit as a new document URL and
    // prevents a stale LockBackground.html response from being reused. The
    // query does not alter relative CSS, JS, font, or wallpaper resolution.
    NSURLComponents *components = [NSURLComponents componentsWithURL:[NSURL fileURLWithPath:entryPath]
                                             resolvingAgainstBaseURL:NO];
    components.query = [NSString stringWithFormat:@"sl_reload=%llu", (unsigned long long)(CFAbsoluteTimeGetCurrent() * 1000.0)];
    [webView loadFileURL:components.URL allowingReadAccessToURL:[NSURL fileURLWithPath:rootPath isDirectory:YES]];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *URL = navigationAction.request.URL;
    NSString *root = self.folderReadRoot ?: @"";
    BOOL local = URL.isFileURL && root.length > 0 && [URL.path hasPrefix:[root stringByAppendingString:@"/"]];
    decisionHandler(local ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

- (void)reloadCurrentFolderDocument {
    NSString *themeID = [self selectedThemeID];
    WKWebView *webView = self.folderWebView;
    NSUInteger generation = self.folderLoadGeneration;
    if (themeID.length == 0 || webView == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // Ignore a delayed callback from a folder that has already been
        // replaced by a JSON/native theme.
        if (self.folderWebView == webView && self.folderLoadGeneration == generation) {
            [self loadFolderThemeWithID:themeID];
        }
    });
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (webView == self.folderWebView) {
        [self reloadCurrentFolderDocument];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (webView == self.folderWebView) {
        [self reloadCurrentFolderDocument];
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    if (webView == self.folderWebView) {
        [self reloadCurrentFolderDocument];
    }
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
    NSString *unrootedAssetPath = [[@"/var/mobile/Library/SpecialLock/Themes/Assets" stringByAppendingPathComponent:[self selectedThemeID]] stringByAppendingPathComponent:assetID];
    NSString *assetPath = ROOT_PATH_NS(unrootedAssetPath);
    return LPImageFromThemeAssetData([NSData dataWithContentsOfFile:assetPath]);
}

- (void)reloadWithThemeJSONString:(NSString *)themeJSONString {
    NSData *data = [themeJSONString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *theme = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([theme isKindOfClass:NSDictionary.class] && [theme[@"format"] isEqualToString:@"folder"]) {
        [self loadFolderThemeWithID:[self selectedThemeID]];
        return;
    }

    // JSON/native mode must never share the renderer’s folder WebView or any
    // elements left by the previous mode. Clear the complete content set in a
    // single main-thread transaction before adding native views.
    [self clearNativeRenderedContent];
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
        if ([type isEqualToString:@"brushstroke-time"]) {
            UIColor *paintColor = [self colorFromCSS:properties[@"color"] fallback:[UIColor colorWithRed:0.06 green:0.20 blue:0.69 alpha:1.0]];
            NSString *brushAssetID = [properties[@"brush-asset-id"] isKindOfClass:NSString.class] ? properties[@"brush-asset-id"] : nil;
            UIImage *brushImage = [self cachedImageAssetWithID:brushAssetID];
            if (brushImage == nil) {
                continue;
            }
            NSMutableArray<UIImage *> *paintingImages = [NSMutableArray array];
            NSString *paintingAssetIDs = [properties[@"painting-asset-ids"] isKindOfClass:NSString.class] ? properties[@"painting-asset-ids"] : @"";
            for (NSString *candidate in [paintingAssetIDs componentsSeparatedByString:@","]) {
                NSString *assetID = [candidate stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                UIImage *paintingImage = [self cachedImageAssetWithID:assetID];
                if (paintingImage != nil && paintingImages.count < 2) {
                    [paintingImages addObject:paintingImage];
                }
            }
            CGFloat top = [self cssNumber:properties[@"top"] defaultValue:170.0];
            CGFloat width = MIN(MAX([self cssNumber:properties[@"width"] defaultValue:340.0], 160.0), 360.0);
            CGFloat height = MIN(MAX([self cssNumber:properties[@"height"] defaultValue:400.0], 240.0), 440.0);
            CGFloat strokeWidth = [self cssNumber:properties[@"stroke-width"] defaultValue:12.0];
            CGFloat animationDuration = [self cssNumber:properties[@"animation-duration"] defaultValue:18.0];
            LPBrushstrokeTimeView *brushstrokeTime = [[LPBrushstrokeTimeView alloc] initWithPaintColor:paintColor brushImage:brushImage paintingImages:paintingImages strokeWidth:strokeWidth animationDuration:animationDuration];
            brushstrokeTime.translatesAutoresizingMaskIntoConstraints = NO;
            brushstrokeTime.layer.zPosition = [self cssNumber:properties[@"z-index"] defaultValue:0.0];
            [self addSubview:brushstrokeTime];
            [NSLayoutConstraint activateConstraints:@[
                [brushstrokeTime.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                [brushstrokeTime.topAnchor constraintEqualToAnchor:self.topAnchor constant:top],
                [brushstrokeTime.widthAnchor constraintEqualToConstant:width],
                [brushstrokeTime.heightAnchor constraintEqualToConstant:height],
            ]];
            [self.brushstrokeTimeViews addObject:brushstrokeTime];
            continue;
        }
        if ([type isEqualToString:@"ecg-time"]) {
            UIColor *traceColor = [self colorFromCSS:properties[@"color"] fallback:UIColor.systemGreenColor];
            UIColor *gridColor = [self colorFromCSS:properties[@"grid-color"] fallback:[UIColor colorWithRed:0.04 green:0.16 blue:0.17 alpha:1.0]];
            CGFloat top = [self cssNumber:properties[@"top"] defaultValue:200.0];
            CGFloat width = MIN(MAX([self cssNumber:properties[@"width"] defaultValue:340.0], 120.0), 360.0);
            CGFloat height = MIN(MAX([self cssNumber:properties[@"height"] defaultValue:260.0], 100.0), 440.0);
            CGFloat strokeWidth = [self cssNumber:properties[@"stroke-width"] defaultValue:3.0];
            CGFloat animationDuration = [self cssNumber:properties[@"animation-duration"] defaultValue:3.0];
            LPECGTimeView *ecgTime = [[LPECGTimeView alloc] initWithTraceColor:traceColor gridColor:gridColor strokeWidth:strokeWidth animationDuration:animationDuration];
            ecgTime.translatesAutoresizingMaskIntoConstraints = NO;
            ecgTime.layer.zPosition = [self cssNumber:properties[@"z-index"] defaultValue:0.0];
            [self addSubview:ecgTime];
            [NSLayoutConstraint activateConstraints:@[
                [ecgTime.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
                [ecgTime.topAnchor constraintEqualToAnchor:self.topAnchor constant:top],
                [ecgTime.widthAnchor constraintEqualToConstant:width],
                [ecgTime.heightAnchor constraintEqualToConstant:height],
            ]];
            [self.ecgTimeViews addObject:ecgTime];
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
        if ([type isEqualToString:@"text"] || [type isEqualToString:@"html"] || [type isEqualToString:@"panel"] || [type isEqualToString:@"widget"] || [type isEqualToString:@"overlay"]) {
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
    for (LPECGTimeView *ecgTimeView in self.ecgTimeViews) {
        [ecgTimeView updateForDate:now];
    }
    for (LPBrushstrokeTimeView *brushstrokeTimeView in self.brushstrokeTimeViews) {
        [brushstrokeTimeView updateForDate:now];
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
