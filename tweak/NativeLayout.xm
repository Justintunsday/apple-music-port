#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import "NativePolicy.h"

// Reuse Apple's existing regularExtended/splitView player. No new player,
// artwork copy, playback IPC, view reparenting or synthetic lyric rendering.
static __weak UIViewController *MLActivePlayer;
static double *MLWidthThreshold;
static MLWidthState MLWidth = {1024, false};
static BOOL MLRotationQueued;
static char MLTraitCacheKey;

static BOOL MLInNativePlayer(UIViewController *controller) {
    if (!MLWidthThreshold || !MLActivePlayer) return NO;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController)
        if (parent == MLActivePlayer) return YES;
    return NO;
}
static BOOL MLLandscape(UIViewController *controller) {
    CGSize size = controller.viewIfLoaded.window.bounds.size;
    return size.width > size.height && size.height >= 240;
}
static void MLRestoreThreshold(void) {
    MLRestoreWidth(MLWidthThreshold, &MLWidth);
}
static BOOL MLPrepareThreshold(UIViewController *controller) {
    if (!MLInNativePlayer(controller) || !MLLandscape(controller)) { MLRestoreThreshold(); return NO; }
    // 0 means Swift's once initializer has not run. Never overwrite uninitialized
    // data or a value owned by another tweak. The first native layout initializes it.
    CGSize size = controller.viewIfLoaded.window.bounds.size;
    return MLApplyWidth(MLWidthThreshold, &MLWidth, size.width, size.height);
}

static UITraitCollection *MLNativeTraits(UIViewController *controller, UITraitCollection *original) {
    if (!original || !MLInNativePlayer(controller) || !MLLandscape(controller)) return original;
    // The disassembled iOS 16 classifier explicitly requires pad + regular.
    // Limit the trait override to these native player controllers, not UIDevice,
    // the application, library/browser screens or arbitrary UIView subclasses.
    NSArray *cached = objc_getAssociatedObject(controller, &MLTraitCacheKey);
    if (cached.count == 2 && cached[0] == original) return cached[1];
    UITraitCollection *traits = [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        original, [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPad],
        [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassRegular]]];
    objc_setAssociatedObject(controller, &MLTraitCacheKey, @[original, traits], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return traits;
}

static void MLRequestRotation(BOOL leaving) {
    if (MLRotationQueued) return;
    MLRotationQueued = YES;
    __weak UIWindow *lastWindow = MLActivePlayer.viewIfLoaded.window;
    dispatch_async(dispatch_get_main_queue(), ^{
        MLRotationQueued = NO;
        UIWindow *window = MLActivePlayer.viewIfLoaded.window ?: lastWindow;
        if (!window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        UIInterfaceOrientationMask mask = UIInterfaceOrientationMaskPortrait;
        if (!leaving && MLActivePlayer) {
            switch (UIDevice.currentDevice.orientation) {
                case UIDeviceOrientationLandscapeLeft: mask = UIInterfaceOrientationMaskLandscapeRight; break;
                case UIDeviceOrientationLandscapeRight: mask = UIInterfaceOrientationMaskLandscapeLeft; break;
                case UIDeviceOrientationPortrait: mask = UIInterfaceOrientationMaskPortrait; break;
                default: return;
            }
        }
        [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        [MLActivePlayer setNeedsUpdateOfSupportedInterfaceOrientations];
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [window.windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            NSLog(@"[MusicLandscape Native] Rotation request rejected: %@", error.localizedDescription);
        }];
    });
}

@interface MLLegacyPlayer : UIViewController @end
@interface MLLegacyControls : UIViewController @end
@interface MLLegacyLyrics : UIViewController @end

%group LegacyNative
%hook UIApplication
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    UIInterfaceOrientationMask original = %orig;
    if (MLWidthThreshold && MLActivePlayer && MLActivePlayer.viewIfLoaded.window == window)
        return UIInterfaceOrientationMaskAllButUpsideDown;
    return original;
}
%end
%hook MLLegacyPlayer
- (void)viewWillAppear:(BOOL)animated {
    if (MLWidthThreshold) MLActivePlayer = self;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (MLWidthThreshold) { MLActivePlayer = self; MLRequestRotation(NO); }
}
- (UITraitCollection *)traitCollection {
    UITraitCollection *original = %orig;
    return MLNativeTraits(self, original);
}
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    UIInterfaceOrientationMask original = %orig;
    return MLInNativePlayer(self) ? UIInterfaceOrientationMaskAllButUpsideDown : original;
}
- (BOOL)shouldAutorotate {
    BOOL original = %orig;
    return MLInNativePlayer(self) ? YES : original;
}
- (void)viewDidLayoutSubviews {
    if (MLInNativePlayer(self)) MLPrepareThreshold(self);
    %orig;
    // First layout may have initialized the native 1024 constant. Request just
    // one follow-up pass when its value actually changes, never unconditionally.
    if (MLInNativePlayer(self) && MLPrepareThreshold(self)) [[(UIViewController *)self view] setNeedsLayout];
}
- (void)viewWillDisappear:(BOOL)animated {
    if (self == MLActivePlayer) {
        MLRestoreThreshold();
        MLRequestRotation(YES);
        MLActivePlayer = nil;
    }
    %orig;
}
%end
%hook MLLegacyControls
- (UITraitCollection *)traitCollection {
    UITraitCollection *original = %orig;
    return MLNativeTraits(self, original);
}
%end
%hook MLLegacyLyrics
- (UITraitCollection *)traitCollection {
    UITraitCollection *original = %orig;
    return MLNativeTraits(self, original);
}
%end
%end

static double *MLFindWidthThreshold(void) {
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const char *name = _dyld_get_image_name(index);
        if (!name || ![[NSString stringWithUTF8String:name] hasSuffix:@"/MusicApplication.framework/MusicApplication"]) continue;
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(index);
        size_t size = sizeof(*header) + header->sizeofcmds;
        if (size > 128 * 1024 || !MLValidateImage(header, size)) return NULL;
        return (double *)(ML_WIDTH_VADDR + _dyld_get_image_vmaddr_slide(index));
    }
    return NULL;
}

static void MLInstallNative(void) {
            static BOOL installed;
            if (installed || !UIApplication.sharedApplication.delegate) return;
            installed = YES;
            MLWidthThreshold = MLFindWidthThreshold();
            Class player = NSClassFromString(@"MusicApplication.NowPlayingViewController") ?: NSClassFromString(@"_TtC16MusicApplication24NowPlayingViewController");
            Class controls = NSClassFromString(@"MusicNowPlayingControlsViewController");
            Class lyrics = NSClassFromString(@"MusicNowPlayingLyricsViewController");
            if (!MLWidthThreshold || !player || !controls || !lyrics) {
                MLWidthThreshold = NULL;
                NSLog(@"[MusicLandscape Native] Framework identity or native classes do not match; native layout unchanged.");
                return;
            }
            %init(LegacyNative, MLLegacyPlayer=player, MLLegacyControls=controls, MLLegacyLyrics=lyrics);
            [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
            [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { if (MLActivePlayer) MLRequestRotation(NO); }];
            NSLog(@"[MusicLandscape Native] Verified 20B101 MusicApplication; native extended player enabled.");
}
%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Music"] ||
            ![UIDevice.currentDevice.systemVersion isEqualToString:@"16.1.1"]) return;
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { MLInstallNative(); }];
        dispatch_async(dispatch_get_main_queue(), ^{
            MLInstallNative();
        });
    }
}
