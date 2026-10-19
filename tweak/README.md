# Music Landscape (experimental rootless tweak)

Targets **iOS 16.x and iOS 26.x only**, with arm64 and arm64e slices and an
`iphoneos-arm64` Debian package installed under `/var/jb` by Theos.
Requires an existing rootless jailbreak and working tweak injection into Apple
Music. A successful build does not establish jailbreak availability or device compatibility.

This is a new UIKit implementation, not a binary transplant of iOS 27 frameworks.
It displays current artwork, title, artist, playback position, seeking and
previous/play/pause/next controls through the system music player. There are no
sample tracks or placeholder lyrics. Native synchronized lyrics, queues and
iOS 27 artwork effects are not implemented.

## Use

Install the `.deb` with Sileo/Zebra, fully close and reopen Apple Music, open its
full-screen player, then rotate the device to landscape. Portrait restores the
native player. The down arrow hides the overlay until the next portrait rotation.
The original view hierarchy is not reparented or modified.

Controller names can differ between OS releases. If automatic detection does not
work, **double-tap with three fingers in Apple Music while holding the phone in
landscape** to toggle the overlay manually. This gesture may conflict with system
accessibility gestures. Native player detection logs its controller name with
the `[MusicLandscape]` prefix. Unknown controller names require device inspection.
When Music stays portrait-locked, the overlay rotates independently.

## Build

On macOS with Xcode, Theos and ldid installed:

```sh
make -C tweak clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

GitHub Actions builds against the installed Xcode SDK with deployment target
16.0. Both OS versions use the same binary; the runtime restricts activation to
major versions 16 and 26. CI verifies Mach-O slices, minimum OS version, package
architecture and installation paths. **Playback, controller detection, rotation,
DRM/cloud metadata, accessibility and lifecycle behavior remain untested on real
iOS 16/26 devices.** The public music-player API may return incomplete metadata
for some streaming content. Remove the package and restart Music to revert.
