#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>

@interface MPPortController : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL instrumentationEnabled;
@property (nonatomic, assign) BOOL showHierarchy;
@property (nonatomic, assign) BOOL landscapeLayoutEnabled;
@property (nonatomic, assign) BOOL autoRevertInPortrait;
@property (nonatomic, assign) BOOL forceEnhancedLandscape;
@property (nonatomic, assign) BOOL logToFile;
@property (nonatomic, copy) NSArray<NSString *> *targetClassNames;
@property (nonatomic, copy) NSArray<NSString *> *targetClassPrefixes;
@property (nonatomic, copy) NSArray<NSString *> *targetClassKeywords;
@property (nonatomic, copy) NSDictionary *layoutConfig;

+ (instancetype)sharedController;
+ (void)start;

- (void)loadPreferences;
- (void)handleViewControllerLayout:(UIViewController *)vc;
- (void)handleViewControllerDisappear:(UIViewController *)vc;
- (void)handleTransitionForViewController:(UIViewController *)vc
                                   toSize:(CGSize)size
                              coordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
- (void)handleOrientationEvent;

@end
