# Compact landscape composition adapted to iOS 16

The installation target is the user's iPhone SE 2 on iOS 16.1.1 (20B101).
The firmware reference selected for this revision is iPhone12,8 iOS 27.0.1
(24A446), analyzed by `analysis/se2-ios27-native.sh`. Its app and shared-cache
metadata are retained as GitHub Actions artifacts, rather than shipped in the deb.

## Structural evidence

The exact SE 2 extraction completed in [Actions run 39206011516](https://github.com/Justintunsday/apple-music-port/actions/runs/39206011516).
Its firmware metadata identifies `iPhone12,8_D79AP_24A446`, A13 and production
iOS 27.0.1. Extracted MediaCoreUI has UUID `D3569640-C411-39F3-8679-E700BEA79FA1`
and SHA-256 `e9f6d7004735ed5f0171c77bd614340e1d7d632ba59ac010918d5627cd19c38e`.
Full-cache Swift metadata confirms the same compact-landscape composition:
`FullScreenContentView_CompactLandscape` accessor `0x1ce3cbde8`,
`CompactLandscapeLayout` accessor `0x1ce3cbe6c`, `MetadataAndControlsView`
accessor `0x1ce3cbe84`, and `FullWindowHostedContentView` accessor `0x1ce3cbe54`.
These are analysis references only; no iOS 27 addresses are used by the tweak.

The earlier iOS 27.0 MediaCoreUI dump identified these native SwiftUI types:

- `NowPlayingView.FullScreenContentView_CompactLandscape`
- `NowPlayingView.CompactLandscapeLayout`, with device metrics, safe area and footer visibility
- `NowPlayingView.MetadataAndControlsView`, grouping metadata, time, transport and volume
- `NowPlayingView.FullWindowHostedContentView` and its independent layout

The compact-landscape body's generic type contains artwork/banner content,
metadata/controls and footer buttons, together with optional full-window hosted
content. It is distinct from `regularExtended` tablet layout. This establishes
component structure, not exact frame constants or pixel-for-pixel equivalence.

## Adaptation

iOS 16's native UIKit player cannot execute these newer SwiftUI types. The tweak
therefore keeps phone/compact traits and reuses its existing artwork, top metadata
container, time control, transport stack, volume slider, footer and route views.
Named object ivars are resolved via Objective-C runtime metadata with type and
hierarchy checks; object offsets and Swift struct layouts are not hard-coded.
No view is added, reparented, copied or replaced.

For ordinary playback, `CompactGeometry.h` calculates two columns within the
actual safe area. Its spacing constants are adaptation choices for a 667 x 375
point screen, not values claimed to have been recovered from Apple. Geometry
tests check containment, control ordering, and non-overlap at SE 2 dimensions.

Existing boundary constraints keep their native active/inactive mode choices.
Their priorities are temporarily lowered while the adaptation's constraints are
active. Original priorities and autoresizing settings are restored for portrait
and dismissal. Descendant button/slider
behavior, audio routing and lyric synchronization remain Apple's implementation.

## Limits

This is a structural layout adaptation, not a transplanted iOS 27 framework or
all of its animations, materials and features. Native hosted content uses iOS 16's
renderer and presentation behavior. Private hierarchy assumptions are guarded;
an unexpected hierarchy leaves native geometry unchanged. Actual constraint
resolution, mode transitions, rendering and hit testing require phone validation.
The package does not enable iOS 26 or iOS 27 installation support.

## 0.5.1 hosted-content controls follow-up

The device screenshot showed full-width native lyrics and metadata, but no
scrubber, transport, volume or lyrics/queue footer. Earlier code explicitly
removed compact constraints when hosted content was visible, leaving iOS 16's
full-screen lyric presentation in charge of the whole height.

This revision gives hosted lyrics/queue their own geometry: on a 667 x 375 screen,
the native content branch ends at y=243, the native scrubber occupies y=251..287,
and native transport, volume, route and lyrics/queue controls occupy y=299..343.
The metadata header and native lyric renderer remain intact. No controls are
created or reparented. The native `setControlsHidden:animator:` entry verified at
0x5a96e0 (Swift implementation 0x5a8ea8) is called to expose the existing controls
on entry; hide requests are suppressed only while this player's landscape
hosted content is visible. The previous unconditional restore on the parent
layout path is removed. Portrait and dismissal still restore native geometry.

Mode, bounds and safe-area changes rebuild the scoped constraint state instead
of retaining rectangles from the previous mode. The host branch is never chosen
if it contains the playback-controls controller. Geometry tests cover SE 2,
safe areas and separation between content and all control hit areas. Actual
visibility, gesture behavior and rendering still need real-device verification.
