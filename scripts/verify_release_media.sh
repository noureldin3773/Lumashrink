#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
APP="${LUMASHRINK_APP_PATH:-$HOME/Desktop/LumaShrink.app}"
IMAGE_HELPER="$APP/Contents/Resources/runtime/lumashrink-image-helper/lumashrink-image-helper"
VIDEO_HELPER="$APP/Contents/Resources/runtime/lumashrink-video-helper/lumashrink-video-helper"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/in/a" "$TMP/in/b" "$TMP/out"

test -x "$IMAGE_HELPER"
test -x "$VIDEO_HELPER"
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null

"$PYTHON" - "$TMP" <<'PY'
from PIL import Image
from pathlib import Path
import os, sys
r = Path(sys.argv[1])
exif = Image.Exif(); exif[0x010E] = "LumaShrink metadata test"
Image.new("RGB", (1800, 1200), (80, 130, 210)).save(r / "photo.jpg", quality=98, exif=exif)
Image.frombytes("RGBA", (700, 700), os.urandom(700 * 700 * 4)).save(r / "alpha.png")
Image.new("RGB", (1200, 800), (160, 60, 100)).save(r / "source.webp", quality=98)
Image.new("RGB", (800, 600), (20, 40, 80)).save(r / "heic-source.png")
Image.new("RGB", (32, 32), (10, 20, 30)).save(r / "tiny.jpg", quality=70)
Image.frombytes("RGB", (600, 600), os.urandom(600 * 600 * 3)).save(r / "hard.png")
Image.new("RGB", (800, 600), "red").save(r / "in/a/duplicate.jpg")
Image.new("RGB", (800, 600), "blue").save(r / "in/b/duplicate.jpg")
PY

"$IMAGE_HELPER" "$TMP/photo.jpg" "$TMP/out" -s 150kb --format webp --name-mode suffix >"$TMP/photo.log"
"$IMAGE_HELPER" "$TMP/photo.jpg" "$TMP/out" -s 150kb --format jpeg --name-mode suffix --keep-metadata >"$TMP/metadata.log"
"$IMAGE_HELPER" "$TMP/alpha.png" "$TMP/out" -s 300kb --format png --name-mode suffix >"$TMP/alpha.log"
"$IMAGE_HELPER" "$TMP/source.webp" "$TMP/out" -s 150kb --format jpeg --name-mode suffix >"$TMP/webp.log"
sips -s format heic "$TMP/heic-source.png" --out "$TMP/photo.heic" >/dev/null
"$IMAGE_HELPER" "$TMP/photo.heic" "$TMP/out" -s 200kb --format jpeg --name-mode suffix >"$TMP/heic.log"
"$IMAGE_HELPER" "$TMP/tiny.jpg" "$TMP/out" -s 150kb --format keep --name-mode suffix >"$TMP/tiny.log"
if "$IMAGE_HELPER" "$TMP/hard.png" "$TMP/out" -s 1kb --format png --name-mode suffix --keep-dimensions >"$TMP/hard.log"; then exit 1; fi
"$IMAGE_HELPER" "$TMP/in" "$TMP/out" -s 150kb --format webp --name-mode suffix >"$TMP/duplicates.log"
printf 'not an image' >"$TMP/corrupt.jpg"
if "$IMAGE_HELPER" "$TMP/corrupt.jpg" "$TMP/out" -s 150kb --format webp >"$TMP/corrupt.log" 2>&1; then exit 1; fi

grep -q '\[UNCHANGED\]' "$TMP/tiny.log"
grep -q '\[BEST EFFORT\]' "$TMP/hard.log"
grep -q '\[ERROR\]' "$TMP/corrupt.log"
test "$(find "$TMP/out" -name 'duplicate*.webp' | wc -l | tr -d ' ')" = 2

ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 -t 5 -c:v libx264 -preset veryfast -crf 12 -c:a aac "$TMP/source.mp4"
"$VIDEO_HELPER" "$TMP/source.mp4" "$TMP/video.mp4" -t 350000 --keep-audio --no-metadata >"$TMP/video.log"
test "$(stat -f%z "$TMP/video.mp4")" -le 350000
ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$TMP/video.mp4" | grep -q mp4
ffmpeg -hide_banner -loglevel error -i "$TMP/source.mp4" -c copy "$TMP/source.mov"
"$VIDEO_HELPER" "$TMP/source.mov" "$TMP/mov-video.mp4" -t 400000 --no-audio --no-metadata >"$TMP/mov-video.log"
test "$(stat -f%z "$TMP/mov-video.mp4")" -le 400000
ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$TMP/mov-video.mp4" | grep -q mp4

"$PYTHON" - "$TMP/out" <<'PY'
from PIL import Image
from pathlib import Path
import sys
out = Path(sys.argv[1])
webp = next(out.glob("photo*.webp")); assert webp.read_bytes()[:4] == b"RIFF" and webp.read_bytes()[8:12] == b"WEBP"
assert not Image.open(webp).getexif()
kept = next(p for p in out.glob("photo*.jpg") if Image.open(p).getexif().get(0x010E)); assert Image.open(kept).getexif().get(0x010E) == "LumaShrink metadata test"
alpha = Image.open(next(out.glob("alpha*.png"))); assert "A" in alpha.getbands() or "transparency" in alpha.info
assert Image.open(next(out.glob("source*.jpg"))).format == "JPEG"
assert any(Image.open(p).format == "JPEG" for p in out.glob("photo*.jpg"))
PY

echo "LumaShrink bundled media matrix: PASS"
