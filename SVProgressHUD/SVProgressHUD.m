//
//  SVProgressHUD.m
//
//  Copyright 2011-2014 Sam Vermette. All rights reserved.
//
//  https://github.com/samvermette/SVProgressHUD
//

#if !__has_feature(objc_arc)
#error SVProgressHUD is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

#import "SVProgressHUD.h"
#import "SVIndefiniteAnimatedView.h"
#import <QuartzCore/QuartzCore.h>

NSString * const SVProgressHUDDidReceiveTouchEventNotification = @"SVProgressHUDDidReceiveTouchEventNotification";
NSString * const SVProgressHUDDidTouchDownInsideNotification = @"SVProgressHUDDidTouchDownInsideNotification";
NSString * const SVProgressHUDWillDisappearNotification = @"SVProgressHUDWillDisappearNotification";
NSString * const SVProgressHUDDidDisappearNotification = @"SVProgressHUDDidDisappearNotification";
NSString * const SVProgressHUDWillAppearNotification = @"SVProgressHUDWillAppearNotification";
NSString * const SVProgressHUDDidAppearNotification = @"SVProgressHUDDidAppearNotification";

NSString * const SVProgressHUDStatusUserInfoKey = @"SVProgressHUDStatusUserInfoKey";

static UIColor *SVProgressHUDBackgroundColor;
static UIColor *SVProgressHUDForegroundColor;
static CGFloat SVProgressHUDRingThickness;
static UIFont *SVProgressHUDFont;
static UIImage *SVProgressHUDInfoImage;
static UIImage *SVProgressHUDSuccessImage;
static UIImage *SVProgressHUDErrorImage;
static SVProgressHUDMaskType SVProgressHUDDefaultMaskType;
static UIView *SVProgressHUDExtensionView;

static const CGFloat SVProgressHUDRingRadius = 18;
static const CGFloat SVProgressHUDRingNoTextRadius = 24;
static const CGFloat SVProgressHUDParallaxDepthPoints = 10;
static const CGFloat SVProgressHUDUndefinedProgress = -1;
static const CGFloat SVProgressHUDVerticalSpacing = 12.0f;
static const CGFloat SVProgressHUDHorizontalSpacing = 12.0f;
static const CGFloat SVProgressHUDLabelSpacing = 8.0f;

#define isIPhoneX   ([UIScreen mainScreen].bounds.size.height == 812 || [UIScreen mainScreen].bounds.size.height == 896)

#define topOffset isIPhoneX ? 88.0f : 64.0f

#define SVProgressHUDEnableNavBarFrame CGRectMake(0.0f, topOffset, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height - (topOffset))

#define SVProgressHUDNonEnableNavBarFrame  CGRectMake(0.0f, 0.0f, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)


@interface SVProgressHUD ()

@property (nonatomic, readwrite) SVProgressHUDMaskType maskType;
@property (nonatomic, strong, readonly) NSTimer *fadeOutTimer;
@property (nonatomic, readonly, getter = isClear) BOOL clear;

@property (nonatomic, strong) UIView *hudView;
@property (nonatomic, strong) UILabel *stringLabel;
@property (nonatomic, strong) SVIndefiniteAnimatedView *indefiniteAnimatedView;

@property (nonatomic, readwrite) CGFloat progress;
@property (nonatomic, readwrite) NSUInteger activityCount;
@property (nonatomic, strong) CAShapeLayer *backgroundRingLayer;
@property (nonatomic, strong) CAShapeLayer *ringLayer;

@property (nonatomic, readonly) CGFloat visibleKeyboardHeight;
@property (nonatomic, assign) UIOffset offsetFromCenter;
@property (nonatomic, assign) BOOL noTransform;

@property (assign, nonatomic) NSTimeInterval minimumDismissTimeInterval;
@property (assign, nonatomic) NSTimeInterval maximumDismissTimeInterval;

@property (assign, nonatomic) CGSize minimumSize UI_APPEARANCE_SELECTOR;

- (void)showProgress:(float)progress status:(NSString*)string maskType:(SVProgressHUDMaskType)hudMaskType;
- (void)showImage:(UIImage*)image status:(NSString*)status duration:(NSTimeInterval)duration maskType:(SVProgressHUDMaskType)hudMaskType;

- (void)dismiss;

- (void)setStatus:(NSString*)string;
- (void)registerNotifications;
- (NSDictionary *)notificationUserInfo;
- (void)moveToPoint:(CGPoint)newCenter rotateAngle:(CGFloat)angle;
- (void)positionHUD:(NSNotification*)notification;
- (NSTimeInterval)displayDurationForString:(NSString*)string;

@end


@implementation SVProgressHUD

+ (SVProgressHUD*)sharedView {
    static dispatch_once_t once;
    static SVProgressHUD *sharedView;
    dispatch_once(&once, ^ { sharedView = [[self alloc] initWithFrame:[[UIScreen mainScreen] bounds]]; });
    return sharedView;
}


#pragma mark - Setters

+ (void)noTransform:(BOOL)noTrans {
    [[self sharedView] setNoTransform:noTrans];
}

+ (void)setStatus:(NSString *)string {
    [[self sharedView] setStatus:string];
}

+ (void)setBackgroundColor:(UIColor *)color {
    [self sharedView].hudView.backgroundColor = color;
    SVProgressHUDBackgroundColor = color;
}

+ (void)setForegroundColor:(UIColor *)color {
    [self sharedView];
    SVProgressHUDForegroundColor = color;
}

+ (void)setFont:(UIFont *)font {
    [self sharedView];
    SVProgressHUDFont = font;
}

+ (void)setRingThickness:(CGFloat)width {
    [self sharedView];
    SVProgressHUDRingThickness = width;
}

+ (void)setInfoImage:(UIImage*)image{
    [self sharedView];
    SVProgressHUDInfoImage = image;
}

+ (void)setSuccessImage:(UIImage *)image {
    [self sharedView];
    SVProgressHUDSuccessImage = image;
}

+ (void)setErrorImage:(UIImage *)image {
    [self sharedView];
    SVProgressHUDErrorImage = image;
}

+ (void)setDefaultMaskType:(SVProgressHUDMaskType)maskType{
    [self sharedView];
    SVProgressHUDDefaultMaskType = maskType;
}

+ (void)setViewForExtension:(UIView *)view{
    [self sharedView];
    SVProgressHUDExtensionView = view;
}

+ (void)setMinimumDismissTimeInterval:(NSTimeInterval)interval {
    [self sharedView].minimumDismissTimeInterval = interval;
}

+ (void)setMaximumDismissTimeInterval:(NSTimeInterval)interval {
    [self sharedView].maximumDismissTimeInterval = interval;
}


#pragma mark - Show Methods

+ (void)show {
    [self showWithStatus:nil];
}

+ (void)showWithMaskType:(SVProgressHUDMaskType)maskType {
    [self showProgress:SVProgressHUDUndefinedProgress maskType:maskType];
}

+ (void)showWithStatus:(NSString *)status {
    [self showProgress:SVProgressHUDUndefinedProgress status:status];
}

+ (void)showWithStatus:(NSString*)status maskType:(SVProgressHUDMaskType)maskType {
    [self showProgress:SVProgressHUDUndefinedProgress status:status maskType:maskType];
}

+ (void)showProgress:(float)progress {
    [self sharedView];
    [self showProgress:progress maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showProgress:(float)progress maskType:(SVProgressHUDMaskType)maskType{
    [self showProgress:progress status:nil maskType:maskType];
}

+ (void)showProgress:(float)progress status:(NSString *)status {
    [self sharedView];
    [self showProgress:progress status:status maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showProgress:(float)progress status:(NSString *)status maskType:(SVProgressHUDMaskType)maskType {
    [[self sharedView] showProgress:progress status:status maskType:maskType];
}

+ (void)setMinimumSize:(CGSize)minimumSize {
    [self sharedView].minimumSize = minimumSize;
}

#pragma mark - Show then dismiss methods

+ (void)showInfoWithStatus:(NSString *)string {
    [self sharedView];
    [self showInfoWithStatus:string maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showInfoWithStatus:(NSString *)string maskType:(SVProgressHUDMaskType)maskType {
    [self sharedView];
    [self showImage:SVProgressHUDInfoImage status:string maskType:maskType];
}

+ (void)showSuccessWithStatus:(NSString *)string {
    [self sharedView];
    [self showSuccessWithStatus:string maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showSuccessWithStatus:(NSString *)string maskType:(SVProgressHUDMaskType)maskType {
    [self sharedView];
    [self showImage:SVProgressHUDSuccessImage status:string maskType:maskType];
}

+ (void)showErrorWithStatus:(NSString *)string {
    [self sharedView];
    [self showErrorWithStatus:string maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showErrorWithStatus:(NSString *)string maskType:(SVProgressHUDMaskType)maskType {
    [self sharedView];
    [self showImage:SVProgressHUDErrorImage status:string maskType:maskType];
}

+ (void)showImage:(UIImage *)image status:(NSString *)string {
    [self sharedView];
    [self showImage:image status:string maskType:SVProgressHUDDefaultMaskType];
}

+ (void)showImage:(UIImage *)image status:(NSString *)string maskType:(SVProgressHUDMaskType)maskType {
    NSTimeInterval displayInterval = [[self sharedView] displayDurationForString:string];
    [[self sharedView] showImage:image status:string duration:displayInterval maskType:maskType];
}

+ (void)showImages:(NSArray *)images {
    [self showImages:images maskType:SVProgressHUDMaskTypeActiveNavBar];
}

+ (void)showImages:(NSArray *)images maskType:(SVProgressHUDMaskType)maskType {
    [[self sharedView] showImages:images progress:SVProgressHUDUndefinedProgress status:nil maskType:maskType];
}


#pragma mark - Dismiss Methods

+ (void)popActivity {
    if([self sharedView].activityCount > 0)
        [self sharedView].activityCount--;
    if([self sharedView].activityCount == 0)
        [[self sharedView] dismiss];
}

+ (void)dismiss {
    if ([self isVisible]) {
        [[self sharedView] dismiss];
    }
}

+ (void)delayDismiss {
    if ([self isVisible]) {
        [[self sharedView] delayDismiss];
    }
}


#pragma mark - Offset

+ (void)setOffsetFromCenter:(UIOffset)offset {
    [self sharedView].offsetFromCenter = offset;
}

+ (void)resetOffsetFromCenter {
    [self setOffsetFromCenter:UIOffsetZero];
}


#pragma mark - Instance Methods

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.alpha = 0.0f;
        self.activityCount = 0;
        self.minimumDismissTimeInterval = 5.0;
        self.maximumDismissTimeInterval = CGFLOAT_MAX;
        self.minimumSize = CGSizeZero;
        
        SVProgressHUDBackgroundColor = [UIColor whiteColor];
        SVProgressHUDForegroundColor = [UIColor blackColor];
        if ([UIFont respondsToSelector:@selector(preferredFontForTextStyle:)]) {
            SVProgressHUDFont = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        } else {
            SVProgressHUDFont = [UIFont systemFontOfSize:14.0f];
            SVProgressHUDBackgroundColor = [UIColor colorWithWhite:0.0f alpha:0.8f];
            SVProgressHUDForegroundColor = [UIColor whiteColor];
        }
        
        NSBundle *bundle = [NSBundle bundleForClass:self.class];
        NSURL *url = [bundle URLForResource:@"SVProgressHUD" withExtension:@"bundle"];
        NSBundle *imageBundle = [NSBundle bundleWithURL:url];
        
        UIImage* infoImage = [UIImage imageWithContentsOfFile:[imageBundle pathForResource:@"info" ofType:@"png"]];
        UIImage* successImage = [UIImage imageWithContentsOfFile:[imageBundle pathForResource:@"success" ofType:@"png"]];
        UIImage* errorImage = [UIImage imageWithContentsOfFile:[imageBundle pathForResource:@"error" ofType:@"png"]];
        
        if ([[UIImage class] instancesRespondToSelector:@selector(imageWithRenderingMode:)]) {
            SVProgressHUDInfoImage = [infoImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            SVProgressHUDSuccessImage = [successImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            SVProgressHUDErrorImage = [errorImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        } else {
            SVProgressHUDInfoImage = infoImage;
            SVProgressHUDSuccessImage = successImage;
            SVProgressHUDErrorImage = errorImage;
        }
        
        SVProgressHUDRingThickness = 2;
        SVProgressHUDDefaultMaskType = SVProgressHUDMaskTypeNone;
    }
    
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    switch (self.maskType) {
        case SVProgressHUDMaskTypeBlack: {
            
            [[UIColor colorWithWhite:0 alpha:0.5] set];
            CGContextFillRect(context, self.bounds);
            
            break;
        }
        case SVProgressHUDMaskTypeActiveNavBar: {
            
            [[UIColor colorWithWhite:0 alpha:0.5] set];
            CGContextFillRect(context, self.bounds);
            
            break;
        }
        case SVProgressHUDMaskTypeGradient: {
            
            size_t locationsCount = 2;
            CGFloat locations[2] = {0.0f, 1.0f};
            CGFloat colors[8] = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.75f};
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, locationsCount);
            CGColorSpaceRelease(colorSpace);
            
            CGFloat freeHeight = CGRectGetHeight(self.bounds) - self.visibleKeyboardHeight;
            
            CGPoint center = CGPointMake(CGRectGetWidth(self.bounds)/2, freeHeight/2);
            float radius = MIN(CGRectGetWidth(self.bounds) , CGRectGetHeight(self.bounds)) ;
            CGContextDrawRadialGradient (context, gradient, center, 0, center, radius, kCGGradientDrawsAfterEndLocation);
            CGGradientRelease(gradient);
            
            break;
        }
        default:
            break;
    }
}

- (void)updatePosition {
    
    BOOL imageUsed = (self.imageView.image) && !(self.imageView.hidden);
    BOOL progressUsed = self.imageView.hidden;
    
    // Calculate size of string
    CGRect labelRect = CGRectZero;
    CGFloat labelHeight = 0.0f;
    CGFloat labelWidth = 0.0f;
    
    if(self.stringLabel.text) {
        CGSize constraintSize = CGSizeMake(200.0f, 300.0f);
        labelRect = [self.stringLabel.text boundingRectWithSize:constraintSize
                                                        options:(NSStringDrawingOptions)(NSStringDrawingUsesFontLeading | NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin)
                                                     attributes:@{NSFontAttributeName: self.stringLabel.font}
                                                        context:NULL];
        labelHeight = ceilf(CGRectGetHeight(labelRect));
        labelWidth = ceilf(CGRectGetWidth(labelRect));
    }
    
    // Calculate hud size based on content
    // For the beginning use default values, these
    // might get update if string is too large etc.
    CGFloat hudWidth;
    CGFloat hudHeight;
    
    CGFloat contentWidth = 0.0f;
    CGFloat contentHeight = 0.0f;
    
    if(imageUsed || progressUsed) {
        contentWidth = CGRectGetWidth(imageUsed ? self.imageView.frame : self.indefiniteAnimatedView.frame);
        contentHeight = CGRectGetHeight(imageUsed ? self.imageView.frame : self.indefiniteAnimatedView.frame);
    }
    
    // |-spacing-content-spacing-|
    hudWidth = SVProgressHUDHorizontalSpacing + MAX(labelWidth, contentWidth) + SVProgressHUDHorizontalSpacing;
    
    // |-spacing-content-(labelSpacing-label-)spacing-|
    hudHeight = SVProgressHUDVerticalSpacing + labelHeight + contentHeight + SVProgressHUDVerticalSpacing;
    if(self.stringLabel.text && (imageUsed || progressUsed)){
        // Add spacing if both content and label are used
        hudHeight += SVProgressHUDLabelSpacing;
    }
    
    // Update values on subviews
    self.hudView.bounds = CGRectMake(0.0f, 0.0f, MAX(self.minimumSize.width, hudWidth), MAX(self.minimumSize.height, hudHeight));
    
    // Animate value update
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    // Spinner and image view
    CGFloat centerY;
    if(self.stringLabel.text) {
        CGFloat yOffset = MAX(SVProgressHUDVerticalSpacing, (self.minimumSize.height - contentHeight - SVProgressHUDLabelSpacing - labelHeight) / 2.0f);
        centerY = yOffset + contentHeight / 2.0f;
    } else {
        centerY = CGRectGetMidY(self.hudView.bounds);
    }
    self.indefiniteAnimatedView.center = CGPointMake(CGRectGetMidX(self.hudView.bounds), centerY);
    if(self.progress != SVProgressHUDUndefinedProgress) {
        CGRect backgroundRingLayerFrame = _backgroundRingLayer.frame;
        backgroundRingLayerFrame.origin.x = CGRectGetMidX(self.hudView.bounds) - SVProgressHUDRingRadius;
        backgroundRingLayerFrame.origin.y = centerY - SVProgressHUDRingRadius;
        _backgroundRingLayer.frame = backgroundRingLayerFrame;
        
        CGRect ringLayerFrame = _ringLayer.frame;
        ringLayerFrame.origin.x = CGRectGetMidX(self.hudView.bounds) - SVProgressHUDRingRadius;
        ringLayerFrame.origin.y = centerY - SVProgressHUDRingRadius;
        _ringLayer.frame = ringLayerFrame;
    }
    self.imageView.center = CGPointMake(CGRectGetMidX(self.hudView.bounds), centerY);
    
    // Label
    if(imageUsed || progressUsed) {
        centerY = CGRectGetMaxY(imageUsed ? self.imageView.frame : self.indefiniteAnimatedView.frame) + SVProgressHUDLabelSpacing + labelHeight / 2.0f;
    } else {
        centerY = CGRectGetMidY(self.hudView.bounds);
    }
    self.stringLabel.frame = labelRect;
    self.stringLabel.center = CGPointMake(CGRectGetMidX(self.hudView.bounds), centerY);
    
    [CATransaction commit];
}

- (void)setStatus:(NSString *)string {
    self.stringLabel.text = string;
    [self updatePosition];
    
}

- (void)setFadeOutTimer:(NSTimer *)newTimer {
    if(_fadeOutTimer)
        [_fadeOutTimer invalidate], _fadeOutTimer = nil;
    
    if(newTimer)
        _fadeOutTimer = newTimer;
}


- (void)registerNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(positionHUD:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(positionHUD:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(positionHUD:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(positionHUD:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(positionHUD:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
}


- (NSDictionary *)notificationUserInfo{
    return (self.stringLabel.text ? @{SVProgressHUDStatusUserInfoKey : self.stringLabel.text} : nil);
}


- (void)positionHUD:(NSNotification*)notification {
    
    CGFloat keyboardHeight = 0.0f;
    double animationDuration = 0.0;
    
    self.frame = UIScreen.mainScreen.bounds;
    
#if !defined(SV_APP_EXTENSIONS)
    UIInterfaceOrientation orientation = UIApplication.sharedApplication.statusBarOrientation;
#else
    UIInterfaceOrientation orientation = CGRectGetWidth(self.frame) > CGRectGetHeight(self.frame) ? UIInterfaceOrientationLandscapeLeft : UIInterfaceOrientationPortrait;
#endif
    // no transforms applied to window in iOS 8, but only if compiled with iOS 8 sdk as base sdk, otherwise system supports old rotation logic.
    BOOL ignoreOrientation = NO;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(operatingSystemVersion)]) {
        ignoreOrientation = YES;
    }
#endif
    
    if(notification) {
        NSDictionary* keyboardInfo = [notification userInfo];
        CGRect keyboardFrame = [[keyboardInfo valueForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
        animationDuration = [[keyboardInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        
        if(notification.name == UIKeyboardWillShowNotification || notification.name == UIKeyboardDidShowNotification) {
            if(ignoreOrientation || UIInterfaceOrientationIsPortrait(orientation))
                keyboardHeight = CGRectGetHeight(keyboardFrame);
            else
                keyboardHeight = CGRectGetWidth(keyboardFrame);
        }
    } else {
        keyboardHeight = self.visibleKeyboardHeight;
    }
    
    CGRect orientationFrame = self.bounds;
#if !defined(SV_APP_EXTENSIONS)
    CGRect statusBarFrame = UIApplication.sharedApplication.statusBarFrame;
#else
    CGRect statusBarFrame = CGRectZero;
#endif
    
    if(!ignoreOrientation && UIInterfaceOrientationIsLandscape(orientation)) {
        float temp = CGRectGetWidth(orientationFrame);
        orientationFrame.size.width = CGRectGetHeight(orientationFrame);
        orientationFrame.size.height = temp;
        
        temp = CGRectGetWidth(statusBarFrame);
        statusBarFrame.size.width = CGRectGetHeight(statusBarFrame);
        statusBarFrame.size.height = temp;
    }
    
    CGFloat activeHeight = CGRectGetHeight(orientationFrame);
    
    if(keyboardHeight > 0)
        activeHeight += CGRectGetHeight(statusBarFrame)*2;
    
    activeHeight -= keyboardHeight;
    CGFloat posY = floor(activeHeight*0.45);
    CGFloat posX = CGRectGetWidth(orientationFrame)/2;
    
    CGPoint newCenter;
    CGFloat rotateAngle;
    
    if (ignoreOrientation) {
        rotateAngle = 0.0;
        newCenter = CGPointMake(posX, posY + ((self.maskType == SVProgressHUDMaskTypeActiveNavBar) ? 0 : topOffset));
    } else {
        switch (orientation) {
            case UIInterfaceOrientationPortraitUpsideDown:
                rotateAngle = M_PI;
                newCenter = CGPointMake(posX, CGRectGetHeight(orientationFrame)-posY);
                break;
            case UIInterfaceOrientationLandscapeLeft:
                rotateAngle = -M_PI/2.0f;
                newCenter = CGPointMake(posY, posX);
                break;
            case UIInterfaceOrientationLandscapeRight:
                rotateAngle = M_PI/2.0f;
                newCenter = CGPointMake(CGRectGetHeight(orientationFrame)-posY, posX);
                break;
            default: // as UIInterfaceOrientationPortrait
                rotateAngle = 0.0;
                newCenter = CGPointMake(posX, posY);
                break;
        }
    }
    
    if(notification) {
        [UIView animateWithDuration:animationDuration
                              delay:0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{
                             [self moveToPoint:newCenter rotateAngle:rotateAngle];
                             [self.hudView setNeedsDisplay];
                         } completion:NULL];
    } else {
        [self moveToPoint:newCenter rotateAngle:rotateAngle];
        [self.hudView setNeedsDisplay];
    }
    
}

- (void)moveToPoint:(CGPoint)newCenter rotateAngle:(CGFloat)angle {
    self.hudView.transform = CGAffineTransformMakeRotation(angle);
    self.hudView.center = CGPointMake(newCenter.x + self.offsetFromCenter.horizontal, newCenter.y + self.offsetFromCenter.vertical-20);
}

- (void)overlayViewDidReceiveTouchEvent:(id)sender forEvent:(UIEvent *)event {
    [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDDidReceiveTouchEventNotification object:event];
    
    UITouch *touch = event.allTouches.anyObject;
    CGPoint touchLocation = [touch locationInView:self];
    
    if (CGRectContainsPoint(self.hudView.frame, touchLocation)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDDidTouchDownInsideNotification object:event];
    }
}


#pragma mark - Master show/dismiss methods

- (void)showProgress:(float)progress status:(NSString*)string maskType:(SVProgressHUDMaskType)hudMaskType {
    if(!self.overlayView.superview){
#if !defined(SV_APP_EXTENSIONS)
        NSEnumerator *frontToBackWindows = [UIApplication.sharedApplication.windows reverseObjectEnumerator];
        for (UIWindow *window in frontToBackWindows){
            BOOL windowOnMainScreen = window.screen == UIScreen.mainScreen;
            BOOL windowIsVisible = !window.hidden && window.alpha > 0;
            BOOL windowLevelNormal = window.windowLevel == UIWindowLevelNormal;
            
            if (windowOnMainScreen && windowIsVisible && windowLevelNormal) {
                [window addSubview:self.overlayView];
                break;
            }
        }
#else
        if(SVProgressHUDExtensionView){
            [SVProgressHUDExtensionView addSubview:self.overlayView];
        }
#endif
    } else {
        // Ensure that overlay will be exactly on top of rootViewController (which may be changed during runtime).
        [self.overlayView.superview bringSubviewToFront:self.overlayView];
    }
    
    if(!self.superview)
        [self.overlayView addSubview:self];
    
    [self.imageView setAnimationImages:nil];
    
    self.fadeOutTimer = nil;
    self.imageView.hidden = YES;
    self.maskType = hudMaskType;
    self.progress = progress;
    
    self.stringLabel.text = string;
    [self updatePosition];
    
    if(progress >= 0) {
        self.imageView.image = nil;
        self.imageView.hidden = NO;
        [self.indefiniteAnimatedView removeFromSuperview];
        
        self.ringLayer.strokeEnd = progress;
        
        if(progress == 0)
            self.activityCount++;
    } else {
        self.activityCount++;
        [self cancelRingLayerAnimation];
        [self.hudView addSubview:self.indefiniteAnimatedView];
    }
    
    if(self.maskType != SVProgressHUDMaskTypeNone) {
        self.overlayView.userInteractionEnabled = YES;
        self.accessibilityLabel = string;
        self.isAccessibilityElement = YES;
        
        if (self.maskType == SVProgressHUDMaskTypeActiveNavBar) {
            self.overlayView.frame = SVProgressHUDEnableNavBarFrame;
        } else {
            self.overlayView.frame = SVProgressHUDNonEnableNavBarFrame;
        }
        [self.overlayView setNeedsDisplay];
        [self.hudView setCenter:CGPointMake(self.overlayView.frame.size.width/2, self.overlayView.frame.size.height/2 + (self.maskType == SVProgressHUDMaskTypeActiveNavBar ? 0 : 10))];
    } else {
        self.overlayView.userInteractionEnabled = NO;
        self.hudView.accessibilityLabel = string;
        self.hudView.isAccessibilityElement = YES;
    }
    
    [self.overlayView setHidden:NO];
    self.overlayView.backgroundColor = [UIColor clearColor];
    [self positionHUD:nil];
    
    if(self.alpha != 1 || self.hudView.alpha != 1) {
        NSDictionary *userInfo = [self notificationUserInfo];
        [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDWillAppearNotification
                                                            object:nil
                                                          userInfo:userInfo];
        
        [self registerNotifications];
        if (!self.noTransform) {
            self.hudView.transform = CGAffineTransformScale(self.hudView.transform, 1.3, 1.3);
        }
        
        if(self.isClear) {
            self.alpha = 1;
            self.hudView.alpha = 0;
        }
        
        [UIView animateWithDuration:0.15
                              delay:0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             if (!self.noTransform) {
                                 self.hudView.transform = CGAffineTransformScale(self.hudView.transform, 1/1.3, 1/1.3);
                             }
                             
                             if(self.isClear) // handle iOS 7 and 8 UIToolbar which not answers well to hierarchy opacity change
                                 self.hudView.alpha = 1;
                             else
                                 self.alpha = 1;
                         }
                         completion:^(BOOL finished){
                             [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDDidAppearNotification
                                                                                 object:nil
                                                                               userInfo:userInfo];
                             UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
                             UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, string);
                         }];
        
        [self setNeedsDisplay];
    }
}

- (UIImage *)image:(UIImage *)image withTintColor:(UIColor *)color{
    CGRect rect = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, image.scale);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [image drawInRect:rect];
    CGContextSetFillColorWithColor(c, [color CGColor]);
    CGContextSetBlendMode(c, kCGBlendModeSourceAtop);
    CGContextFillRect(c, rect);
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return tintedImage;
}

//showProgress:(float)progress status:(NSString*)string maskType:(SVProgressHUDMaskType)hudMaskType

- (void)showImages:(NSArray *)images progress:(float)progress status:(NSString*)string maskType:(SVProgressHUDMaskType)hudMaskType {
    
    if(!self.overlayView.superview){
#if !defined(SV_APP_EXTENSIONS)
        NSEnumerator *frontToBackWindows = [UIApplication.sharedApplication.windows reverseObjectEnumerator];
        for (UIWindow *window in frontToBackWindows){
            BOOL windowOnMainScreen = window.screen == UIScreen.mainScreen;
            BOOL windowIsVisible = !window.hidden && window.alpha > 0;
            BOOL windowLevelNormal = window.windowLevel == UIWindowLevelNormal;
            
            if (windowOnMainScreen && windowIsVisible && windowLevelNormal) {
                if(!window || !_overlayView) break;
                [window addSubview:self.overlayView];
                break;
            }
        }
#else
        if(SVProgressHUDExtensionView){
            [SVProgressHUDExtensionView addSubview:self.overlayView];
        }
#endif
    } else {
        // Ensure that overlay will be exactly on top of rootViewController (which may be changed during runtime).
        [self.overlayView.superview bringSubviewToFront:self.overlayView];
    }
    
    if(!self.superview)
        [self.overlayView addSubview:self];
    
    self.fadeOutTimer = nil;
    
    self.imageView.animationImages = images;
    self.imageView.hidden = NO;
    [self.imageView startAnimating];
    
    //    self.imageView.hidden = YES;
    self.maskType = hudMaskType;
    //    self.progress = progress;
    
    self.stringLabel.text = string;
    [self updatePosition];
    
    if(progress >= 0) {
        self.imageView.image = nil;
        self.imageView.hidden = NO;
        [self.indefiniteAnimatedView removeFromSuperview];
        
        self.ringLayer.strokeEnd = progress;
        
        if(progress == 0)
            self.activityCount++;
    } else {
        self.activityCount++;
        [self cancelRingLayerAnimation];
        [self.hudView addSubview:self.indefiniteAnimatedView];
    }
    
    if(self.maskType != SVProgressHUDMaskTypeNone) {
        self.overlayView.userInteractionEnabled = YES;
        self.accessibilityLabel = string;
        self.isAccessibilityElement = YES;
        
        if (self.maskType == SVProgressHUDMaskTypeActiveNavBar) {
            self.overlayView.frame = SVProgressHUDEnableNavBarFrame;
        } else {
            self.overlayView.frame = SVProgressHUDNonEnableNavBarFrame;
        }
        [self.overlayView setNeedsDisplay];
        [self.hudView setCenter:CGPointMake(self.overlayView.frame.size.width/2, self.overlayView.frame.size.height/2 + (self.maskType == SVProgressHUDMaskTypeActiveNavBar ? 0 : 10))];
    } else {
        self.overlayView.userInteractionEnabled = NO;
        self.hudView.accessibilityLabel = string;
        self.hudView.isAccessibilityElement = YES;
    }
    
    [self.overlayView setHidden:NO];
    self.overlayView.backgroundColor = [UIColor clearColor];
    [self positionHUD:nil];
    
    if(self.alpha != 1 || self.hudView.alpha != 1) {
        NSDictionary *userInfo = [self notificationUserInfo];
        [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDWillAppearNotification
                                                            object:nil
                                                          userInfo:userInfo];
        
        [self registerNotifications];
        if (!self.noTransform) {
            self.hudView.transform = CGAffineTransformScale(self.hudView.transform, 1.3, 1.3);
        }
        
        if(self.isClear) {
            self.alpha = 1;
            self.hudView.alpha = 0;
        }
        
        
        [UIView animateWithDuration:0.15
                              delay:0
                            options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             if (!self.noTransform) {
                                 self.hudView.transform = CGAffineTransformScale(self.hudView.transform, 1/1.3, 1/1.3);
                             }
                             
                             if(self.isClear) // handle iOS 7 and 8 UIToolbar which not answers well to hierarchy opacity change
                                 self.hudView.alpha = 1;
                             else
                                 self.alpha = 1;
                         }
                         completion:^(BOOL finished){
                             [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDDidAppearNotification
                                                                                 object:nil
                                                                               userInfo:userInfo];
                             UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
                             UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, string);
                         }];
        
        [self setNeedsDisplay];
    }
}

- (void)showImage:(UIImage *)image status:(NSString *)string duration:(NSTimeInterval)duration maskType:(SVProgressHUDMaskType)hudMaskType {
    self.progress = SVProgressHUDUndefinedProgress;
    self.maskType = hudMaskType;
    [self cancelRingLayerAnimation];
    
    if(![self.class isVisible])
        [self.class showWithMaskType:self.maskType];
    
    if ([self.imageView respondsToSelector:@selector(setTintColor:)]) {
        self.imageView.tintColor = SVProgressHUDForegroundColor;
    } else {
        image = [self image:image withTintColor:SVProgressHUDForegroundColor];
    }
    [self.imageView setAnimationImages:nil];
    self.imageView.image = image;
    self.imageView.hidden = NO;
    
    self.stringLabel.text = string;
    [self updatePosition];
    [self.indefiniteAnimatedView removeFromSuperview];
    
    if(self.maskType != SVProgressHUDMaskTypeNone) {
        self.overlayView.userInteractionEnabled = YES;
        self.accessibilityLabel = string;
        self.isAccessibilityElement = YES;
        
        if (self.maskType == SVProgressHUDMaskTypeActiveNavBar) {
            self.overlayView.frame = SVProgressHUDEnableNavBarFrame;
        } else {
            self.overlayView.frame = SVProgressHUDNonEnableNavBarFrame;
        }
        [self.overlayView setNeedsDisplay];
        [self.hudView setCenter:CGPointMake(self.overlayView.frame.size.width/2, self.overlayView.frame.size.height/2 + (self.maskType == SVProgressHUDMaskTypeActiveNavBar ? 0 : 10))];
    } else {
        self.overlayView.userInteractionEnabled = NO;
        self.hudView.accessibilityLabel = string;
        self.hudView.isAccessibilityElement = YES;
    }
    
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, string);
    
    self.fadeOutTimer = [NSTimer timerWithTimeInterval:duration target:self selector:@selector(dismiss) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.fadeOutTimer forMode:NSRunLoopCommonModes];
}

- (void)realDismiss {
    NSDictionary *userInfo = [self notificationUserInfo];
    if (self.activityCount) {
        return;
    }
    [UIView animateWithDuration:0.15
                          delay:0
                        options:UIViewAnimationCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
                         if (!self.noTransform) {
                             self.hudView.transform = CGAffineTransformScale(self.hudView.transform, 0.8f, 0.8f);
                         }
                         if(self.isClear) // handle iOS 7 UIToolbar not answer well to hierarchy opacity change
                             self.hudView.alpha = 0.0f;
                         else
                             self.alpha = 0.0f;
                     }
                     completion:^(BOOL finished){
                         if(self.alpha == 0.0f || self.hudView.alpha == 0.0f) {
                             self.alpha = 0.0f;
                             self.hudView.alpha = 0.0f;
                             
                             [[NSNotificationCenter defaultCenter] removeObserver:self];
                             [self cancelRingLayerAnimation];
                             [_hudView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                 [obj removeFromSuperview];
                             }];
                             [_hudView removeFromSuperview];
                             _hudView = nil;
                             
                             [_overlayView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                 [obj removeFromSuperview];
                             }];
                             [_overlayView removeFromSuperview];
                             _overlayView = nil;
                             
                             [_indefiniteAnimatedView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                 [obj removeFromSuperview];
                             }];
                             [_indefiniteAnimatedView removeFromSuperview];
                             _indefiniteAnimatedView = nil;
                             
                             UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil);
                             
                             [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDDidDisappearNotification
                                                                                 object:nil
                                                                               userInfo:userInfo];
                             
                             // Tell the rootViewController to update the StatusBar appearance
#if !defined(SV_APP_EXTENSIONS)
                             UIViewController *rootController = [[UIApplication sharedApplication] keyWindow].rootViewController;
                             if ([rootController respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
                                 [rootController setNeedsStatusBarAppearanceUpdate];
                             }
#endif
                             // uncomment to make sure UIWindow is gone from app.windows
                             //NSLog(@"%@", [UIApplication sharedApplication].windows);
                             //NSLog(@"keyWindow = %@", [UIApplication sharedApplication].keyWindow);
                         }
                     }];
}

- (void)dismiss {
    NSDictionary *userInfo = [self notificationUserInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDWillDisappearNotification
                                                        object:nil
                                                      userInfo:userInfo];
    self.activityCount = 0;
    [self realDismiss];
}

- (void)delayDismiss {
    NSDictionary *userInfo = [self notificationUserInfo];
    [[NSNotificationCenter defaultCenter] postNotificationName:SVProgressHUDWillDisappearNotification
                                                        object:nil
                                                      userInfo:userInfo];
    self.activityCount = 0;
    
    [self performSelector:@selector(realDismiss) withObject:nil afterDelay:0.2];
    
}


#pragma mark - Ring progress animation

- (SVIndefiniteAnimatedView *)indefiniteAnimatedView {
    if (_indefiniteAnimatedView == nil) {
        _indefiniteAnimatedView = [[SVIndefiniteAnimatedView alloc] initWithFrame:CGRectZero];
        _indefiniteAnimatedView.strokeThickness = SVProgressHUDRingThickness;
        _indefiniteAnimatedView.strokeColor = SVProgressHUDForegroundColor;
        _indefiniteAnimatedView.radius = self.stringLabel.text ? SVProgressHUDRingRadius : SVProgressHUDRingNoTextRadius;
        [_indefiniteAnimatedView sizeToFit];
    }
    return _indefiniteAnimatedView;
}

- (CAShapeLayer *)ringLayer {
    if(!_ringLayer) {
        CGPoint center = CGPointMake(CGRectGetWidth(_hudView.frame)/2, CGRectGetHeight(_hudView.frame)/2);
        _ringLayer = [self createRingLayerWithCenter:center
                                              radius:SVProgressHUDRingRadius
                                           lineWidth:SVProgressHUDRingThickness
                                               color:SVProgressHUDForegroundColor];
        [self.hudView.layer addSublayer:_ringLayer];
    }
    return _ringLayer;
}

- (CAShapeLayer *)backgroundRingLayer {
    if(!_backgroundRingLayer) {
        CGPoint center = CGPointMake(CGRectGetWidth(_hudView.frame)/2, CGRectGetHeight(_hudView.frame)/2);
        _backgroundRingLayer = [self createRingLayerWithCenter:center
                                                        radius:SVProgressHUDRingRadius
                                                     lineWidth:SVProgressHUDRingThickness
                                                         color:[SVProgressHUDForegroundColor colorWithAlphaComponent:0.1f]];
        _backgroundRingLayer.strokeEnd = 1;
        [self.hudView.layer addSublayer:_backgroundRingLayer];
    }
    return _backgroundRingLayer;
}

- (void)cancelRingLayerAnimation {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_hudView.layer removeAllAnimations];
    
    _ringLayer.strokeEnd = 0.0f;
    if (_ringLayer.superlayer) {
        [_ringLayer removeFromSuperlayer];
    }
    _ringLayer = nil;
    
    if (_backgroundRingLayer.superlayer) {
        [_backgroundRingLayer removeFromSuperlayer];
    }
    _backgroundRingLayer = nil;
    
    [CATransaction commit];
}

- (CAShapeLayer *)createRingLayerWithCenter:(CGPoint)center radius:(CGFloat)radius lineWidth:(CGFloat)lineWidth color:(UIColor *)color {
    
    UIBezierPath* smoothedPath = [UIBezierPath bezierPathWithArcCenter:CGPointMake(radius, radius) radius:radius startAngle:-M_PI_2 endAngle:(M_PI + M_PI_2) clockwise:YES];
    
    CAShapeLayer *slice = [CAShapeLayer layer];
    slice.contentsScale = [[UIScreen mainScreen] scale];
    slice.frame = CGRectMake(center.x-radius, center.y-radius, radius*2, radius*2);
    slice.fillColor = [UIColor clearColor].CGColor;
    slice.strokeColor = color.CGColor;
    slice.lineWidth = lineWidth;
    slice.lineCap = kCALineCapRound;
    slice.lineJoin = kCALineJoinBevel;
    slice.path = smoothedPath.CGPath;
    
    return slice;
}

#pragma mark - Utilities

+ (BOOL)isVisible {
    return ([self sharedView].alpha == 1);
}


#pragma mark - Getters

- (NSTimeInterval)displayDurationForString:(NSString*)string {
    CGFloat minimum = MAX((CGFloat)string.length * 0.06 + 0.5, self.minimumDismissTimeInterval);
    return MIN(minimum, self.maximumDismissTimeInterval);
}

- (BOOL)isClear { // used for iOS 7 and above
    return (self.maskType == SVProgressHUDMaskTypeClear || self.maskType == SVProgressHUDMaskTypeNone);
}

- (UIControl *)overlayView {
    if(!_overlayView) {
        //        _overlayView = [[UIControl alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _overlayView = [[UIControl alloc] initWithFrame:SVProgressHUDNonEnableNavBarFrame];
        _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _overlayView.backgroundColor = [UIColor clearColor];
        [_overlayView addTarget:self action:@selector(overlayViewDidReceiveTouchEvent:forEvent:) forControlEvents:UIControlEventTouchDown];
    }
    return _overlayView;
}

- (UIView *)hudView {
    if(!_hudView) {
        _hudView = [[UIView alloc] initWithFrame:CGRectZero];
        _hudView.backgroundColor = SVProgressHUDBackgroundColor;
        _hudView.layer.cornerRadius = 14;
        _hudView.layer.masksToBounds = YES;
        
        _hudView.autoresizingMask = (UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin |
                                     UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin);
        
        if ([_hudView respondsToSelector:@selector(addMotionEffect:)]) {
            UIInterpolatingMotionEffect *effectX = [[UIInterpolatingMotionEffect alloc] initWithKeyPath: @"center.x" type: UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
            effectX.minimumRelativeValue = @(-SVProgressHUDParallaxDepthPoints);
            effectX.maximumRelativeValue = @(SVProgressHUDParallaxDepthPoints);
            
            UIInterpolatingMotionEffect *effectY = [[UIInterpolatingMotionEffect alloc] initWithKeyPath: @"center.y" type: UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
            effectY.minimumRelativeValue = @(-SVProgressHUDParallaxDepthPoints);
            effectY.maximumRelativeValue = @(SVProgressHUDParallaxDepthPoints);
            
            UIMotionEffectGroup *effectGroup = [[UIMotionEffectGroup alloc] init];
            effectGroup.motionEffects = @[effectX, effectY];
            [_hudView addMotionEffect:effectGroup];
        }
    }
    
    if(!_hudView.superview)
        [self addSubview:_hudView];
    
    return _hudView;
}

- (UILabel *)stringLabel {
    if (!_stringLabel) {
        _stringLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _stringLabel.backgroundColor = [UIColor clearColor];
        _stringLabel.adjustsFontSizeToFitWidth = YES;
        _stringLabel.textAlignment = NSTextAlignmentCenter;
        _stringLabel.baselineAdjustment = UIBaselineAdjustmentAlignCenters;
        _stringLabel.numberOfLines = 0;
    }
    
    if(!_stringLabel.superview)
        [self.hudView addSubview:_stringLabel];
    
    _stringLabel.textColor = SVProgressHUDForegroundColor;
    _stringLabel.font = SVProgressHUDFont;
    
    return _stringLabel;
}

- (UIImageView *)imageView {
    if (!_imageView)
        _imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 28.0f, 28.0f)];
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    
    if(!_imageView.superview)
        [self.hudView addSubview:_imageView];
    
    return _imageView;
}


- (CGFloat)visibleKeyboardHeight {
#if !defined(SV_APP_EXTENSIONS)
    UIWindow *keyboardWindow = nil;
    for (UIWindow *testWindow in [[UIApplication sharedApplication] windows]) {
        if(![[testWindow class] isEqual:[UIWindow class]]) {
            keyboardWindow = testWindow;
            break;
        }
    }
    
    for (__strong UIView *possibleKeyboard in keyboardWindow.subviews) {
        NSString *viewName = NSStringFromClass(possibleKeyboard.class);
        if([viewName hasPrefix:@"UI"]){
            if([viewName hasSuffix:@"PeripheralHostView"] || [viewName hasSuffix:@"Keyboard"]){
                return CGRectGetHeight(possibleKeyboard.bounds);
            } else if ([viewName hasSuffix:@"InputSetContainerView"]){
                for (__strong UIView *possibleKeyboardSubview in possibleKeyboard.subviews) {
                    viewName = NSStringFromClass(possibleKeyboardSubview.class);
                    if([viewName hasPrefix:@"UI"] && [viewName hasSuffix:@"InputSetHostView"]) {
                        CGRect convertedRect = [possibleKeyboard convertRect:possibleKeyboardSubview.frame toView:self];
                        CGRect intersectedRect = CGRectIntersection(convertedRect, self.bounds);
                        if (!CGRectIsNull(intersectedRect)) {
                            return CGRectGetHeight(intersectedRect);
                        }
                    }
                }
            }
        }
    }
#endif
    return 0;
}

@end

