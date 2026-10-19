#pragma once
#include <math.h>
#include <stdbool.h>
typedef struct { double x, y, width, height; } MLRect;
typedef struct { MLRect artwork, metadata, time, transport, volume, footer, route, routeLabel; } MLCompactGeometry;
static inline bool MLMakeCompactGeometry(double width, double height, double left, double right,
                                         double top, double bottom, MLCompactGeometry *g) {
    if (!g || !isfinite(width) || !isfinite(height) || !isfinite(left) || !isfinite(right) ||
        !isfinite(top) || !isfinite(bottom) || left < 0 || right < 0 || top < 0 || bottom < 0 ||
        width <= height || width - left - right < 480 || height - top - bottom < 300) return false;
    double x = left + 20, y = top + 20, w = width - left - right - 40;
    double column = (w - 28) / 2, trailing = x + column + 28;
    double footer = height - bottom - 64, body = footer - 16 - y;
    double side = fmin(column, body);
    g->artwork = (MLRect){x + (column-side)/2, y + (body-side)/2, side, side};
    g->metadata = (MLRect){trailing, y, column, 52};
    g->time = (MLRect){trailing, y + body * .28, column, 32};
    g->transport = (MLRect){trailing, y + body * .49, column, 56};
    g->volume = (MLRect){trailing, y + body - 32, column, 32};
    g->footer = (MLRect){width-right-132, footer, 112, 44};
    g->route = (MLRect){x, footer, 44, 44};
    g->routeLabel = (MLRect){x+48, footer, fmax(0, column-48), 44};
    return true;
}
