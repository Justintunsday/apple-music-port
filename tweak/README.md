# Native Apple Music layout investigation

The requested feature is to reposition Apple's existing artwork, controls and
lyrics views inside the native player on iOS 16 and iOS 26. The former 0.1.x
custom-player overlay did not implement that feature and has been removed.

**0.2.0~diagnostics1 captures the native view tree. It is not the finished native
landscape modification.** It uses the same package identifier and dylib name to
replace the old implementation. Fully terminate Music after installation.
It does not modify frames, constraints, rotation policies or playback state.

## Capture on the real device

1. Install the rootless deb, fully close and reopen Apple Music.
2. Open the native full-screen player in portrait. Rotate to landscape and wait
   one second. Open the native lyrics panel and rotate once more.
3. Double-tap with **three fingers** in Music to open the native share sheet.
   Save `MusicLandscape-native-layout.json` to Files, then attach it to the
   development conversation. The gesture may conflict with accessibility Zoom.
4. After export, the report also exists inside Music's app data container at
   `Library/Caches/MusicLandscape-native-layout.json`. Container UUIDs vary.

The report includes instantiated controller/view class names, method names,
frames, bounds, transforms, rotation state and constraint attributes. It omits
label text, song metadata, lyric text, artwork, accounts, device identifiers and
screenshots. No report is uploaded automatically.

Captures have a 1200-view/100-controller limit and a 75 ms traversal budget, with
at most six automatic snapshots and eight retained snapshots per process. A
truncation flag marks partial captures. JSON encoding and file writes run off
the main thread. UIKit reads run on the main thread. Device behavior still
requires verification.

## Next step

Use the iOS 16.1.1 report to identify the real artwork, lyrics and controls, their
container ownership, constraints and rotation policy. Implement a version-specific
adapter and verify portrait restoration, dismissal and lyrics toggling. Obtain
a separate report from the exact iOS 26 release before enabling its adapter.
Static framework symbols alone do not establish the instantiated hierarchy.

Build on macOS with Xcode and Theos:

```sh
make -C tweak clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```
