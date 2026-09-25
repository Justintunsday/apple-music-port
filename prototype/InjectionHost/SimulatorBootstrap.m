#import <UIKit/UIKit.h>
#import "../../tweak/MPLandscapeHost.h"
#import "../../tweak/MPPortController.h"
#import "../../tweak/MPHierarchyProbe.h"

static void MPWriteResult(NSString *result) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MusicPortSimulator.result"];
    [result writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static void MPCheckHost(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) window = candidate;
        }
    }
    if (!window) window = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = window.rootViewController;
    if (![NSStringFromClass(vc.class) isEqualToString:@"MPTestViewController"]) {
        MPWriteResult(@"FAIL: injection host controller was not found");
        return;
    }

    UIView *container = vc.view;
    UIView *artwork = [MPHierarchyProbe findViewIn:container matchingClassNames:@[@"MPTestArtworkView"] index:0];
    UIView *details = [MPHierarchyProbe findViewIn:container matchingClassNames:@[@"MPTestDetailsView"] index:0];
    if (!artwork || !details) {
        MPWriteResult(@"FAIL: test views were not found");
        return;
    }

    NSArray<UIView *> *originalOrder = [container.subviews copy];
    NSArray<NSLayoutConstraint *> *originalConstraints = [container.constraints copy];
    MPPortController.sharedController.layoutConfig = @{
        @"artworkClass": @"MPTestArtworkView",
        @"detailsClass": @"MPTestDetailsView",
    };

    if (![MPLandscapeHost applyToViewController:vc] ||
        ![MPLandscapeHost isAppliedToViewController:vc] ||
        artwork.superview == container || details.superview != artwork.superview) {
        MPWriteResult(@"FAIL: landscape host was not applied");
        return;
    }
    [container layoutIfNeeded];
    if (CGRectGetMaxX(artwork.frame) >= CGRectGetMinX(details.frame)) {
        MPWriteResult(@"FAIL: artwork and details did not become columns");
        return;
    }

    [MPLandscapeHost revertForViewController:vc];
    if ([MPLandscapeHost isAppliedToViewController:vc] ||
        artwork.superview != container || details.superview != container ||
        ![container.subviews isEqualToArray:originalOrder]) {
        MPWriteResult(@"FAIL: original view hierarchy was not restored");
        return;
    }
    for (NSLayoutConstraint *constraint in originalConstraints) {
        if (!constraint.isActive) {
            MPWriteResult(@"FAIL: original constraints were not restored");
            return;
        }
    }

    if (![MPLandscapeHost applyToViewController:vc]) {
        MPWriteResult(@"FAIL: host could not be reapplied");
        return;
    }
    MPWriteResult(@"PASS: injected, applied, reverted and reapplied landscape layout");
}

__attribute__((constructor)) static void MPBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                    object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ MPCheckHost(); });
        }];
    });
}
