#import "MPHierarchyProbe.h"
#import "MPLog.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>

@interface MPHierarchyProbe ()
+ (NSString *)describeView:(UIView *)view inWindow:(UIWindow *)window;
+ (void)logMethodsForClassName:(NSString *)name;
@end

static const char *MPImagePath(const char *needle) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, needle)) return name;
    }
    return NULL;
}

static NSInteger MPTextLayerCount(CALayer *layer) {
    NSInteger count = [layer isKindOfClass:CATextLayer.class] ? 1 : 0;
    for (CALayer *sub in layer.sublayers) count += MPTextLayerCount(sub);
    return count;
}

static NSArray<NSString *> *MPSelectorNames(Class cls, BOOL classMethods) {
    Class target = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *sels = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *sel = NSStringFromSelector(method_getName(methods[i]));
        if (sel.length) [sels addObject:sel];
    }
    if (methods) free(methods);
    [sels sortUsingSelector:@selector(compare:)];
    if (sels.count > 200) return [sels subarrayWithRange:NSMakeRange(0, 200)];
    return sels;
}

static void MPCollectViews(UIView *view, UIWindow *window, NSInteger depth, NSMutableArray<MPViewCandidate *> *out) {
    CGSize screen = window.bounds.size;
    CGFloat screenArea = MAX(screen.width * screen.height, 1);
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGFloat side = MAX(frame.size.width, frame.size.height);
    MPViewCandidate *c = [MPViewCandidate new];
    c.className = NSStringFromClass(view.class);
    c.frame = frame;
    c.areaRatio = (frame.size.width * frame.size.height) / screenArea;
    c.depth = depth;
    c.subviewCount = view.subviews.count;
    c.hasLayerContents = view.layer.contents != nil;
    c.hosting = [c.className containsString:@"Hosting"] || [c.className containsString:@"DisplayList"];
    c.textLayerCount = MPTextLayerCount(view.layer);
    c.squareness = side > 0 ? MIN(frame.size.width, frame.size.height) / side : 0;
    c.view = view;
    [out addObject:c];
    for (UIView *sub in view.subviews) MPCollectViews(sub, window, depth + 1, out);
}

@implementation MPViewCandidate

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ frame=%@ area=%.3f depth=%ld subviews=%ld contents=%d hosting=%d textLayers=%ld square=%.2f",
            self.className,
            NSStringFromCGRect(self.frame),
            self.areaRatio,
            (long)self.depth,
            (long)self.subviewCount,
            self.hasLayerContents,
            self.hosting,
            (long)self.textLayerCount,
            self.squareness];
}

@end

@implementation MPHierarchyProbe

+ (void)logMediaClassInventory {
    const char *image = MPImagePath("MediaCoreUI");
    MPLog(@"MediaCoreUI image: %s", image ?: "(not loaded)");

    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if (image) {
        unsigned int count = 0;
        const char **classNames = objc_copyClassNamesForImage(image, &count);
        if (classNames) {
            for (unsigned int i = 0; i < count; i++) {
                if (!classNames[i]) continue;
                [names addObject:[NSString stringWithUTF8String:classNames[i]]];
            }
            free(classNames);
        }
    }
    if (names.count == 0) {
        unsigned int count = 0;
        Class *classes = objc_copyClassList(&count);
        if (classes) {
            for (unsigned int i = 0; i < count; i++) {
                NSString *n = NSStringFromClass(classes[i]);
                if ([n hasPrefix:@"MediaCoreUI."] || [n hasPrefix:@"MediaControls."]) [names addObject:n];
            }
            free(classes);
        }
    }
    [names sortUsingSelector:@selector(compare:)];
    MPLog(@"MediaCoreUI/MediaControls classes: %lu", (unsigned long)names.count);

    NSArray<NSString *> *keywords = @[@"NowPlaying", @"Player", @"Lyric", @"DeviceMetrics", @"FullScreen", @"Landscape", @"Artwork", @"Timeline", @"MiniPlayer", @"Immersive", @"Speed", @"Waveform"];
    NSUInteger logged = 0;
    for (NSString *n in names) {
        BOOL interesting = NO;
        for (NSString *kw in keywords) {
            if ([n rangeOfString:kw options:NSCaseInsensitiveSearch].location != NSNotFound) {
                interesting = YES;
                break;
            }
        }
        if (!interesting) continue;
        MPLog(@"class %@", n);
        if (++logged >= 150) break;
    }

    for (NSString *n in names) {
        BOOL isPlayerClass = [n rangeOfString:@"NowPlaying" options:NSCaseInsensitiveSearch].location != NSNotFound;
        BOOL isMetricsClass = [n rangeOfString:@"DeviceMetrics" options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (!isPlayerClass && !isMetricsClass) continue;
        [self logMethodsForClassName:n];
    }
}

+ (void)logMethodsForClassName:(NSString *)name {
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) return;
    MPLog(@"methods %@ (-): %@", name, [MPSelectorNames(cls, NO) componentsJoinedByString:@" "]);
    MPLog(@"methods %@ (+): %@", name, [MPSelectorNames(cls, YES) componentsJoinedByString:@" "]);
}

+ (NSArray<MPViewCandidate *> *)candidatesInWindow:(UIWindow *)window {
    NSMutableArray<MPViewCandidate *> *out = [NSMutableArray array];
    if (window) MPCollectViews(window, window, 0, out);
    [out sortUsingComparator:^NSComparisonResult(MPViewCandidate *a, MPViewCandidate *b) {
        if (a.areaRatio == b.areaRatio) return NSOrderedSame;
        return a.areaRatio > b.areaRatio ? NSOrderedAscending : NSOrderedDescending;
    }];
    return out;
}

+ (NSString *)describeView:(UIView *)view inWindow:(UIWindow *)window {
    if (!view) return @"(none)";
    return [NSString stringWithFormat:@"%@ %@",
            NSStringFromClass(view.class),
            NSStringFromCGRect([view convertRect:view.bounds toView:window])];
}

+ (void)logHierarchyForWindow:(UIWindow *)window reason:(NSString *)reason {
    if (!window) return;
    MPLog(@"---- hierarchy (%@) %@ ----", reason, NSStringFromClass(window.class));
    MPLogView(window, @"window");

    NSInteger n = 0;
    for (MPViewCandidate *c in [self candidatesInWindow:window]) {
        if (c.areaRatio < 0.01) continue;
        MPLog(@"cand %@", c);
        if (++n >= 40) break;
    }

    UIView *artwork = [self bestArtworkViewInWindow:window];
    UIView *details = [self bestDetailsViewInWindow:window avoiding:artwork];
    MPLog(@"guess artwork: %@", [self describeView:artwork inWindow:window]);
    MPLog(@"guess details: %@", [self describeView:details inWindow:window]);
}

+ (UIView *)bestArtworkViewInWindow:(UIWindow *)window {
    NSArray<MPViewCandidate *> *all = [self candidatesInWindow:window];
    MPViewCandidate *best = nil;
    for (MPViewCandidate *c in all) {
        if (!c.hasLayerContents) continue;
        if (c.squareness < 0.92) continue;
        if (c.areaRatio < 0.12 || c.areaRatio > 0.9) continue;
        if (c.subviewCount > 8) continue;
        if (!best || c.areaRatio > best.areaRatio) best = c;
    }
    if (!best) {
        for (MPViewCandidate *c in all) {
            if (c.squareness < 0.92) continue;
            if (c.areaRatio < 0.12 || c.areaRatio > 0.9) continue;
            if (c.subviewCount > 6) continue;
            if (!best || c.areaRatio > best.areaRatio) best = c;
        }
    }
    return best.view;
}

+ (UIView *)bestDetailsViewInWindow:(UIWindow *)window avoiding:(UIView *)artwork {
    MPViewCandidate *best = nil;
    CGFloat bestScore = -1;
    for (MPViewCandidate *c in [self candidatesInWindow:window]) {
        UIView *v = c.view;
        if (v == artwork) continue;
        if (c.areaRatio < 0.12) continue;
        if ([v isKindOfClass:UIWindow.class]) continue;
        if (artwork && ([v isDescendantOfView:artwork] || [artwork isDescendantOfView:v])) continue;
        CGFloat score = c.areaRatio
            + 0.01 * (CGFloat)MIN(c.textLayerCount, 50)
            + 0.005 * (CGFloat)MIN(c.subviewCount, 40);
        if (score > bestScore) {
            bestScore = score;
            best = c;
        }
    }
    return best.view;
}

+ (UIView *)findViewIn:(UIView *)root matchingClassNames:(NSArray<NSString *> *)names index:(NSUInteger)index {
    if (!root || names.count == 0) return nil;
    NSMutableArray<UIView *> *matches = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSString *cls = NSStringFromClass(v.class);
        for (NSString *pattern in names) {
            BOOL hit = [pattern hasSuffix:@"*"]
                ? [cls hasPrefix:[pattern substringToIndex:pattern.length - 1]]
                : [cls isEqualToString:pattern];
            if (hit) {
                [matches addObject:v];
                break;
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    if (index >= matches.count) return nil;
    return matches[index];
}

@end
