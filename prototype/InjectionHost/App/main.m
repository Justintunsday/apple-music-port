#import <UIKit/UIKit.h>

@interface MPTestArtworkView : UIView
@end
@implementation MPTestArtworkView
@end

@interface MPTestDetailsView : UIView
@end
@implementation MPTestDetailsView
@end

@interface MPTestViewController : UIViewController
@end

@implementation MPTestViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:1];

    UIView *background = [UIView new];
    background.backgroundColor = UIColor.clearColor;
    background.frame = self.view.bounds;
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:background];

    MPTestArtworkView *artwork = [MPTestArtworkView new];
    artwork.backgroundColor = [UIColor colorWithRed:0.92 green:0.71 blue:0.13 alpha:1];
    artwork.layer.cornerRadius = 20;
    artwork.accessibilityIdentifier = @"test-artwork";
    artwork.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:artwork];

    MPTestDetailsView *details = [MPTestDetailsView new];
    details.accessibilityIdentifier = @"test-details";
    details.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:details];

    UILabel *title = [UILabel new];
    title.text = @"MusicPort";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:35];
    title.frame = CGRectMake(0, 0, 300, 55);
    [details addSubview:title];

    UILabel *subtitle = [UILabel new];
    subtitle.text = @"Simulator injection test";
    subtitle.textColor = UIColor.whiteColor;
    subtitle.font = [UIFont systemFontOfSize:23];
    subtitle.frame = CGRectMake(0, 65, 340, 40);
    [details addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [artwork.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [artwork.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:40],
        [artwork.widthAnchor constraintEqualToConstant:260],
        [artwork.heightAnchor constraintEqualToConstant:260],
        [details.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [details.topAnchor constraintEqualToAnchor:artwork.bottomAnchor constant:20],
        [details.widthAnchor constraintEqualToConstant:340],
        [details.heightAnchor constraintEqualToConstant:120],
    ]];
}

@end

@interface MPTestAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation MPTestAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [MPTestViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(MPTestAppDelegate.class));
    }
}
