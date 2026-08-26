#import "LPNativeThemeRenderer.h"

@interface LPNativeThemeElement : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *type;
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
    NSError *error = nil;
    NSDictionary *theme = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    NSDictionary *placedElements = [theme isKindOfClass:NSDictionary.class] ? theme[@"placedElements"] : nil;
    if (![placedElements isKindOfClass:NSDictionary.class] || placedElements.count == 0) {
        placedElements = @{
            @"clock": @{
                @"type": @"clock", @"top": @"72px", @"color": @"#FFFFFF",
                @"font-size": @"60px", @"font-weight": @"700"
            },
            @"todaystrings": @{
                @"type": @"date", @"top": @"144px", @"color": @"#FFFFFF",
                @"font-size": @"16px", @"font-weight": @"500"
            }
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

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        label.userInteractionEnabled = NO;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.6;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textColor = [self colorFromCSS:properties[@"color"] fallback:UIColor.whiteColor];
        label.backgroundColor = [self colorFromCSS:properties[@"background-color"] fallback:UIColor.clearColor];

        CGFloat size = [self cssNumber:properties[@"font-size"] defaultValue:identifier.length ? 16.0 : 16.0];
        NSString *fontName = [properties[@"font-family"] isKindOfClass:NSString.class] ? properties[@"font-family"] : nil;
        UIFontWeight weight = [self fontWeight:properties[@"font-weight"]];
        UIFont *font = fontName.length ? [UIFont fontWithName:fontName size:size] : nil;
        label.font = font ?: [UIFont systemFontOfSize:size weight:weight];

        NSString *type = [properties[@"type"] isKindOfClass:NSString.class] ? properties[@"type"] : @"text";
        if ([type isEqualToString:@"text"]) {
            label.text = [properties[@"innerHTML"] isKindOfClass:NSString.class] ? properties[@"innerHTML"] : @"";
        }

        CGFloat radius = [self cssNumber:properties[@"border-radius"] defaultValue:0.0];
        if (radius > 0.0) {
            label.layer.cornerRadius = radius;
            label.layer.masksToBounds = YES;
        }

        [self addSubview:label];
        CGFloat top = [self cssNumber:properties[@"top"] defaultValue:72.0];
        CGFloat width = [self cssNumber:properties[@"width"] defaultValue:320.0];
        CGFloat height = [self cssNumber:properties[@"height"] defaultValue:([type isEqualToString:@"clock"] ? 76.0 : 34.0)];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [label.topAnchor constraintEqualToAnchor:self.topAnchor constant:top],
            [label.widthAnchor constraintEqualToConstant:MIN(MAX(width, 40.0), 360.0)],
            [label.heightAnchor constraintEqualToConstant:MAX(height, 20.0)],
        ]];

        LPNativeThemeElement *element = [[LPNativeThemeElement alloc] init];
        element.identifier = identifier;
        element.type = type;
        element.label = label;
        [self.elements addObject:element];
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
            element.label.text = [formatter stringFromDate:now];
        } else if ([element.type isEqualToString:@"date"]) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = NSLocale.currentLocale;
            formatter.dateFormat = @"EEEE, MMMM d";
            element.label.text = [formatter stringFromDate:now];
        }
    }
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

- (UIColor *)colorFromCSS:(id)value fallback:(UIColor *)fallback {
    if (![value isKindOfClass:NSString.class]) {
        return fallback;
    }
    NSString *css = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([css hasPrefix:@"#"] && css.length == 7) {
        unsigned int rgb = 0;
        [[NSScanner scannerWithString:[css substringFromIndex:1]] scanHexInt:&rgb];
        return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:1.0];
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
