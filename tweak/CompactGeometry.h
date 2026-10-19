#pragma once
#include <math.h>
#include <stdbool.h>

typedef struct { double x, y, width, height; } MLRect;
typedef struct { MLRect artwork, metadata, time, transport, volume, footer, route, routeLabel; } MLCompactGeometry;

// iOS 27.0.1 MediaCoreUI DeviceMetrics.Layout.horizontalMargins:
// compact 32, compactLandscape 32, regular 78, regularExtended 52.
#define ML_COMPACT27_HORIZONTAL_MARGIN 32.0
#define ML_COMPACT27_VERTICAL_MARGIN 32.0
#define ML_COMPACT27_COLUMN_GAP 20.0
#define ML_COMPACT27_FOOTER_WIDTH 120.0

static inline bool MLMakeCompactGeometry(double width, double height, double left, double right,
                                         double top, double bottom, MLCompactGeometry *g) {
    if (!g || !isfinite(width) || !isfinite(height) || !isfinite(left) || !isfinite(right) ||
        !isfinite(top) || !isfinite(bottom) || left < 0 || right < 0 || top < 0 || bottom < 0 ||
        width <= height || width < 600 || height < 300) return false;
    double x = left + ML_COMPACT27_HORIZONTAL_MARGIN;
    double r = right + ML_COMPACT27_HORIZONTAL_MARGIN;
    double y = top + ML_COMPACT27_VERTICAL_MARGIN;
    double b = bottom + ML_COMPACT27_VERTICAL_MARGIN;
    double availableWidth = width - x - r;
    double availableHeight = height - y - b;
    if (availableWidth < 480 || availableHeight < 260) return false;
    double column = (availableWidth - ML_COMPACT27_COLUMN_GAP) * .5;
    if (column < 180) return false;
    double side = fmin(column, availableHeight);
    double detailsX = x + column + ML_COMPACT27_COLUMN_GAP;
    double footerY = height - b - 44;
    double volumeY = footerY - 10 - 32;
    double transportY = volumeY - 10 - 56;
    double timeY = transportY - 10 - 48;
    double metadataBottom = y + 64;
    double routeLabelWidth = column - 48 - ML_COMPACT27_FOOTER_WIDTH - 8;
    if (routeLabelWidth < 24 || timeY < metadataBottom + 8) return false;
    g->artwork = (MLRect){x + (column - side) * .5, top + (height - top - bottom - side) * .5, side, side};
    g->metadata = (MLRect){detailsX, y, column, 64};
    g->time = (MLRect){detailsX, timeY, column, 48};
    g->transport = (MLRect){detailsX, transportY, column, 56};
    g->volume = (MLRect){detailsX, volumeY, column, 32};
    g->footer = (MLRect){detailsX + column - ML_COMPACT27_FOOTER_WIDTH, footerY, ML_COMPACT27_FOOTER_WIDTH, 44};
    g->route = (MLRect){detailsX, footerY, 44, 44};
    g->routeLabel = (MLRect){detailsX + 48, footerY, routeLabelWidth, 44};
    return true;
}
