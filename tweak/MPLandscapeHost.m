#import "MPLandscapeHost.h"
#import "MPHierarchyProbe.h"
#import "MPLog.h"
#import "MPPortController.h"

static NSString *const MPHostIdentifier = @"com.justintunsday.musicport.host";

@interface MPLandscapeHostView : UIView
@property (nonatomic, weak) UIView *artwork;
@property (nonatomic, weak) UIView *details;
@end

@implementation MPLandscapeHostView

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *artwork = self.artwork;
    UIView *details = self.details;
    if (!artwork || !details) return;

    CGRect b = self.bounds;
    CGFloat h = b.size.height;
    CGFloat w = b.size.width;
    CGFloat side = h * 0.78;
    CGFloat pad = h * 0.095;
    CGFloat spacing = h * 0.055;

    artwork.frame = CGRectMake(pad, (h - side) / 2.0, side, side);
    CGFloat x = pad + side + spacing;
    CGFloat detailsWidth = MAX(w - x - pad, 1);
    details.frame = CGRectMake(x, h * 0.08, detailsWidth, h * 0.84);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

@end

@interface MPLandscapeState : NSObject
@property (nonatomic, weak) UIView *container;
@property (nonatomic, weak) UIView *artwork;
@property (nonatomic, weak) UIView *details;
@property (nonatomic, weak) UIView *artworkSuperview;
@property (nonatomic, weak) UIView *detailsSuperview;
@property (nonatomic, assign) CGRect artworkFrame;
@property (nonatomic, assign) CGRect detailsFrame;
@property (nonatomic, assign) BOOL artworkAutoresizing;
@property (nonatomic, assign) BOOL detailsAutoresizing;
@property (nonatomic, assign) NSUInteger artworkIndex;
@property (nonatomic, assign) NSUInteger detailsIndex;
@property (nonatomic, copy) NSArray<NSLayoutConstraint *> *externalConstraints;
@property (nonatomic, strong) MPLandscapeHostView *host;
@end

@implementation MPLandscapeState
@end

@interface MPLandscapeHost ()
+ (void)revertState:(MPLandscapeState *)state;
@end

@implementation MPLandscapeHost

static NSMutableArray<MPLandscapeState *> *MPStates(void) {
    static NSMutableArray *states;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ states = [NSMutableArray array]; });
    return states;
}

+ (MPLandscapeState *)stateForContainer:(UIView *)container {
    for (MPLandscapeState *state in MPStates()) {
        if (state.container == container) return state;
    }
    return nil;
}

+ (UIView *)resolveViewForKey:(NSString *)key config:(NSDictionary *)cfg container:(UIView *)container {
    NSString *classKey = [key stringByAppendingString:@"Class"];
    NSString *indexKey = [key stringByAppendingString:@"Index"];
    id classValue = cfg[classKey];
    NSArray<NSString *> *patterns = nil;
    if ([classValue isKindOfClass:NSString.class]) {
        patterns = @[classValue];
    } else if ([classValue isKindOfClass:NSArray.class]) {
        patterns = classValue;
    }
    NSUInteger index = [cfg[indexKey] respondsToSelector:@selector(unsignedIntegerValue)]
        ? [cfg[indexKey] unsignedIntegerValue]
        : 0;

    if (patterns.count) {
        return [MPHierarchyProbe findViewIn:container matchingClassNames:patterns index:index];
    }

    UIWindow *window = container.window;
    if ([key isEqualToString:@"artwork"]) {
        return [MPHierarchyProbe bestArtworkViewInWindow:window];
    }
    return [MPHierarchyProbe bestDetailsViewInWindow:window
                                             avoiding:[MPHierarchyProbe bestArtworkViewInWindow:window]];
}

static NSArray<NSLayoutConstraint *> *MPExternalConstraints(UIView *view, UIView *container) {
    NSMutableOrderedSet<NSLayoutConstraint *> *constraints = [NSMutableOrderedSet orderedSet];
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        for (NSLayoutConstraint *constraint in ancestor.constraints) {
            if (constraint.firstItem == view || constraint.secondItem == view) {
                [constraints addObject:constraint];
            }
        }
        if (ancestor == container) break;
    }
    return constraints.array;
}

+ (BOOL)applyToViewController:(UIViewController *)vc {
    UIView *container = vc.viewIfLoaded;
    if (!container) return NO;

    MPLandscapeState *existing = [self stateForContainer:container];
    if (existing) {
        if (existing.host.superview == container &&
            existing.artwork.superview == existing.host &&
            existing.details.superview == existing.host) {
            [existing.host setNeedsLayout];
            return YES;
        }
        [self revertState:existing];
    }

    NSDictionary *cfg = MPPortController.sharedController.layoutConfig ?: @{};
    UIView *artwork = [self resolveViewForKey:@"artwork" config:cfg container:container];
    UIView *details = [self resolveViewForKey:@"details" config:cfg container:container];
    if (!artwork || !details || artwork == details) {
        MPLog(@"host: unresolved views (artwork=%@ details=%@)", artwork, details);
        return NO;
    }
    if ([artwork isDescendantOfView:details] || [details isDescendantOfView:artwork]) {
        MPLog(@"host: artwork/details are nested, refusing to re-parent");
        return NO;
    }
    if (artwork == container || details == container ||
        ![artwork isDescendantOfView:container] || ![details isDescendantOfView:container] ||
        !artwork.superview || !details.superview) {
        MPLog(@"host: selected views must be inside target controller's view");
        return NO;
    }

    MPLandscapeState *state = [MPLandscapeState new];
    state.container = container;
    state.artwork = artwork;
    state.details = details;
    state.artworkSuperview = artwork.superview;
    state.detailsSuperview = details.superview;
    state.artworkFrame = artwork.frame;
    state.detailsFrame = details.frame;
    state.artworkAutoresizing = artwork.translatesAutoresizingMaskIntoConstraints;
    state.detailsAutoresizing = details.translatesAutoresizingMaskIntoConstraints;
    state.artworkIndex = [artwork.superview.subviews indexOfObject:artwork];
    state.detailsIndex = [details.superview.subviews indexOfObject:details];
    NSMutableOrderedSet<NSLayoutConstraint *> *constraints = [NSMutableOrderedSet orderedSet];
    [constraints addObjectsFromArray:MPExternalConstraints(artwork, container)];
    [constraints addObjectsFromArray:MPExternalConstraints(details, container)];
    state.externalConstraints = constraints.array;

    MPLandscapeHostView *host = [MPLandscapeHostView new];
    host.accessibilityIdentifier = MPHostIdentifier;
    host.backgroundColor = UIColor.clearColor;
    host.frame = container.bounds;
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    host.artwork = artwork;
    host.details = details;
    [container addSubview:host];

    [NSLayoutConstraint deactivateConstraints:state.externalConstraints];
    [artwork removeFromSuperview];
    [details removeFromSuperview];
    artwork.translatesAutoresizingMaskIntoConstraints = YES;
    details.translatesAutoresizingMaskIntoConstraints = YES;
    [host addSubview:artwork];
    [host addSubview:details];
    state.host = host;
    [MPStates() addObject:state];
    [host setNeedsLayout];
    [host layoutIfNeeded];

    MPLog(@"host: applied to %@ artwork=%@ %@ details=%@ %@",
          NSStringFromClass(vc.class),
          NSStringFromClass(artwork.class), NSStringFromCGRect(artwork.frame),
          NSStringFromClass(details.class), NSStringFromCGRect(details.frame));
    return YES;
}

+ (void)revertState:(MPLandscapeState *)state {
    if (!state) return;
    BOOL restoreArtwork = state.artwork.superview == state.host && state.artworkSuperview != nil;
    BOOL restoreDetails = state.details.superview == state.host && state.detailsSuperview != nil;
    if (restoreArtwork) [state.artwork removeFromSuperview];
    if (restoreDetails) [state.details removeFromSuperview];
    [state.host removeFromSuperview];

    if (restoreArtwork) {
        [state.artworkSuperview insertSubview:state.artwork atIndex:MIN(state.artworkIndex, state.artworkSuperview.subviews.count)];
        state.artwork.frame = state.artworkFrame;
        state.artwork.translatesAutoresizingMaskIntoConstraints = state.artworkAutoresizing;
    }
    if (restoreDetails) {
        [state.detailsSuperview insertSubview:state.details atIndex:MIN(state.detailsIndex, state.detailsSuperview.subviews.count)];
        state.details.frame = state.detailsFrame;
        state.details.translatesAutoresizingMaskIntoConstraints = state.detailsAutoresizing;
    }
    if (restoreArtwork && restoreDetails) {
        [NSLayoutConstraint activateConstraints:state.externalConstraints];
    }

    [MPStates() removeObject:state];
    MPLog(@"host: reverted container %@", NSStringFromClass(state.container.class));
}

+ (void)revertForViewController:(UIViewController *)vc {
    [self revertState:[self stateForContainer:vc.viewIfLoaded]];
}

+ (void)revertAll {
    for (MPLandscapeState *state in [MPStates() copy]) {
        [self revertState:state];
    }
}

+ (BOOL)isAppliedToViewController:(UIViewController *)vc {
    return [self stateForContainer:vc.viewIfLoaded] != nil;
}

@end
