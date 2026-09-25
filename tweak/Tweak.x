#import <UIKit/UIKit.h>
#import "MPPortController.h"

%hook UIViewController

- (void)viewDidLayoutSubviews {
    %orig;
    [[MPPortController sharedController] handleViewControllerLayout:self];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [[MPPortController sharedController] handleTransitionForViewController:self toSize:size coordinator:coordinator];
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[MPPortController sharedController] handleViewControllerDisappear:self];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[MPPortController sharedController] handleViewControllerLayout:self];
}

%end

%ctor {
    [MPPortController start];
}
