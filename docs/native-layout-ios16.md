# iOS 16.1.1 native player investigation

Firmware: iOS 16.1.1, build 20B101. Independently extracted from iPhone14,5 and
the user's iPhone SE 2 target (`iPhone12,8`). Both framework binaries have the
same UUID and SHA-256 `458dbb35396b750073b3df4f38a5d46e0afc5406a8a7742e45dc77742e4e5572`.
Reproduce with `analysis/ios16-native.sh`; artifacts retain the binary and dumps.

## Evidence

The real implementation is in the staged Music app's embedded
`Frameworks/MusicApplication.framework/MusicApplication`, not the small Music
launcher or the modern shared-cache MediaCoreUI player implementation.

The verified SE 2 arm64e image UUID is `AC7AFBA5-DD53-3CB8-A146-5D975BB3AD1B`.
The app's phone Info.plist permits only portrait, while its iPad orientation list
includes landscape.

The Objective-C and Swift metadata confirm:

- `MusicApplication.NowPlayingViewController` owns the existing controls controller
  and the queue/lyrics presentation state. `LayoutType` cases are `compact`,
  `regular`, `regularExtended`.
- `MusicNowPlayingControlsViewController` owns `artworkView`, `mainContainerView`,
  `contentLayoutGuide`, `artworkLayoutGuide`, transport/volume/lyrics controls and
  separate regular/extended constraint arrays. Controls modes include `splitView`.
- `MusicNowPlayingLyricsViewController` owns the native synced/static lyrics
  controllers. No separate lyric renderer is needed.

Disassembly of the native parent's `viewDidLayoutSubviews` entry at `0x3e2148`
leads to its Swift implementation at `0x3e15b4`. At `0x3e16e0` it reads
`traitCollection.userInterfaceIdiom`, checks pad (`1`), then reads
`horizontalSizeClass` and checks regular (`2`). It checks width > height, then
compares width with the double stored at `0xf6eaa8`. A width at least that value
selects the `regularExtended` branch at `0x3e1a84`.

The once initializer at `0x3d7624` converts integer `0x400` (1024) to double
via `0x8fc7c8`, then stores it at `0xf6eaa8`. This address is within the writable
`__DATA` segment (`0xe3c000` through `0xf74000`), in its zero-fill area. These
addresses are evidence for this UUID only; they must never be applied to other images.

## Implementation

`NativeLayout.xm` keeps the existing player and its native constraints/actions.
Only the native player's controllers report pad/regular traits in landscape.
The verified extended-layout minimum becomes 640 points in landscape so an SE 2's
667-point width can enter Apple's extended branch. The original 1024 value is
restored on portrait or dismissal. The app delegate's orientation mask is extended
only while the native full-screen player is active; scene geometry requests use
UIKit's iOS 16 API.

No custom player view, copied artwork, remote playback query, synthetic controls,
view reparenting or lyric fetching is introduced. The code leaves metrics and
constraints to Apple's native implementation, rather than transplanting a Swift
enum from iOS 27 into a differently laid-out iOS 16 type.

The UUID, arm64e architecture and writable segment bounds are validated before
the native path is enabled. A mismatched image remains unchanged. CPU tests
exercise these guards and the SE 2/portrait width policy. Compilation and these
tests do not verify rendering, rotation or native gesture behavior on a real phone.
Apple's existing tablet constraints may still need phone-height adjustments after
on-device evaluation. The iOS 26 implementation is structurally different and is
not enabled by this iOS 16 adapter.
