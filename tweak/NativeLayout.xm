#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import "NativePolicy.h"

// Adapt Apple's existing phone player to compact landscape. No new player,
// artwork copy, playback IPC, view reparenting or synthetic lyric rendering.
static __weak UIViewController *MLActivePlayer;
static double *MLWidthThreshold;
static BOOL MLRotationQueued;
static char MLTraitCacheKey;
static char MLOriginalLyricFontKey;
static NSHashTable<UILabel *> *MLChangedLyricLabels;
static __weak UIView *MLMeasuringLyricLine;

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
static UITraitCollection *MLPhoneTraits(UIViewController *controller, UITraitCollection *original) {
    if (!original || !MLInNativePlayer(controller) || !MLLandscape(controller)) return original;
    // Keep phone metrics throughout; the compact adapter supplies column geometry
    // without entering the tablet's regularExtended/splitView layout.
    NSArray *cached = objc_getAssociatedObject(controller, &MLTraitCacheKey);
    if (cached.count == 2 && cached[0] == original) return cached[1];
    UITraitCollection *traits = [UITraitCollection traitCollectionWithTraitsFromCollections:@[
        original, [UITraitCollection traitCollectionWithUserInterfaceIdiom:UIUserInterfaceIdiomPhone],
        [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact],
        [UITraitCollection traitCollectionWithVerticalSizeClass:UIUserInterfaceSizeClassCompact]]];
    objc_setAssociatedObject(controller, &MLTraitCacheKey, @[original, traits], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return traits;
}

static BOOL MLCompactLyricLabel(UILabel *label) {
    if (!MLWidthThreshold || !MLActivePlayer || !MLLandscape(MLActivePlayer) ||
        (label.window != MLActivePlayer.viewIfLoaded.window && !MLMeasuringLyricLine)) return NO;
    for (UIView *view = label.superview; view; view = view.superview) {
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"SyncedLyricsLineView"] || [name containsString:@"StaticLyrics"])
            return view == MLMeasuringLyricLine || [label isDescendantOfView:MLActivePlayer.viewIfLoaded];
    }
    return NO;
}

static CGFloat MLMaxLyricFontSize(void) {
    CGSize size = MLActivePlayer.viewIfLoaded.window.bounds.size;
    CGFloat maximum = 26;
    if (size.width > size.height && isfinite(size.height) && size.height > 0)
        maximum = fmax(18, fmin(26, size.height * .06));
    return maximum;
}
static UIFont *MLLyricFont(UILabel *label, UIFont *font) {
    if (!font || !MLCompactLyricLabel(label)) return font;
    if (!objc_getAssociatedObject(label, &MLOriginalLyricFontKey))
        objc_setAssociatedObject(label, &MLOriginalLyricFontKey, font, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!MLChangedLyricLabels) MLChangedLyricLabels = [NSHashTable weakObjectsHashTable];
    [MLChangedLyricLabels addObject:label];
    CGFloat maximum = MLMaxLyricFontSize();
    return font.pointSize > maximum ? [font fontWithSize:maximum] : font;
}

static void MLUpdateLyricLabels(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        UIFont *font = MLLyricFont(label, label.font);
        if (![font isEqual:label.font]) label.font = font;
    }
    for (UIView *child in view.subviews) MLUpdateLyricLabels(child);
}

static void MLRestoreLyricFonts(void) {
    for (UILabel *label in MLChangedLyricLabels.allObjects) {
        UIFont *font = objc_getAssociatedObject(label, &MLOriginalLyricFontKey);
        objc_setAssociatedObject(label, &MLOriginalLyricFontKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (font) label.font = font;
    }
    [MLChangedLyricLabels removeAllObjects];
}

#import "CompactLayout.h"

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
@interface MLLegacyLyricLine : UIControl @end

%group LegacyNative
%hook UILabel
- (void)setFont:(UIFont *)font {
    UIFont *adjusted = MLLyricFont(self, font);
    %orig(adjusted);
}
%end
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
    return MLPhoneTraits(self, original);
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
    if (!MLLandscape(self)) { MLRestoreLyricFonts(); MLRestoreCompactTree(self); }
    %orig;
    MLUpdateHostedLayout(self);
}
- (void)viewWillDisappear:(BOOL)animated {
    if (self == MLActivePlayer) {
        MLRequestRotation(YES);
        MLActivePlayer = nil;
        MLRestoreLyricFonts();
        MLRestoreCompactTree(self);
    }
    %orig;
}
%end
%hook MLLegacyControls
- (void)setControlsHidden:(BOOL)hidden animator:(id)animator {
    BOOL adjusted = hidden;
    if (MLInNativePlayer(self) && MLLandscape(self) && MLHasHostedContent(MLActivePlayer)) adjusted = NO;
    %orig(adjusted, animator);
}
- (UITraitCollection *)traitCollection {
    UITraitCollection *original = %orig;
    return MLPhoneTraits(self, original);
}
- (void)viewDidLayoutSubviews {
    %orig;
    MLApplyCompact(self);
}
%end
%hook MLLegacyLyrics
- (UITraitCollection *)traitCollection {
    UITraitCollection *original = %orig;
    return MLPhoneTraits(self, original);
}
- (void)viewDidLayoutSubviews {
    MLUpdateLyricLabels([(UIViewController *)self view]);
    %orig;
}
%end
%hook MLLegacyLyricLine
- (CGSize)sizeThatFits:(CGSize)size {
    UIView *previous = MLMeasuringLyricLine;
    MLMeasuringLyricLine = self;
    MLUpdateLyricLabels(self);
    CGSize result = %orig;
    MLMeasuringLyricLine = previous;
    return result;
}
- (void)layoutSubviews {
    MLUpdateLyricLabels(self);
    %orig;
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
            Class line = NSClassFromString(@"_TtC16MusicApplication20SyncedLyricsLineView");
            if (!MLWidthThreshold || !player || !controls || !lyrics || !line) {
                MLWidthThreshold = NULL;
                NSLog(@"[MusicLandscape Native] Framework identity or native classes do not match; native layout unchanged.");
                return;
            }
            %init(LegacyNative, MLLegacyPlayer=player, MLLegacyControls=controls, MLLegacyLyrics=lyrics, MLLegacyLyricLine=line);
            [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
            [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { if (MLActivePlayer) MLRequestRotation(NO); }];
            NSLog(@"[MusicLandscape Native] Verified 20B101 MusicApplication; compact landscape adapter enabled.");
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
