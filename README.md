# Music landscape player port (iOS 27 -> 26.6.2)

Goal: bring the iOS 27 Media/Apple Music landscape (full-screen) player to
iOS 26.6.2 with a dylib/tweak, continuing in this repository.

## What we know so far

- On iOS 26/27 the Apple Music app binary is `/Applications/Media.app/Media`
  (not `Music.app`), accompanied by `MusicUIService`, `MediaRemoteUI` and
  `MediaRemoteUIService`.
- The four app binaries were extracted from both OS volumes (26.6.2 build
  23G90, 27.0 build 24A437). Both versions link the **same 38 dylibs**, and the
  app binaries expose no landscape/player classes themselves - the UI lives in
  frameworks.
- `MediaCoreUI.framework` is the prime candidate: it is imported by `Media`
  and hosts the media now-playing / full-screen player UI.
- Framework binaries are not on the filesystem, only inside the DSC, so the
  `Music Analysis` workflow downloads the DSC and extracts:
  `MediaCoreUI`, `MediaPlayer`, `MusicKit`, `MediaControls`, plus a
  Media/Music image inventory and landscape/full-screen string search.
- Local DSC copies are missing the `.dyldlinkedit` subcache, and the local
  Python (dissect) extraction of the cryptex linkedit hits an LZBITMAP bug, so
  framework extraction is done on CI (macOS) instead.

## Next steps

1. Run `Music Analysis`, download `music-analysis-26.6.2` / `-27.0`.
2. Diff `MediaCoreUI` symbols/strings between the two versions; find the
   landscape/full-screen player types that are new in 27.
3. Decide the port mechanism (new UI code in a tweak vs. selectively loading
   extracted 27.0 components) and prototype behind a feature flag.
