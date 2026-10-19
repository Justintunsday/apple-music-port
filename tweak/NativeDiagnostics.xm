#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Capture the native view tree. No player UI, playback calls, layout hooks,
// geometry writes, constraint changes or orientation overrides.
static NSMutableArray *MLSnapshots;
static BOOL MLQueued, MLExporting;
static NSUInteger MLAutoCount;
static NSString *MLClass(id value) { return value ? NSStringFromClass([value class]) : @"nil"; }
static NSString *MLPath(NSMapTable *paths, id value) { return value ? ([paths objectForKey:value] ?: @"unmapped") : @"nil"; }
static NSArray<UIWindow *> *MLWindows(void) {
    NSMutableArray *result = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden && window.rootViewController) [result addObject:window];
    }
    return result;
}
static NSArray *MLMethods(Class cls) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *result = [NSMutableArray new];
    for (unsigned i = 0; i < MIN(count, 500u); i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lower = name.lowercaseString;
        for (NSString *term in @[@"layout", @"view", @"orientation", @"trait", @"artwork", @"lyric", @"metric"])
            if ([lower containsString:term]) { [result addObject:name]; break; }
    }
    free(methods);
    return result;
}
static NSDictionary *MLCapture(NSString *reason) {
    CFTimeInterval start = CACurrentMediaTime();
    NSMutableArray *views = [NSMutableArray new], *controllers = [NSMutableArray new];
    NSMutableArray *viewRecords = [NSMutableArray new], *controllerRecords = [NSMutableArray new], *windowRecords = [NSMutableArray new];
    NSMapTable *paths = [NSMapTable strongToStrongObjectsMapTable];
    for (UIWindow *window in MLWindows()) {
        NSString *path = [NSString stringWithFormat:@"window/%lu", (unsigned long)windowRecords.count];
        [views addObject:window];
        [paths setObject:path forKey:window];
        [controllers addObject:window.rootViewController];
        [windowRecords addObject:@{@"path":path, @"class":MLClass(window), @"bounds":NSStringFromCGRect(window.bounds),
            @"safeArea":NSStringFromUIEdgeInsets(window.safeAreaInsets), @"orientation":@(window.windowScene.interfaceOrientation)}];
    }
    BOOL truncated = NO;
    for (NSUInteger i = 0; i < views.count; i++) {
        if (i >= 1200 || CACurrentMediaTime() - start > 0.05) { truncated = YES; break; }
        UIView *view = views[i];
        NSString *path = [paths objectForKey:view];
        NSUInteger childIndex = 0;
        for (UIView *child in view.subviews) {
            if (views.count >= 1200) { truncated = YES; break; }
            [paths setObject:[path stringByAppendingFormat:@"/%lu", (unsigned long)childIndex++] forKey:child];
            [views addObject:child];
        }
        NSMutableArray *constraints = [NSMutableArray new];
        for (NSLayoutConstraint *c in view.constraints) {
            if (constraints.count >= 100) { truncated = YES; break; }
            [constraints addObject:@{@"firstClass":MLClass(c.firstItem), @"secondClass":MLClass(c.secondItem),
                @"firstPath":MLPath(paths, c.firstItem), @"secondPath":MLPath(paths, c.secondItem),
                @"firstAttribute":@(c.firstAttribute), @"secondAttribute":@(c.secondAttribute), @"relation":@(c.relation),
                @"constant":@(c.constant), @"multiplier":@(c.multiplier), @"priority":@(c.priority), @"active":@(c.active)}];
        }
        [viewRecords addObject:@{@"path":path, @"class":MLClass(view), @"frame":NSStringFromCGRect(view.frame),
            @"bounds":NSStringFromCGRect(view.bounds), @"transform":NSStringFromCGAffineTransform(view.transform),
            @"hidden":@(view.hidden), @"alpha":@(view.alpha), @"autoresizingMask":@(view.autoresizingMask),
            @"translatesMask":@(view.translatesAutoresizingMaskIntoConstraints), @"constraints":constraints}];
    }
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSUInteger i = 0; i < controllers.count; i++) {
        if (i >= 100 || CACurrentMediaTime() - start > 0.075) { truncated = YES; break; }
        UIViewController *controller = controllers[i];
        if ([seen containsObject:controller]) continue;
        [seen addObject:controller];
        for (UIViewController *child in controller.childViewControllers) {
            if (controllers.count >= 100) { truncated = YES; break; }
            [controllers addObject:child];
        }
        if (controller.presentedViewController && controllers.count < 100) [controllers addObject:controller.presentedViewController];
        [controllerRecords addObject:@{@"class":MLClass(controller), @"parentClass":MLClass(controller.parentViewController),
            @"viewClass":MLClass(controller.viewIfLoaded), @"viewPath":MLPath(paths, controller.viewIfLoaded),
            @"methods":MLMethods(controller.class)}];
    }
    return @{@"reason":reason, @"timestamp":@([NSDate.date timeIntervalSince1970]), @"systemVersion":UIDevice.currentDevice.systemVersion,
        @"deviceOrientation":@(UIDevice.currentDevice.orientation), @"windows":windowRecords, @"views":viewRecords,
        @"controllers":controllerRecords, @"truncated":@(truncated), @"captureMilliseconds":@((CACurrentMediaTime() - start) * 1000)};
}

@interface MLNativeDiagnostics : NSObject
+ (instancetype)shared;
- (void)active:(NSNotification *)note;
- (void)orientation:(NSNotification *)note;
- (void)export:(UITapGestureRecognizer *)gesture;
@end
@implementation MLNativeDiagnostics
+ (instancetype)shared {
    static MLNativeDiagnostics *observer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ observer = [MLNativeDiagnostics new]; MLSnapshots = [NSMutableArray new]; });
    return observer;
}
- (void)record:(NSString *)reason {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || MLExporting) return;
    NSDictionary *snapshot = MLCapture(reason);
    if (MLSnapshots.count >= 8) [MLSnapshots removeObjectAtIndex:0];
    [MLSnapshots addObject:snapshot];
}
- (void)active:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in MLWindows()) {
            if (!window.isKeyWindow) continue;
            BOOL installed = NO;
            for (UIGestureRecognizer *gesture in window.gestureRecognizers)
                if ([gesture.name isEqualToString:@"MusicLandscape.NativeReport"]) installed = YES;
            if (installed) continue;
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(export:)];
            tap.name = @"MusicLandscape.NativeReport";
            tap.numberOfTouchesRequired = 3;
            tap.numberOfTapsRequired = 2;
            tap.cancelsTouchesInView = NO;
            [window addGestureRecognizer:tap];
        }
    });
}
- (void)orientation:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MLQueued || MLExporting || MLAutoCount >= 6) return;
        MLQueued = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            MLQueued = NO;
            if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || MLExporting) return;
            MLAutoCount++;
            [self record:@"orientation-settled"];
        });
    });
}
- (void)export:(UITapGestureRecognizer *)gesture {
    if (MLExporting) return;
    [self record:@"manual-export"];
    MLExporting = YES;
    NSDictionary *report = @{@"schema":@1, @"version":@"0.2.0~diagnostics1", @"mode":@"native-layout-diagnostics-only",
        @"privacy":@"Classes, geometry and constraints; no label text, lyric text, artwork, accounts or playback metadata.", @"snapshots":[MLSnapshots copy]};
    __weak UIWindow *sourceWindow = (UIWindow *)gesture.view;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        NSURL *folder = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *file = [folder URLByAppendingPathComponent:@"MusicLandscape-native-layout.json"];
        BOOL saved = data && [data writeToURL:file options:NSDataWritingAtomic error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!saved) { MLExporting = NO; NSLog(@"[MusicLandscape] Native report write failed: %@", error); return; }
            UIViewController *presenter = sourceWindow.rootViewController;
            while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) presenter = presenter.presentedViewController;
            if (!presenter.viewIfLoaded.window || presenter.isBeingDismissed) { MLExporting = NO; return; }
            UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
            share.popoverPresentationController.sourceView = presenter.view;
            share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
            share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *shareError) { MLExporting = NO; };
            [presenter presentViewController:share animated:YES completion:nil];
        });
    });
}
@end
%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Music"]) return;
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (major != 16 && major != 26) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            MLNativeDiagnostics *observer = MLNativeDiagnostics.shared;
            [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
            [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(active:) name:UIApplicationDidBecomeActiveNotification object:nil];
            [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(orientation:) name:UIDeviceOrientationDidChangeNotification object:nil];
            [observer active:nil];
        });
    }
}
