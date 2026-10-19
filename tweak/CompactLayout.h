// Adapt Apple's existing iOS 16 views to the iOS 27 compact-landscape structure.
// Native target/action, artwork, scrubber, route picker and lyric renderer survive.
#import "CompactGeometry.h"
static char MLCompactStateKey;
@interface MLCompactState : NSObject
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *constraints;
@property(nonatomic, strong) NSMapTable<NSLayoutConstraint *, NSNumber *> *priorities;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *masks;
@property(nonatomic, strong) NSArray<UIView *> *targets;
@property(nonatomic, strong) NSArray<UIView *> *ancestors;
@end
@implementation MLCompactState
@end

static UIView *MLNativeView(id controller, const char *name) {
    Ivar ivar = class_getInstanceVariable([controller class], name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    id value = object_getIvar(controller, ivar);
    return [value isKindOfClass:UIView.class] ? value : nil;
}
static BOOL MLHasHostedContent(UIViewController *controller) {
    for (UIViewController *child in controller.childViewControllers) {
        UIView *view = child.viewIfLoaded;
        if (!view.superview || view.hidden || view.alpha <= .01) continue;
        BOOL hiddenAncestor = NO;
        for (UIView *parent = view.superview; parent && parent != MLActivePlayer.viewIfLoaded; parent = parent.superview)
            if (parent.hidden || parent.alpha <= .01) { hiddenAncestor = YES; break; }
        if (hiddenAncestor || !CGRectIntersectsRect([view convertRect:view.bounds toView:MLActivePlayer.viewIfLoaded],
                                                     MLActivePlayer.viewIfLoaded.bounds)) continue;
        NSString *name = NSStringFromClass(child.class);
        if ([name containsString:@"LyricsViewController"] || [name containsString:@"QueueViewController"]) return YES;
        if (MLHasHostedContent(child)) return YES;
    }
    return NO;
}
static void MLRestoreCompact(UIViewController *controller) {
    MLCompactState *state = objc_getAssociatedObject(controller, &MLCompactStateKey);
    if (!state) return;
    [NSLayoutConstraint deactivateConstraints:state.constraints];
    for (NSLayoutConstraint *constraint in state.priorities) {
        BOOL active = constraint.active;
        if (active) constraint.active = NO;
        constraint.priority = [state.priorities objectForKey:constraint].floatValue;
        if (active) constraint.active = YES;
    }
    for (UIView *view in state.masks) view.translatesAutoresizingMaskIntoConstraints = [state.masks objectForKey:view].boolValue;
    objc_setAssociatedObject(controller, &MLCompactStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void MLRestoreCompactTree(UIViewController *controller) {
    MLRestoreCompact(controller);
    for (UIViewController *child in controller.childViewControllers) MLRestoreCompactTree(child);
}
static NSArray<NSLayoutConstraint *> *MLPinRect(UIView *view, UIView *root, MLRect rect) {
    return @[[view.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:rect.x],
             [view.topAnchor constraintEqualToAnchor:root.topAnchor constant:rect.y],
             [view.widthAnchor constraintEqualToConstant:rect.width],
             [view.heightAnchor constraintEqualToConstant:rect.height]];
}
static void MLApplyCompact(UIViewController *controller) {
    UIView *root = controller.viewIfLoaded;
    MLCompactGeometry geometry;
    UIEdgeInsets safe = root.safeAreaInsets;
    if (!MLInNativePlayer(controller) || !MLLandscape(controller) || MLHasHostedContent(MLActivePlayer) ||
        !MLMakeCompactGeometry(root.bounds.size.width, root.bounds.size.height, safe.left, safe.right,
                               safe.top, safe.bottom, &geometry)) { MLRestoreCompact(controller); return; }
    MLCompactState *state = objc_getAssociatedObject(controller, &MLCompactStateKey);
    if (!state) {
        const char *names[] = {"artworkView", "topContainerView", "timeControl", "transportControlsStackView",
                              "volumeSlider", "bottomButtonsStackView", "routeButton", "routeLabel"};
        NSMutableArray<UIView *> *targets = [NSMutableArray array];
        NSMutableOrderedSet<UIView *> *ancestors = [NSMutableOrderedSet orderedSet];
        for (const char *name : names) {
            UIView *view = MLNativeView(controller, name);
            if (!view || view == root || ![view isDescendantOfView:root]) return;
            [targets addObject:view];
            for (UIView *parent = view.superview; parent && parent != root; parent = parent.superview)
                [ancestors addObject:parent];
        }
        // Do not alter an unexpected hierarchy or a stack's arranged child.
        for (UIView *view in targets)
            if ([ancestors containsObject:view] || ([view.superview isKindOfClass:UIStackView.class] &&
                [((UIStackView *)view.superview).arrangedSubviews containsObject:view])) return;
        state = [MLCompactState new];
        state.targets = targets;
        state.ancestors = ancestors.array;
        state.priorities = [NSMapTable weakToStrongObjectsMapTable];
        state.masks = [NSMapTable weakToStrongObjectsMapTable];
        NSMutableArray *constraints = [NSMutableArray array];
        for (UIView *view in [targets arrayByAddingObjectsFromArray:ancestors.array]) {
            [state.masks setObject:@(view.translatesAutoresizingMaskIntoConstraints) forKey:view];
            view.translatesAutoresizingMaskIntoConstraints = NO;
        }
        for (UIView *view in ancestors)
            [constraints addObjectsFromArray:@[[view.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
                [view.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
                [view.topAnchor constraintEqualToAnchor:root.topAnchor],
                [view.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]]];
        MLRect rects[] = {geometry.artwork, geometry.metadata, geometry.time, geometry.transport,
                          geometry.volume, geometry.footer, geometry.route, geometry.routeLabel};
        for (NSUInteger index = 0; index < targets.count; index++)
            [constraints addObjectsFromArray:MLPinRect(targets[index], root, rects[index])];
        for (NSLayoutConstraint *constraint in constraints) { constraint.priority = 999; constraint.identifier = @"MusicLandscape.Compact27"; }
        state.constraints = constraints;
        objc_setAssociatedObject(controller, &MLCompactStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Preserve Apple's active/inactive choices when switching modes. Lower only
    // geometry constraints on managed native views; restore priorities on exit.
    NSArray *managed = [state.targets arrayByAddingObjectsFromArray:state.ancestors];
    for (UIView *owner in [state.ancestors arrayByAddingObjectsFromArray:[state.targets arrayByAddingObject:root]]) {
        for (NSLayoutConstraint *constraint in owner.constraints) {
            if ([constraint.identifier isEqualToString:@"MusicLandscape.Compact27"] ||
                [state.priorities objectForKey:constraint] ||
                (![managed containsObject:constraint.firstItem] && ![managed containsObject:constraint.secondItem])) continue;
            [state.priorities setObject:@(constraint.priority) forKey:constraint];
            BOOL active = constraint.active;
            if (active) constraint.active = NO;
            constraint.priority = 249;
            if (active) constraint.active = YES;
        }
    }
    MLRect rects[] = {geometry.artwork, geometry.metadata, geometry.time, geometry.transport,
                      geometry.volume, geometry.footer, geometry.route, geometry.routeLabel};
    NSUInteger start = state.ancestors.count * 4;
    for (NSUInteger index = 0; index < state.targets.count; index++) {
        MLRect rect = rects[index];
        double values[] = {rect.x, rect.y, rect.width, rect.height};
        for (NSUInteger axis = 0; axis < 4; axis++) {
            NSLayoutConstraint *constraint = state.constraints[start + index*4 + axis];
            if (fabs(constraint.constant - values[axis]) > .01) constraint.constant = values[axis];
        }
    }
    [NSLayoutConstraint activateConstraints:state.constraints];
}
