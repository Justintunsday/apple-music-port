#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

// No private Swift symbols or layout offsets: the native controller remains intact.
@interface MLLandscape : UIView
@property(nonatomic, strong) UIImageView *artwork;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *artistLabel;
@property(nonatomic, strong) UIButton *playButton;
@property(nonatomic, strong) UISlider *progress;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UIStackView *details;
@property(nonatomic, strong) MPMusicPlayerController *player;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) MPMediaItem *lastItem;
- (void)refresh;
@end

static __weak UIViewController *MLNativeController;
static __weak UIWindow *MLManualWindow;
static MLLandscape *MLPanel;
static BOOL MLSuppressed;
static void MLUpdate(void);

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
        _player = MPMusicPlayerController.systemMusicPlayer;
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
        UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[previous, _playButton, next, close]];
        controls.distribution = UIStackViewDistributionFillEqually;
        [controls.heightAnchor constraintEqualToConstant:54].active = YES;
        _details = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _artistLabel, _progress, _timeLabel, controls]];
        _details.axis = UILayoutConstraintAxisVertical;
        _details.spacing = 12;
        [self addSubview:_details];
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [self refresh];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat margin = MAX(24, MIN(52, h * 0.09));
    CGFloat side = MIN(h - margin * 2, w * 0.43);
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
            [weakSelf refresh];
        }];
        [self refresh];
    }
}
- (void)refresh {
    MPMediaItem *item = self.player.nowPlayingItem;
    self.titleLabel.text = item.title ?: @"Nothing Playing";
    self.artistLabel.text = item.artist ?: @"Apple Music";
    if (item != self.lastItem || !self.artwork.image) {
        self.artwork.image = [item.artwork imageWithSize:CGSizeMake(700, 700)] ?: [UIImage systemImageNamed:@"music.note"];
        self.lastItem = item;
    }
    BOOL playing = self.player.playbackState == MPMusicPlaybackStatePlaying;
    [self.playButton setImage:[UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = playing ? @"Pause" : @"Play";
    NSTimeInterval duration = item.playbackDuration;
    NSTimeInterval current = self.player.currentPlaybackTime;
    if (!isfinite(current) || current < 0) current = 0;
    self.progress.enabled = isfinite(duration) && duration > 0;
    if (!self.progress.tracking) self.progress.value = duration > 0 ? MIN(1, current / duration) : 0;
    self.timeLabel.text = [NSString stringWithFormat:@"%ld:%02ld / %ld:%02ld", (long)current / 60, (long)current % 60,
        (long)MAX(0, duration) / 60, (long)MAX(0, duration) % 60];
    [self setNeedsLayout];
}
- (void)seek { self.player.currentPlaybackTime = self.progress.value * self.player.nowPlayingItem.playbackDuration; }
- (void)previous { [self.player skipToPreviousItem]; [self refresh]; }
- (void)next { [self.player skipToNextItem]; [self refresh]; }
- (void)togglePlayback {
    if (self.player.playbackState == MPMusicPlaybackStatePlaying) [self.player pause];
    else [self.player play];
    [self refresh];
}
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
    UIView *host = MLManualWindow ?: MLNativeController.viewIfLoaded;
    UIWindow *window = host.window;
    BOOL landscape = UIDeviceOrientationIsLandscape(orientation);
    if (!landscape || !window || MLSuppressed || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        [MLPanel removeFromSuperview];
        MLPanel = nil;
        return;
    }
    if (!MLPanel) MLPanel = [[MLLandscape alloc] initWithFrame:CGRectZero];
    if (MLPanel.superview != host) [host addSubview:MLPanel];
    [host bringSubviewToFront:MLPanel];
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
        MLUpdate();
    });
}
- (void)manual:(UITapGestureRecognizer *)gesture {
    if (MLPanel) { MLSuppressed = YES; MLManualWindow = nil; }
    else { MLSuppressed = NO; MLManualWindow = (UIWindow *)gesture.view; }
    MLUpdate();
}
@end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (MLIsPlayer(self)) {
        MLNativeController = self;
        NSLog(@"[MusicLandscape] native player: %@, OS %@", NSStringFromClass(self.class), UIDevice.currentDevice.systemVersion);
        MLUpdate();
    }
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (self == MLNativeController) MLUpdate();
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self == MLNativeController) { MLNativeController = nil; MLUpdate(); }
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
