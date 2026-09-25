#import "MPPortController.h"
#import "MPHierarchyProbe.h"
#import "MPLandscapeHost.h"
#import "MPLog.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach/mach.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import <unistd.h>

static NSString *const MPDomain = @"com.justintunsday.musicport";
static NSDictionary *MPFilePrefs;

@interface MPPortController ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastLayoutDump;
@property (nonatomic, assign) BOOL flagProbed;
- (BOOL)isTargetClass:(Class)cls;
- (UIViewController *)targetViewController;
- (void)registerObservers;
- (void)handleActivation;
- (void)probeEnhancedLandscapeFlag;
- (void)logEnvironment;
@end

static id MPPref(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)MPDomain);
    if (value) return (__bridge_transfer id)value;
    return MPFilePrefs[key];
}

static void MPRefreshPreferences(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)MPDomain);
    MPFilePrefs = nil;
    NSArray<NSString *> *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.justintunsday.musicport.plist",
        @"/var/mobile/Library/Preferences/com.justintunsday.musicport.plist",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.justintunsday.musicport.plist"],
    ];
    for (NSString *path in paths) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (prefs) {
            MPFilePrefs = prefs;
            break;
        }
    }
}

static BOOL MPPrefBool(NSString *key, BOOL fallback) {
    id v = MPPref(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

static NSString *MPPrefString(NSString *key, NSString *fallback) {
    id v = MPPref(key);
    return [v isKindOfClass:NSString.class] ? v : fallback;
}

static NSArray *MPPrefArray(NSString *key, NSArray *fallback) {
    id v = MPPref(key);
    return [v isKindOfClass:NSArray.class] ? v : fallback;
}

static NSString *MPDeviceModel(void) {
    struct utsname u;
    uname(&u);
    return [NSString stringWithUTF8String:u.machine];
}

static UIInterfaceOrientation MPCurrentOrientation(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState == UISceneActivationStateForegroundActive) return ws.interfaceOrientation;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
}

static UIWindow *MPKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
}

static UIViewController *MPFindTarget(UIViewController *vc, MPPortController *controller) {
    if (!vc) return nil;
    UIViewController *found = MPFindTarget(vc.presentedViewController, controller);
    if (found) return found;
    for (UIViewController *child in vc.childViewControllers.reverseObjectEnumerator) {
        found = MPFindTarget(child, controller);
        if (found) return found;
    }
    return vc.viewIfLoaded.window && [controller isTargetClass:vc.class] ? vc : nil;
}

static BOOL MPIsPointerInDataSection(const void *sym, const void *imageHeader) {
    uintptr_t addr = (uintptr_t)sym;
    const char *segments[] = { "__DATA", "__DATA_CONST", "__DATA_DIRTY" };
    const char *sections[] = { "__data", "__bss", "__common", "__const", "__data_dirty", "__objc_data" };
    for (size_t s = 0; s < sizeof(segments) / sizeof(segments[0]); s++) {
        for (size_t i = 0; i < sizeof(sections) / sizeof(sections[0]); i++) {
            unsigned long size = 0;
            const void *data = getsectiondata((const struct mach_header_64 *)imageHeader, segments[s], sections[i], &size);
            uintptr_t start = (uintptr_t)data;
            if (data && addr >= start && addr < start + size) return YES;
        }
    }
    return NO;
}

static void MPReloadCallback(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [MPPortController.sharedController loadPreferences];
    });
}

@implementation MPPortController

+ (instancetype)sharedController {
    static MPPortController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [MPPortController new]; });
    return controller;
}

+ (void)start {
    MPPortController *c = [self sharedController];
    [c loadPreferences];
    [c registerObservers];
    [c logEnvironment];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [c probeEnhancedLandscapeFlag];
        [MPHierarchyProbe logMediaClassInventory];
    });
    MPLog(@"log file: %@", MPLogFilePath());
}

- (void)logEnvironment {
    MPLog(@"MusicPort 0.1.0 pid=%d bundle=%@ os=%@ device=%@",
          getpid(),
          NSBundle.mainBundle.bundleIdentifier ?: @"?",
          NSProcessInfo.processInfo.operatingSystemVersionString,
          MPDeviceModel());
}

- (void)loadPreferences {
    [MPLandscapeHost revertAll];
    MPRefreshPreferences();
    self.enabled = MPPrefBool(@"enabled", YES);
    self.instrumentationEnabled = MPPrefBool(@"instrumentation", YES);
    self.showHierarchy = MPPrefBool(@"showHierarchy", YES);
    self.landscapeLayoutEnabled = MPPrefBool(@"landscapeLayout", NO);
    self.autoRevertInPortrait = MPPrefBool(@"autoRevertInPortrait", YES);
    self.forceEnhancedLandscape = MPPrefBool(@"forceEnhancedLandscape", NO);
    self.logToFile = MPPrefBool(@"logToFile", YES);
    self.targetClassNames = MPPrefArray(@"targetClassNames", @[]);
    self.targetClassPrefixes = MPPrefArray(@"targetClassPrefixes", @[@"MediaCoreUI."]);
    self.targetClassKeywords = MPPrefArray(@"targetClassKeywords", @[@"NowPlaying", @"FullScreen"]);
    id layout = MPPref(@"layout");
    self.layoutConfig = [layout isKindOfClass:NSDictionary.class] ? layout : @{};
    if (!self.lastLayoutDump) self.lastLayoutDump = [NSMutableDictionary dictionary];

    MPLogSetFileEnabled(self.logToFile);
    MPLogSetLogPath(MPPrefString(@"logPath", nil));

    MPLog(@"prefs enabled=%d instrumentation=%d hierarchy=%d landscapeLayout=%d autoRevert=%d forceFlag=%d",
          self.enabled, self.instrumentationEnabled, self.showHierarchy,
          self.landscapeLayoutEnabled, self.autoRevertInPortrait, self.forceEnhancedLandscape);
    if (self.enabled && self.landscapeLayoutEnabled) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleOrientationEvent]; });
    }
}

- (void)registerObservers {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(handleOrientationEvent) name:UIDeviceOrientationDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(handleActivation) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(handleActivation) name:UIWindowDidBecomeKeyNotification object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    MPReloadCallback,
                                    CFSTR("com.justintunsday.musicport.reload"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (BOOL)isTargetClass:(Class)cls {
    if (!cls) return NO;
    NSString *name = NSStringFromClass(cls);
    for (NSString *exact in self.targetClassNames) {
        if ([name isEqualToString:exact]) return YES;
    }
    if (self.targetClassNames.count) return NO;
    BOOL prefixOK = NO;
    for (NSString *prefix in self.targetClassPrefixes) {
        if ([name hasPrefix:prefix]) {
            prefixOK = YES;
            break;
        }
    }
    if (!prefixOK) return NO;
    if (!self.targetClassKeywords.count) return YES;
    for (NSString *kw in self.targetClassKeywords) {
        if ([name rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

- (UIViewController *)targetViewController {
    UIWindow *window = MPKeyWindow();
    return MPFindTarget(window.rootViewController, self);
}

- (void)handleViewControllerLayout:(UIViewController *)vc {
    if (!self.enabled || !vc) return;
    if (![self isTargetClass:vc.class]) return;
    if (!self.instrumentationEnabled && !self.landscapeLayoutEnabled) return;
    if (!vc.viewIfLoaded.window) return;

    UIInterfaceOrientation orientation = MPCurrentOrientation();
    if (self.landscapeLayoutEnabled) {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            [MPLandscapeHost applyToViewController:vc];
        } else if (self.autoRevertInPortrait) {
            [MPLandscapeHost revertForViewController:vc];
        }
    }
    if (!self.instrumentationEnabled) return;

    NSString *cls = NSStringFromClass(vc.class);
    NSString *key = [NSString stringWithFormat:@"%@-%ld", cls, (long)orientation];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval last = [self.lastLayoutDump[key] doubleValue];
    if (now - last < 4.0) return;
    self.lastLayoutDump[key] = @(now);

    MPLog(@"layout %@ orientation=%ld bounds=%@ traits=%@",
          cls, (long)orientation, NSStringFromCGRect(vc.view.bounds), vc.traitCollection);
    if (self.showHierarchy) {
        [MPHierarchyProbe logHierarchyForWindow:vc.view.window reason:key];
    }
}

- (void)handleViewControllerDisappear:(UIViewController *)vc {
    if ([MPLandscapeHost isAppliedToViewController:vc]) {
        [MPLandscapeHost revertForViewController:vc];
    }
}

- (void)handleTransitionForViewController:(UIViewController *)vc
                                   toSize:(CGSize)size
                              coordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    if (!self.enabled || ![self isTargetClass:vc.class]) return;
    MPLog(@"transition %@ size=%@", NSStringFromClass(vc.class), NSStringFromCGSize(size));
    if (coordinator) {
        [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self handleViewControllerLayout:vc];
            });
        }];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self handleViewControllerLayout:vc];
        });
    }
}

- (void)handleOrientationEvent {
    if (!self.enabled) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIInterfaceOrientation orientation = MPCurrentOrientation();
        MPLog(@"orientation=%ld landscape=%d", (long)orientation, UIInterfaceOrientationIsLandscape(orientation));
        UIViewController *target = [self targetViewController];
        if (target) {
            [self handleViewControllerLayout:target];
        } else if (self.instrumentationEnabled) {
            UIWindow *window = MPKeyWindow();
            if (window) [MPHierarchyProbe logHierarchyForWindow:window reason:@"orientation-no-target"];
        }
    });
}

- (void)handleActivation {
    if (!self.enabled) return;
    if (!self.flagProbed) [self probeEnhancedLandscapeFlag];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self handleOrientationEvent];
    });
}

- (void)probeEnhancedLandscapeFlag {
    if (self.flagProbed) return;
    self.flagProbed = YES;

    const char *name = "__UIEnhancedLandscapeEnabled";
    void *sym = dlsym(RTLD_DEFAULT, name);
    if (!sym) {
        MPLog(@"%s: symbol not exported by any loaded image", name);
        return;
    }
    Dl_info info = {0};
    dladdr(sym, &info);
    NSString *image = info.dli_fname ? [NSString stringWithUTF8String:info.dli_fname] : @"?";
    BOOL inData = MPIsPointerInDataSection(sym, info.dli_fbase);
    MPLog(@"%s symbol=%p image=%@ dataSection=%d", name, sym, image, inData);
    if (!inData) {
        MPLog(@"%s: not a data symbol; refusing to poke", name);
        return;
    }
    uint8_t value = *(uint8_t *)sym;
    MPLog(@"%s current value=%d", name, value);
    if (value == 0 && self.forceEnhancedLandscape) {
        vm_address_t page = (vm_address_t)sym & ~(vm_address_t)(vm_page_size - 1);
        kern_return_t kr = vm_protect(mach_task_self(), page, vm_page_size, FALSE,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (kr == KERN_SUCCESS) {
            *(uint8_t *)sym = 1;
            MPLog(@"forced %s -> 1", name);
        } else {
            MPLog(@"vm_protect failed for %s: %d", name, kr);
        }
    }
}

@end
