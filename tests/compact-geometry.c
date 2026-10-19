#include "../tweak/CompactGeometry.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int close_enough(double a, double b) { return fabs(a - b) < .01; }

static void check(double width, double height, double l, double r, double t, double b) {
    MLCompactGeometry g;
    assert(MLMakeCompactGeometry(width, height, l, r, t, b, &g));
    MLRect rects[] = {g.artwork, g.metadata, g.time, g.transport, g.volume, g.footer, g.route, g.routeLabel};
    for (unsigned i = 0; i < sizeof(rects) / sizeof(*rects); i++) {
        MLRect rect = rects[i];
        assert(rect.x >= l && rect.y >= t && rect.width > 0 && rect.height > 0);
        assert(rect.x + rect.width <= width - r + .01);
        assert(rect.y + rect.height <= height - b + .01);
    }
    assert(g.artwork.x + g.artwork.width < g.metadata.x);
    assert(g.metadata.y + g.metadata.height + 8 <= g.time.y);
    assert(g.time.y + g.time.height <= g.transport.y);
    assert(g.transport.y + g.transport.height <= g.volume.y);
    assert(g.volume.y + g.volume.height < g.footer.y);
    assert(g.routeLabel.x + g.routeLabel.width < g.footer.x);
    assert(g.footer.x > g.artwork.x + g.artwork.width);
    assert(g.route.x > g.artwork.x + g.artwork.width);
}
int main(void) {
    check(667, 375, 0, 0, 0, 0);   // iPhone SE 2, both landscape directions.
    check(736, 414, 0, 0, 0, 0);
    check(844, 390, 47, 47, 0, 21);
    check(667, 375, 0, 0, 20, 0);
    MLCompactGeometry g;
    assert(MLMakeCompactGeometry(667, 375, 0, 0, 0, 0, &g));
    assert(close_enough(g.artwork.x, 32) && close_enough(g.artwork.y, 41.75) && close_enough(g.artwork.width, 291.5));
    assert(close_enough(g.metadata.x, 343.5) && close_enough(g.metadata.width, 291.5));
    assert(close_enough(g.footer.x, 515) && close_enough(g.footer.y, 299));
    assert(close_enough(g.routeLabel.width, 115.5));
    assert(close_enough(g.time.y, 133));
    assert(!MLMakeCompactGeometry(375, 667, 0, 0, 0, 0, &g));
    assert(!MLMakeCompactGeometry(667, 250, 0, 0, 0, 0, &g));
    assert(!MLMakeCompactGeometry(NAN, 375, 0, 0, 0, 0, &g));
    assert(!MLMakeCompactGeometry(667, 375, -1, 0, 0, 0, &g));
    puts("PASS: SE2 iOS27 margins, right-column controls and safe-area containment");
}
