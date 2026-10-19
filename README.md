# Native Apple Music landscape layout

**0.5.1~lyrics-controls1 targets iPhone SE 2 on iOS 16.1.1 (20B101).**
It adapts the iOS 27 phone compact-landscape composition to the existing iOS 16
player: artwork at the left, metadata and controls at the right, native lyrics
and queue as hosted content. Native lyric fonts adapt to landscape height (22.5 points on SE 2).

Unlike 0.3.x, it does not select the tablet regularExtended layout or change its
1024-point threshold. Existing UIKit views, actions, scrubbers and lyric timing
are retained. Only geometry constraints are overridden, with native priorities
and autoresizing settings restored on portrait or dismissal; lyrics and queue receive a reserved control bar.

See [compact-layout evidence and limits](docs/native-layout-compact27.md),
[earlier iOS 16 investigation](docs/native-layout-ios16.md) and [usage](tweak/README.md).
Rootless arm64/arm64e builds and geometry/identity checks run on GitHub. Private
Music UI rendering and touch behavior still require real-device testing.
iOS 26 currently retains diagnostics only.

---
Historical research follows; it is not the implementation or compatibility claim
for the current iOS 16 package.

# Music landscape player port (iOS 27 -> 26.6.2)

Goal: bring the iOS 27 Apple Music **landscape full-screen player** (artwork on
the left, track info + lyrics on the right) to iOS 26.6.2 with a dylib/tweak.

## App / framework map (both versions)

- The Apple Music app binary is `/Applications/Media.app/Media`
  (not `Music.app`); helpers: `MusicUIService`, `MediaRemoteUI`,
  `MediaRemoteUIService`.
- `Media.app` links the **same 38 dylibs** on 26.6.2 and 27.0; the UI lives in
  frameworks:
  - full-screen now-playing UI -> `MediaCoreUI.framework`
  - lyrics rendering -> `MediaPlayer.framework` (600+ `*yric*` symbols)
  - `MediaControls.framework` (transport / now-playing controls)
  - `MusicUI.framework` exists in the cache but is not linked by `Media.app`
- Both `Media.app` Info.plists already allow portrait + landscape.

## What iOS 27 adds in MediaCoreUI (26.6.2 -> 27.0: +0.8 MB, +444 symbols)

`DeviceMetrics` is the layout model:

| | 26.6.2 | 27.0 |
|---|---|---|
| `Layout` cases | `regular`, `compact`, `regularExtended` | + **`compactLandscape`** |
| `Layout` helpers | `horizontalMargins` | + `isCompact` |
| `DeviceMetrics` fields | `safeAreaInsets`, `userInterfaceIdiom`, `size` | `layoutMargins`, `size`, **`isFullSizeArtworkAlwaysDisplayed`** |

Additionally new in 27.0 (no counterpart in 26.6.2):

- the UIKit import `__UIEnhancedLandscapeEnabled` and the
  `"EnhancedFullBleed"` effect path, both only present in 27.0
- `NowPlayingCustomArtworkBackground{View,Layer,EffectLayer,ReplicatorLayer}`,
  `NowPlayingArtworkBackgroundEffect`
- `NowPlayingViewModel.{BackgroundArtwork, MiniPlayerNotice, Markers,
  EyebrowConfiguration}`, `NowPlayingTimeControlState` (+`Clock`,
  `Strings.TimestampCache`), `NowPlayingSpeedPicker` / `PreciseSpeedPickerModel`
  ("Playback Speed Slider"), `NowPlayingFooterLayout`,
  `MediaTimelineControl` markers, `WaveformLayer` / `BouncyBarsAsset` /
  `WaveformDataController`, `MetalVideoTextureProvider`

## Port plan (proposal)

1. **Instrumentation first**: build a tweak that injects into the Music process
   and logs the full-screen player's view hierarchy / constraints in landscape
   on 26.6.2, plus the `DeviceMetrics.layout` classification. This avoids
   guessing the existing hierarchy.
2. **Layout port**: hook the now-playing presentation and, in landscape, arrange
   the existing artwork / metadata / lyrics views side by side like the iOS 27
   screenshot (feature-flagged, reversible).
3. Optional later: port the 27-only components (custom artwork background,
   speed picker, timeline markers) one by one.

Tooling available in this repo: `analysis/run.sh` (CI DSC extraction) and the
`Music Analysis` workflow (macOS) that produces `music-analysis-<ver>`
artifacts with MediaCoreUI / MediaPlayer / MusicKit / MediaControls.
