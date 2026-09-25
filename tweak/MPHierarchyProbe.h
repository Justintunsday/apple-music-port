#import <UIKit/UIKit.h>

@interface MPViewCandidate : NSObject
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) CGFloat areaRatio;
@property (nonatomic, assign) NSInteger depth;
@property (nonatomic, assign) NSInteger subviewCount;
@property (nonatomic, assign) BOOL hasLayerContents;
@property (nonatomic, assign) BOOL hosting;
@property (nonatomic, assign) NSInteger textLayerCount;
@property (nonatomic, assign) CGFloat squareness;
@property (nonatomic, weak) UIView *view;
@end

@interface MPHierarchyProbe : NSObject
+ (void)logMediaClassInventory;
+ (void)logHierarchyForWindow:(UIWindow *)window reason:(NSString *)reason;
+ (NSArray<MPViewCandidate *> *)candidatesInWindow:(UIWindow *)window;
+ (UIView *)bestArtworkViewInWindow:(UIWindow *)window;
+ (UIView *)bestDetailsViewInWindow:(UIWindow *)window avoiding:(UIView *)artwork;
+ (UIView *)findViewIn:(UIView *)root matchingClassNames:(NSArray<NSString *> *)names index:(NSUInteger)index;
@end
