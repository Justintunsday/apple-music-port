#!/usr/bin/env bash
# Apple Music landscape-player analysis helper.
# Downloads the DSC remotely and extracts the Media/Music UI frameworks so the
# 26.6.2 and 27.0 binaries can be diffed locally.
# Usage: bash music/run.sh "26.6.2" [build] [device]
set -uo pipefail

VERSION="${1:-26.6.2}"
BUILD="${2:-}"
DEVICE="${3:-iPhone17,3}"
OUT="${OUT:-out}"

mkdir -p "$OUT"
tag="$(echo "$VERSION" | tr '.' '_')"
dir="ipsw_$tag"
mkdir -p "$dir" "$OUT/$tag/frameworks"

run_to() {
  local t="$1"; shift
  local s rc
  s="$(date +%s)"
  echo "--> [timeout ${t}s] $*"
  perl -e 'alarm shift; exec @ARGV' "$t" "$@" && rc=0 || rc=$?
  echo "    rc=$rc elapsed=$(( $(date +%s) - s ))s : $*"
  return $rc
}

echo "==> fetching DSC for iOS $VERSION ($DEVICE)"
args=(download ipsw --device "$DEVICE" --version "$VERSION" --dyld --dyld-arch arm64e --confirm -o "$dir")
if [[ -n "$BUILD" ]]; then
  args+=(--build "$BUILD")
fi
run_to 2400 ipsw "${args[@]}"

DSC="$(find "$dir" -type f -name 'dyld_shared_cache_arm64e' | head -1)"
if [[ -z "$DSC" ]]; then
  echo "!! no dyld_shared_cache_arm64e under $dir"
  find "$dir" -maxdepth 3 -type f | head -50
  exit 1
fi

# Discover every Media/Music related image in the cache for follow-up iterations.
run_to 600 ipsw dyld info "$DSC" >"$OUT/$tag/dsc_info.txt" 2>&1
grep -i -E 'media|music|nowplaying' "$OUT/$tag/dsc_info.txt" >"$OUT/$tag/media_images.txt" 2>&1 || true

# Landscape/full-screen player API surface.
run_to 300 ipsw dyld str "$DSC" \
  "landscape" "Landscape" "fullScreen" "FullScreen" "immersive" "Immersive" \
  >"$OUT/$tag/str_hits.txt" 2>&1 || true

IMAGES=(
  "/System/Library/PrivateFrameworks/MediaCoreUI.framework/MediaCoreUI"
  "/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer"
  "/System/Library/Frameworks/MusicKit.framework/MusicKit"
  "/System/Library/PrivateFrameworks/MediaControls.framework/MediaControls"
)
for img in "${IMAGES[@]}"; do
  name="$(basename "$img")"
  run_to 600 ipsw dyld macho "$DSC" "$img" --objc --symbols --strings >"$OUT/$tag/toc_$name.txt" 2>&1
  run_to 600 ipsw dyld macho "$DSC" "$img" --extract --output "$OUT/$tag/frameworks" >>"$OUT/$tag/extract_$name.txt" 2>&1
done

echo "==> done"
find "$OUT" -type f | sort
