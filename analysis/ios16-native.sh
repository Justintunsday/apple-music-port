#!/usr/bin/env bash
# Static analysis of the exact iOS 16.1.1 build used by the reported device.
set -euo pipefail
OUT=out/16_1_1
mkdir -p "$OUT" firmware cache app
run_to() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }
ipsw version | tee "$OUT/tool-version.txt"
df -h .
run_to 1800 ipsw download ipsw --device iPhone14,5 --build 20B101 --confirm -o firmware
IPSW=$(find firmware -name '*.ipsw' -type f -print -quit)
test -n "$IPSW"
ipsw info "$IPSW" > "$OUT/firmware-info.txt"
run_to 1200 ipsw extract "$IPSW" --dyld --dyld-arch arm64e -o cache
DSC=$(find cache -type f -name dyld_shared_cache_arm64e -print -quit)
test -n "$DSC"
ipsw dyld info "$DSC" > "$OUT/dsc-info.txt"
grep -Ei 'Music|MediaCoreUI|MediaPlayer|MediaControls|NowPlaying' "$OUT/dsc-info.txt" > "$OUT/media-images.txt" || true
# Unlike the newer OS, Music's UI may live in the app executable or embedded
# frameworks. Extract these as well as shared-cache images.
run_to 1200 ipsw extract "$IPSW" --files --pattern 'Applications/(Music|Media)\.app/(Music|Media|Info\.plist|Frameworks/.*)$' -o app
find app -type f > "$OUT/app-files.txt"
while IFS= read -r binary; do
    file "$binary" | grep -q 'Mach-O' || continue
    name=$(basename "$binary")
    echo "=== APP MACHO: $binary ==="
    run_to 240 ipsw macho info "$binary" --objc --symbols --loads --swift > "$OUT/app-$name.txt" 2>&1 || true
    otool -l "$binary" | grep -A5 -E 'LC_ENCRYPTION_INFO|LC_BUILD_VERSION' > "$OUT/app-$name-loads.txt" || true
done < "$OUT/app-files.txt"
for image in MediaCoreUI MediaPlayer MediaControls MusicUI MusicKit MusicKitInternal; do
    echo "=== CACHE IMAGE: $image ==="
    run_to 240 ipsw dyld macho "$DSC" "$image" --objc --symbols --strings > "$OUT/cache-$image.txt" 2>&1 || true
done
python3 analysis/summarize-native.py "$OUT"
cat "$OUT/findings.txt"
# Keep binaries as downloadable analysis artifacts, not as repository files.
cp -R app "$OUT/app-binaries"
