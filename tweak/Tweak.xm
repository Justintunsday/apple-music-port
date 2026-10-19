#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <math.h>

// Resolve private entry points only on the worker queue. Missing APIs disable
// playback controls instead of falling back to synchronous systemMusicPlayer IPC.
typedef void (*MLGetInfoFunction)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*MLSendFunction)(int, NSDictionary *);
typedef void (*MLSeekFunction)(double);
static MLGetInfoFunction MLGetInfo;
static MLSendFunction MLSend;
static MLSeekFunction MLSeek;
static dispatch_queue_t MLMediaQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.justintunsday.musiclandscape.media", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static void MLLoadMediaRemote(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;
        MLGetInfo = (MLGetInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        MLSend = (MLSendFunction)dlsym(handle, "MRMediaRemoteSendCommand");
        MLSeek = (MLSeekFunction)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    });
}

// No private Swift symbols or layout offsets: the native controller remains intact.
@interface MLLandscape : UIView
@property(nonatomic, strong) UIImageView *artwork;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *artistLabel;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UISlider *progress;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UIStackView *details;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSData *lastArtworkData;
@property(nonatomic, copy) NSArray<UIButton *> *transportButtons;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) BOOL requestPending;
@property(nonatomic) BOOL commandPending;
@property(nonatomic) BOOL canSend;
@property(nonatomic) BOOL canSeek;
@property(nonatomic) NSUInteger requestNumber;
- (void)refresh;
@end

static __weak UIViewController *MLNativeController;
static __weak UIWindow *MLManualWindow;
static MLLandscape *MLPanel;
static BOOL MLSuppressed;
static void MLUpdate(void);
static void MLRequestUpdate(void) {
    static BOOL queued;
    if (queued) return;
    queued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ queued = NO; MLUpdate(); });
}

static UIButton *MLButton(NSString *symbol, NSString *label, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 12, 12, 12);
    button.configuration = configuration;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@implementation MLLandscape
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:1];
        self.accessibilityIdentifier = @"MusicLandscape.Player";
        _artwork = [UIImageView new];
        _artwork.contentMode = UIViewContentModeScaleAspectFit;
        _artwork.layer.cornerRadius = 16;
        _artwork.clipsToBounds = YES;
        [self addSubview:_artwork];
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.numberOfLines = 2;
        _artistLabel = [UILabel new];
        _artistLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
        _artistLabel.textColor = UIColor.secondaryLabelColor;
        _artistLabel.numberOfLines = 2;
        _progress = [UISlider new];
        _progress.accessibilityLabel = @"Playback position";
        _progress.tintColor = UIColor.whiteColor;
        [_progress addTarget:self action:@selector(seek) forControlEvents:UIControlEventValueChanged];
        _timeLabel = [UILabel new];
        _timeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        _timeLabel.textColor = UIColor.lightGrayColor;
        UIButton *previous = MLButton(@"backward.end.fill", @"Previous track", self, @selector(previous));
        _playButton = MLButton(@"play.fill", @"Play", self, @selector(togglePlayback));
        UIButton *next = MLButton(@"forward.end.fill", @"Next track", self, @selector(next));
        UIButton *close = MLButton(@"chevron.down", @"Return to native player", self, @selector(close));
        _transportButtons = @[previous, _playButton, next];
        for (UIButton *button in _transportButtons) button.enabled = NO;
        _progress.enabled = NO;
        _titleLabel.text = @"Apple Music";
        _artistLabel.text = @"Loading playback information…";
        _artwork.image = [UIImage systemImageNamed:@"music.note"];
        UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[previous, _playButton, next, close]];
        controls.distribution = UIStackViewDistributionFillEqually;
        [controls.heightAnchor constraintEqualToConstant:54].active = YES;
        _details = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _artistLabel, _progress, _timeLabel, controls]];
        _details.axis = UILayoutConstraintAxisVertical;
        _details.spacing = 12;
        [self addSubview:_details];
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat margin = MAX(24, MIN(52, h * 0.09));
    CGFloat side = MAX(0, MIN(h - margin * 2, w * 0.43));
    self.artwork.frame = CGRectMake(margin, (h - side) / 2, side, side);
    CGFloat x = CGRectGetMaxX(self.artwork.frame) + margin;
    CGFloat width = MAX(0, w - x - margin);
    CGSize size = [self.details systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
        withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.details.frame = CGRectMake(x, MAX(12, (h - size.height) / 2), width, size.height);
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.timer invalidate];
    self.timer = nil;
    if (self.window) {
        __weak MLLandscape *weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            MLUpdate();
            if (weakSelf.window) [weakSelf refresh];
        }];
        [self refresh];
    }
}
- (void)refresh {
    if (self.requestPending || !self.window) return;
    self.requestPending = YES;
    NSUInteger request = ++self.requestNumber;
    __weak MLLandscape *weakSelf = self;
    NSData *previousArtwork = self.lastArtworkData;
    // One outstanding request at most. A timed-out request is not retried every
    // second: a stalled service must not accumulate work or block the UI thread.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MLLandscape *panel = weakSelf;
        if (panel.requestPending && panel.requestNumber == request) {
            panel.artistLabel.text = @"Playback information unavailable. Close to use native player.";
            for (UIButton *button in panel.transportButtons) button.enabled = NO;
            panel.progress.enabled = NO;
        }
    });
    dispatch_async(MLMediaQueue(), ^{
        MLLoadMediaRemote();
        if (!MLGetInfo) return; // Timeout leaves the close button responsive.
        BOOL canSend = MLSend != NULL, canSeek = MLSeek != NULL;
        MLGetInfo(MLMediaQueue(), ^(CFDictionaryRef information) {
            NSDictionary *info = [(__bridge NSDictionary *)information copy] ?: @{};
            id rawArtwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            NSData *artworkData = [rawArtwork isKindOfClass:NSData.class] ? rawArtwork : nil;
            // Decode artwork away from the main thread; do not decode unchanged data.
            BOOL changedArtwork = ![artworkData isEqualToData:previousArtwork] && (artworkData || previousArtwork);
            UIImage *artwork = changedArtwork ? [UIImage imageWithData:artworkData] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                MLLandscape *panel = weakSelf;
                if (!panel || panel.requestNumber != request) return;
                panel.requestPending = NO;
                if (!panel.window) return;
                panel.canSend = canSend;
                panel.canSeek = canSeek;
                for (UIButton *button in panel.transportButtons) button.enabled = canSend && !panel.commandPending;
                id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                panel.titleLabel.text = [title isKindOfClass:NSString.class] ? title : @"Nothing Playing";
                panel.artistLabel.text = [artist isKindOfClass:NSString.class] ? artist : @"Apple Music";
                if (changedArtwork) {
                    panel.artwork.image = artwork ?: [UIImage systemImageNamed:@"music.note"];
                    panel.lastArtworkData = artworkData;
                }
                double (^number)(NSString *) = ^double(NSString *key) {
                    id value = info[key];
                    double result = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0;
                    return isfinite(result) ? result : 0;
                };
                double duration = MAX(0, MIN(604800, number(@"kMRMediaRemoteNowPlayingInfoDuration")));
                double rate = number(@"kMRMediaRemoteNowPlayingInfoPlaybackRate");
                double current = number(@"kMRMediaRemoteNowPlayingInfoElapsedTime");
                id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([timestamp isKindOfClass:NSDate.class]) current += MAX(0, -[timestamp timeIntervalSinceNow]) * rate;
                current = MAX(0, MIN(duration, current));
                panel.duration = duration;
                panel.progress.enabled = canSeek && duration > 0 && !panel.commandPending;
                if (!panel.progress.tracking) panel.progress.value = duration > 0 ? current / duration : 0;
                [panel.playButton setImage:[UIImage systemImageNamed:rate > 0 ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
                panel.playButton.accessibilityLabel = rate > 0 ? @"Pause" : @"Play";
                panel.timeLabel.text = [NSString stringWithFormat:@"%ld:%02ld / %ld:%02ld", (long)current / 60,
                    (long)current % 60, (long)duration / 60, (long)duration % 60];
                [panel setNeedsLayout];
            });
        });
    });
}
- (void)sendCommand:(int)command position:(double)position {
    if (self.commandPending || (command < 0 ? !self.canSeek : !self.canSend)) return;
    self.commandPending = YES;
    for (UIButton *button in self.transportButtons) button.enabled = NO;
    self.progress.enabled = NO;
    __weak MLLandscape *weakSelf = self;
    dispatch_async(MLMediaQueue(), ^{
        if (command < 0) { if (MLSeek) MLSeek(position); }
        else if (MLSend) MLSend(command, nil);
        dispatch_async(dispatch_get_main_queue(), ^{
            MLLandscape *panel = weakSelf;
            panel.commandPending = NO;
            for (UIButton *button in panel.transportButtons) button.enabled = panel.canSend;
            panel.progress.enabled = panel.canSeek && panel.duration > 0;
            [panel refresh];
        });
    });
}
- (void)seek { [self sendCommand:-1 position:self.progress.value * self.duration]; }
- (void)previous { [self sendCommand:5 position:0]; }
- (void)next { [self sendCommand:4 position:0]; }
- (void)togglePlayback { [self sendCommand:2 position:0]; }
- (void)close { MLSuppressed = YES; [self removeFromSuperview]; MLPanel = nil; }
@end

static BOOL MLIsPlayer(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class).lowercaseString;
    return [name containsString:@"nowplaying"] && [name containsString:@"controller"] &&
        ![name containsString:@"mini"] && ![name containsString:@"queue"] &&
        ![name containsString:@"background"] && ![name containsString:@"controls"];
}

static void MLUpdate(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (UIDeviceOrientationIsPortrait(orientation)) MLSuppressed = NO;
    UIWindow *window = MLManualWindow ?: MLNativeController.viewIfLoaded.window;
    UIView *host = window; // Never add/reorder views inside Music's layout hierarchy.
    BOOL landscape = UIDeviceOrientationIsLandscape(orientation);
    if (!landscape || !window || MLSuppressed || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [MLPanel removeFromSuperview];
        MLPanel = nil;
        return;
    }
    BOOL created = !MLPanel;
    if (created) MLPanel = [[MLLandscape alloc] initWithFrame:CGRectZero];
    if (MLPanel.superview != host) [host addSubview:MLPanel];
    static CGRect lastBounds;
    static UIDeviceOrientation lastOrientation;
    if (!created && CGRectEqualToRect(lastBounds, host.bounds) && lastOrientation == orientation) return;
    lastBounds = host.bounds;
    lastOrientation = orientation;
    // Music can lock its own UI to portrait; rotate only our overlay in that case.
    CGSize size = host.bounds.size;
    MLPanel.transform = CGAffineTransformIdentity;
    if (size.height > size.width) {
        MLPanel.bounds = CGRectMake(0, 0, size.height, size.width);
        MLPanel.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
        MLPanel.transform = CGAffineTransformMakeRotation(orientation == UIDeviceOrientationLandscapeLeft ? M_PI_2 : -M_PI_2);
    } else {
        MLPanel.frame = host.bounds;
    }
}

@interface MLObserver : NSObject
+ (instancetype)shared;
- (void)changed:(NSNotification *)note;
- (void)manual:(UITapGestureRecognizer *)gesture;
@end
@implementation MLObserver
+ (instancetype)shared { static MLObserver *observer; static dispatch_once_t once; dispatch_once(&once, ^{ observer = [MLObserver new]; }); return observer; }
- (void)changed:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([note.name isEqualToString:UIApplicationDidBecomeActiveNotification]) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (![scene isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (!window.isKeyWindow) continue;
                    BOOL installed = NO;
                    for (UIGestureRecognizer *gesture in window.gestureRecognizers)
                        if ([gesture.name isEqualToString:@"MusicLandscape.Manual"]) installed = YES;
                    if (!installed) {
                        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(manual:)];
                        tap.numberOfTouchesRequired = 3;
                        tap.numberOfTapsRequired = 2;
                        tap.name = @"MusicLandscape.Manual";
                        tap.cancelsTouchesInView = NO;
                        [window addGestureRecognizer:tap];
                    }
                }
            }
        }
        MLRequestUpdate();
    });
}
- (void)manual:(UITapGestureRecognizer *)gesture {
    if (MLPanel) { MLSuppressed = YES; MLManualWindow = nil; }
    else { MLSuppressed = NO; MLManualWindow = (UIWindow *)gesture.view; }
    MLRequestUpdate();
}
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (MLIsPlayer(self)) {
        MLNativeController = self;
        NSLog(@"[MusicLandscape] native player: %@, OS %@", NSStringFromClass(self.class), UIDevice.currentDevice.systemVersion);
        MLRequestUpdate();
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self == MLNativeController) { MLNativeController = nil; MLRequestUpdate(); }
}
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Music"]) return;
        NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
        if (major != 16 && major != 26) return;
        %init;
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
            MLObserver *observer = MLObserver.shared;
            for (NSString *name in @[UIDeviceOrientationDidChangeNotification, UIApplicationDidBecomeActiveNotification,
                                    UIApplicationWillResignActiveNotification])
                [NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(changed:) name:name object:nil];
            [observer changed:[NSNotification notificationWithName:UIApplicationDidBecomeActiveNotification object:nil]];
        });
    }
}
