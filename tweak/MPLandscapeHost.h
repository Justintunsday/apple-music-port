#import <UIKit/UIKit.h>

@interface MPLandscapeHost : NSObject
+ (BOOL)applyToViewController:(UIViewController *)vc;
+ (void)revertForViewController:(UIViewController *)vc;
+ (void)revertAll;
+ (BOOL)isAppliedToViewController:(UIViewController *)vc;
@end
