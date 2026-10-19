"""Produce bounded, inspectable evidence rather than treating exit 0 as analysis."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
pattern = re.compile(r"NowPlaying|mainContainerView|grabberView|artworkView|lyricsView|lyricsContainer|supportedInterfaceOrientations|shouldAutorotate|DeviceMetrics|compactLandscape", re.I)
out = []
for path in sorted(root.glob("*.txt")):
    if path.name in {"findings.txt", "dsc-info.txt"}:
        continue
    lines = path.read_text(errors="replace").splitlines()
    hits = [(index + 1, line) for index, line in enumerate(lines) if pattern.search(line)]
    if hits:
        out.append(f"\n=== {path.name}: {len(hits)} matches ===")
        # Keep all matching lines in the artifact; log output is bounded separately.
        out.extend(f"{line_number}: {line}" for line_number, line in hits)
(root / "findings.txt").write_text("\n".join(out), encoding="utf-8")
if not any(root.glob("app-Music.txt")) and not any(root.glob("app-Media.txt")):
    raise SystemExit("No Music/Media app binary analysis: extraction is incomplete")
