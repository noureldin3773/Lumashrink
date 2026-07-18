#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="$ROOT/.venv/bin/python"
PORT="${LUMASHRINK_VERIFY_PORT:-8765}"
BASE="http://127.0.0.1:$PORT"
TMP="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing .venv. Run: python3 -m venv .venv && .venv/bin/pip install -r server/requirements.txt"
  exit 1
fi

cd "$ROOT"
"$PYTHON" -m uvicorn server.main:app --host 127.0.0.1 --port "$PORT" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!
for _ in {1..50}; do
  curl -fsS "$BASE/health" >/dev/null 2>&1 && break
  sleep 0.1
done
curl -fsS "$BASE/health" >/dev/null

"$PYTHON" - "$TMP/sample.png" <<'PY'
from PIL import Image
import sys
Image.new("RGB", (1200, 800), (190, 70, 120)).save(sys.argv[1], "PNG")
PY

for route in / /app /privacy /terms /support /health; do
  test "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE$route")" = 200
done

ready_code="$(curl -sS -o "$TMP/ready.json" -w '%{http_code}' "$BASE/health/ready")"
if [[ -n "${LUMASHRINK_CHECKOUT_URL:-}" && -n "${LUMASHRINK_DOWNLOAD_URL:-}" ]]; then
  test "$ready_code" = 200
else
  test "$ready_code" = 503
fi

session="$(curl -fsS -X POST "$BASE/api/session" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')"
curl -fsS -F "files=@$TMP/sample.png;type=image/png" "$BASE/api/session/$session/upload" >/dev/null
test "$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH -H 'Content-Type: application/json' -d '{"max_size":"invalid"}' "$BASE/api/session/$session/settings")" = 422
curl -fsS -X PATCH -H 'Content-Type: application/json' -d '{"max_size":"150kb","output_format":"webp","name_mode":"suffix"}' "$BASE/api/session/$session/settings" >/dev/null
curl -fsS -X POST "$BASE/api/session/$session/compress" >/dev/null

state=queued
for _ in {1..100}; do
  curl -fsS "$BASE/api/session/$session/files" >"$TMP/status.json"
  state="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][0]["status"])' "$TMP/status.json")"
  [[ "$state" =~ ^(done|best_effort|failed|skipped)$ ]] && break
  sleep 0.05
done
[[ "$state" =~ ^(done|best_effort)$ ]]

file_id="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][0]["file_id"])' "$TMP/status.json")"
curl -fsS -D "$TMP/headers" "$BASE/api/session/$session/download/$file_id" -o "$TMP/output"
"$PYTHON" - "$TMP/output" "$TMP/headers" <<'PY'
import sys
data = open(sys.argv[1], "rb").read(12)
assert data[:4] == b"RIFF" and data[8:12] == b"WEBP", data
assert ".webp" in open(sys.argv[2]).read().lower()
PY

curl -fsS -D "$TMP/preview-headers" -F "file=@$TMP/sample.png;type=image/png" -F max_size=150kb -F quality=80 "$BASE/api/preview" -o "$TMP/preview"
grep -qi '^cache-control: no-store' "$TMP/preview-headers"
test "$(curl -sS -o /dev/null -w '%{http_code}' -F "file=@$ROOT/README.md;type=text/plain" "$BASE/api/preview")" = 415
curl -fsS -X DELETE "$BASE/api/session/$session" >/dev/null

command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=640x360:rate=24 -t 3 -c:v libx264 -preset veryfast -crf 12 "$TMP/sample.mp4"
video_session="$(curl -fsS -X POST "$BASE/api/session" | "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["session_id"])')"
curl -fsS -F "files=@$TMP/sample.mp4;type=video/mp4" "$BASE/api/session/$video_session/upload" >/dev/null
curl -fsS -X PATCH -H 'Content-Type: application/json' -d '{"max_size":"300kb","output_format":"webp","name_mode":"suffix"}' "$BASE/api/session/$video_session/settings" >/dev/null
curl -fsS -X POST "$BASE/api/session/$video_session/compress" >/dev/null
video_state=queued
for _ in {1..200}; do
  curl -fsS "$BASE/api/session/$video_session/files" >"$TMP/video-status.json"
  video_state="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][0]["status"])' "$TMP/video-status.json")"
  [[ "$video_state" =~ ^(done|best_effort|failed|skipped)$ ]] && break
  sleep 0.05
done
test "$video_state" = done
video_id="$("$PYTHON" -c 'import json,sys; print(json.load(open(sys.argv[1]))["files"][0]["file_id"])' "$TMP/video-status.json")"
curl -fsS "$BASE/api/session/$video_session/download/$video_id" -o "$TMP/video-output.mp4"
test "$(stat -f%z "$TMP/video-output.mp4")" -le 300000
ffprobe -v error -show_entries format=format_name -of default=nw=1:nk=1 "$TMP/video-output.mp4" | grep -q mp4
curl -fsS -X DELETE "$BASE/api/session/$video_session" >/dev/null

echo "LumaShrink launch smoke test: PASS"
