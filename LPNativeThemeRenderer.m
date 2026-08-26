#import "LPNativeThemeRenderer.h"

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
        CGFloat defaultHeight = [type isEqualToString:@"clock"] ? 76.0 : ([type isEqualToString:@"panel"] ? 72.0 : 34.0);
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
        if ([type isEqualToString:@"text"] || [type isEqualToString:@"panel"]) {
            [self applyText:[properties[@"innerHTML"] isKindOfClass:NSString.class] ? properties[@"innerHTML"] : @"" toElement:element];
        }
    }

    [self updateDynamicLabels];
    __weak typeof(self) weakSelf = self;
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf updateDynamicLabels];
    }];
}

- (void)updateDynamicLabels {
    NSDate *now = [NSDate date];
    for (LPNativeThemeElement *element in self.elements) {
        if ([element.type isEqualToString:@"clock"]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = NSLocale.currentLocale;
            formatter.dateFormat = @"HH:mm";
            [self applyText:[formatter stringFromDate:now] toElement:element];
        } else if ([element.type isEqualToString:@"date"]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = NSLocale.currentLocale;
            formatter.dateFormat = @"EEEE, MMMM d";
            [self applyText:[formatter stringFromDate:now] toElement:element];
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
