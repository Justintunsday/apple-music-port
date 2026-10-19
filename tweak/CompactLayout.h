#import "CompactGeometry.h"

static char MLCompactStateKey;
@interface MLCompactState : NSObject
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *constraints;
@property(nonatomic, strong) NSMapTable<NSLayoutConstraint *, NSNumber *> *priorities;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *masks;
@property(nonatomic, strong) NSArray<UIView *> *targets;
@property(nonatomic, strong) NSArray<NSValue *> *targetRects;
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
static BOOL MLIsArrangedSubview(UIView *view) {
    return [view.superview isKindOfClass:UIStackView.class] &&
           [((UIStackView *)view.superview).arrangedSubviews containsObject:view];
}
static BOOL MLIsRelated(UIView *a, UIView *b) {
    for (UIView *view = a; view; view = view.superview) if (view == b) return YES;
    for (UIView *view = b; view; view = view.superview) if (view == a) return YES;
    return NO;
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
        struct { const char *name; MLRect rect; bool required; } specs[] = {
            {"artworkView", geometry.artwork, true},
            {"topContainerView", geometry.metadata, true},
            {"timeControl", geometry.time, true},
            {"transportControlsStackView", geometry.transport, true},
            {"volumeSlider", geometry.volume, true},
            {"bottomButtonsStackView", geometry.footer, false},
            {"routeButton", geometry.route, false},
            {"routeLabel", geometry.routeLabel, false},
        };
        NSMutableArray<UIView *> *targets = [NSMutableArray array];
        NSMutableArray<NSValue *> *rects = [NSMutableArray array];
        NSMutableOrderedSet<UIView *> *ancestors = [NSMutableOrderedSet orderedSet];
        for (size_t index = 0; index < sizeof(specs) / sizeof(specs[0]); index++) {
            UIView *view = MLNativeView(controller, specs[index].name);
            if (!view || view == root || ![view isDescendantOfView:root]) {
                if (specs[index].required) { MLRestoreCompact(controller); return; }
                continue;
            }
            BOOL conflict = MLIsArrangedSubview(view);
            for (UIView *target in targets)
                if (MLIsRelated(view, target)) { conflict = YES; break; }
            if (conflict) {
                if (specs[index].required) { MLRestoreCompact(controller); return; }
                continue;
            }
            [targets addObject:view];
            [rects addObject:[NSValue valueWithBytes:&specs[index].rect objCType:@encode(MLRect)]];
            for (UIView *parent = view.superview; parent && parent != root; parent = parent.superview)
                [ancestors addObject:parent];
        }
        for (UIView *view in targets)
            if ([ancestors containsObject:view]) { MLRestoreCompact(controller); return; }
        state = [MLCompactState new];
        state.targets = targets;
        state.targetRects = rects;
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
        for (NSUInteger index = 0; index < targets.count; index++) {
            MLRect rect;
            [state.targetRects[index] getValue:&rect];
            [constraints addObjectsFromArray:MLPinRect(targets[index], root, rect)];
        }
        for (NSLayoutConstraint *constraint in constraints) {
            constraint.priority = 999;
            constraint.identifier = @"MusicLandscape.SE2iOS27";
        }
        state.constraints = constraints;
        objc_setAssociatedObject(controller, &MLCompactStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray *managed = [state.targets arrayByAddingObjectsFromArray:state.ancestors];
    for (UIView *owner in [state.ancestors arrayByAddingObjectsFromArray:[state.targets arrayByAddingObject:root]]) {
        for (NSLayoutConstraint *constraint in owner.constraints) {
            if ([constraint.identifier isEqualToString:@"MusicLandscape.SE2iOS27"] ||
                [state.priorities objectForKey:constraint] ||
                (![managed containsObject:constraint.firstItem] && ![managed containsObject:constraint.secondItem])) continue;
            [state.priorities setObject:@(constraint.priority) forKey:constraint];
            BOOL active = constraint.active;
            if (active) constraint.active = NO;
            constraint.priority = 249;
            if (active) constraint.active = YES;
        }
    }
    NSUInteger start = state.ancestors.count * 4;
    for (NSUInteger index = 0; index < state.targets.count; index++) {
        MLRect rect;
        [state.targetRects[index] getValue:&rect];
        double values[] = {rect.x, rect.y, rect.width, rect.height};
        for (NSUInteger axis = 0; axis < 4; axis++) {
            NSLayoutConstraint *constraint = state.constraints[start + index * 4 + axis];
            if (fabs(constraint.constant - values[axis]) > .01) constraint.constant = values[axis];
        }
    }
    [NSLayoutConstraint activateConstraints:state.constraints];
}
