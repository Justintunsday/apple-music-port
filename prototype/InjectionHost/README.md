# Simulator dylib integration test

`MusicPortInjectionHost` is a small UIKit app with artwork and details views.
`MusicPortSimulator` compiles the same Objective-C layout host used by the
device tweak. The app does not link the dylib; CI supplies its path through
`SIMCTL_CHILD_DYLD_INSERT_LIBRARIES` when launching the app in Simulator.

The dylib checks that it can find the test views, apply the two-column layout,
restore the original view order and constraints, and apply the layout again.
It writes `MusicPortSimulator.result` in the app's temporary directory. CI
requires a `PASS:` result and uploads a screenshot of the injected app.

This checks the injection mechanism and shared layout code. The Apple Music
process and its private view hierarchy are not present in this test host.
