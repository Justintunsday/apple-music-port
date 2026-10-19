#include "../tweak/CompactGeometry.h"
#include <assert.h>
#include <stdio.h>
static void check(double width, double height, double l, double r, double t, double b) {
    MLCompactGeometry g;
    assert(MLMakeCompactGeometry(width,height,l,r,t,b,&g));
    MLRect rects[] = {g.artwork,g.metadata,g.time,g.transport,g.volume,g.footer,g.route,g.routeLabel};
    for (unsigned i=0; i<sizeof(rects)/sizeof(*rects); i++) {
        MLRect rect=rects[i];
        assert(rect.x >= l && rect.y >= t && rect.width > 0 && rect.height > 0);
        assert(rect.x+rect.width <= width-r && rect.y+rect.height <= height-b);
    }
    assert(g.artwork.x+g.artwork.width < g.metadata.x);
    assert(g.metadata.y+g.metadata.height <= g.time.y);
    assert(g.time.y+g.time.height <= g.transport.y);
    assert(g.transport.y+g.transport.height <= g.volume.y);
    assert(g.volume.y+g.volume.height < g.footer.y);
    assert(g.routeLabel.x+g.routeLabel.width < g.footer.x);
}
int main(void) {
    check(667,375,0,0,0,0); // SE 2, both landscape directions.
    check(736,414,0,0,0,0);
    check(844,390,47,47,0,21);
    check(667,375,0,0,20,0);
    MLCompactGeometry g;
    assert(!MLMakeCompactGeometry(375,667,0,0,0,0,&g));
    assert(!MLMakeCompactGeometry(667,250,0,0,0,0,&g));
    assert(!MLMakeCompactGeometry(NAN,375,0,0,0,0,&g));
    assert(!MLMakeCompactGeometry(667,375,-1,0,0,0,&g));
    puts("PASS: compact columns stay in safe areas and controls do not overlap");
}
