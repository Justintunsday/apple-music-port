#import <objc/runtime.h>
#import <stdatomic.h>
#import "PlayerUnderTest.m"

static atomic_int queries, commands, seeks, mode;
static NSInteger layouts, beats;
static UIDeviceOrientation testOrientation = UIDeviceOrientationLandscapeLeft;
static NSMutableArray<NSString *> *failures;

static void check(BOOL condition, NSString *message) {
    if (!condition) [failures addObject:message];
}
static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}
static void mockInfo(dispatch_queue_t queue, void (^completion)(CFDictionaryRef)) {
    NSCAssert(!NSThread.isMainThread, @"Media IPC ran on main thread");
    atomic_fetch_add(&queries, 1);
    double delay = atomic_load(&mode) == 0 ? 4.0 : 0.05;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, ^{
        NSDictionary *info = @{@"kMRMediaRemoteNowPlayingInfoTitle": @"Smoke track",
            @"kMRMediaRemoteNowPlayingInfoArtist": @"Test artist",
            @"kMRMediaRemoteNowPlayingInfoDuration": @180,
            @"kMRMediaRemoteNowPlayingInfoElapsedTime": @30,
            @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @1};
        completion((__bridge CFDictionaryRef)info);
    });
}
static Boolean mockSend(int command, NSDictionary *options) {
    NSCAssert(!NSThread.isMainThread, @"Command ran on main thread");
    atomic_fetch_add(&commands, 1);
    return true;
}
static void mockSeek(double position) {
    NSCAssert(!NSThread.isMainThread, @"Seek ran on main thread");
    atomic_fetch_add(&seeks, 1);
}

@interface SmokeNowPlayingController : UIViewController
@end
@implementation SmokeNowPlayingController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; layouts++; }
@end

@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) NSTimer *heartbeat;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [SmokeNowPlayingController new];
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application {
    static BOOL started;
    if (started) return;
    started = YES;
    after(0.2, ^{ [self runChecks]; });
}
- (void)runChecks {
    failures = [NSMutableArray new];
    Method orientation = class_getInstanceMethod(UIDevice.class, @selector(orientation));
    method_setImplementation(orientation, imp_implementationWithBlock(^UIDeviceOrientation(UIDevice *device) { return testOrientation; }));
    MLGetInfo = mockInfo;
    MLSend = mockSend;
    MLSeek = mockSeek;
    MLNativeController = self.window.rootViewController;
    check(MLIsPlayer(MLNativeController), @"Player detection failed");
    self.heartbeat = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { beats++; }];
    for (int i = 0; i < 100; i++) MLRequestUpdate();
    after(3.4, ^{
        check(MLPanel.superview == self.window, @"Overlay must be hosted outside native layout");
        check(atomic_load(&queries) == 1, @"Slow request was repeatedly enqueued");
        check(beats > 30, @"Main run loop stalled during media request");
        check(layouts < 20, @"Native layout kept reentering");
        check([MLPanel.artistLabel.text containsString:@"unavailable"], @"Timeout did not show fallback");
        MLLandscape *oldPanel = MLPanel;
        [MLPanel close];
        check(!MLPanel && !oldPanel.superview, @"Close failed while request was outstanding");
        after(1.0, ^{
            check(!MLPanel, @"Late callback recreated dismissed overlay");
            atomic_store(&mode, 1);
            MLSuppressed = NO;
            MLUpdate();
            after(0.3, ^{
                check([MLPanel.titleLabel.text isEqualToString:@"Smoke track"], @"Async metadata was not applied");
                check(MLPanel.playButton.enabled, @"Playback controls remained disabled");
                [MLPanel togglePlayback];
                after(0.2, ^{
                    [MLPanel seek];
                    after(0.2, ^{
                        check(atomic_load(&commands) == 1 && atomic_load(&seeks) == 1, @"Async controls failed");
                        testOrientation = UIDeviceOrientationLandscapeRight;
                        MLUpdate();
                        testOrientation = UIDeviceOrientationPortrait;
                        MLUpdate();
                        check(!MLPanel, @"Portrait did not restore native UI");
                        check(beats > 60, @"Main run loop stopped responding");
                        [self.heartbeat invalidate];
                        NSString *result = failures.count ? [@"FAIL\n" stringByAppendingString:[failures componentsJoinedByString:@"\n"]] : @"PASS\n";
                        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"smoke-result.txt"];
                        [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    });
                });
            });
        });
    });
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SmokeDelegate.class)); }
}
