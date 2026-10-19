"""Compile the actual overlay in a simulator host with mocked media IPC.

Only the dynamic loader and Logos installation are excluded: the overlay,
request/timeout handling, observer and geometry implementation are unchanged.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = (root / "tweak/Tweak.xm").read_text(encoding="utf-8")
assert "viewDidLayoutSubviews" not in source, "Do not reintroduce the layout hook"
assert "MPMusicPlayerController" not in source, "Do not reintroduce synchronous playback reads"
source = source.split("%hook UIViewController", 1)[0]
start = source.index("static void MLLoadMediaRemote(void) {")
end = source.index("\n@interface MLLandscape", start)
source = source[:start] + "static void MLLoadMediaRemote(void) {}\n" + source[end:]
(root / "tests/PlayerUnderTest.m").write_text(source, encoding="utf-8")
