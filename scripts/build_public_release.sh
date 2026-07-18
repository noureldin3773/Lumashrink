#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/.env" ]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

require_value() {
  local name="$1"
  local value="${(P)name:-}"
  if [ -z "$value" ]; then
    echo "Missing required environment variable: $name"
    exit 1
  fi
}

for name in \
  LUMASHRINK_CHECKOUT_URL \
  LUMASHRINK_DOWNLOAD_URL \
  LUMASHRINK_SIGNING_IDENTITY \
  LUMASHRINK_NOTARY_PROFILE; do
  require_value "$name"
done

for url in "$LUMASHRINK_CHECKOUT_URL" "$LUMASHRINK_DOWNLOAD_URL"; do
  if [[ "$url" != https://* ]] || [[ "$url" == *example.com* ]]; then
    echo "Public checkout and download URLs must be real HTTPS URLs: $url"
    exit 1
  fi
done

if [[ "$LUMASHRINK_SIGNING_IDENTITY" != *"Developer ID Application"* ]]; then
  echo "Signing identity must be a Developer ID Application certificate."
  exit 1
fi
security find-identity -v -p codesigning | grep -F "$LUMASHRINK_SIGNING_IDENTITY" >/dev/null
xcrun notarytool history --keychain-profile "$LUMASHRINK_NOTARY_PROFILE" >/dev/null

if ! dig +short lumashrink.app A | grep -q . && ! dig +short lumashrink.app AAAA | grep -q .; then
  echo "lumashrink.app has no A or AAAA record. Configure production DNS first."
  exit 1
fi
if ! dig +short lumashrink.app MX | grep -q .; then
  echo "lumashrink.app has no MX record. Configure support@lumashrink.app first."
  exit 1
fi

export LUMASHRINK_PUBLIC_RELEASE=1
cd "$ROOT"
./create_desktop_launcher.sh
./scripts/verify_launch.sh
./scripts/verify_release_media.sh

echo "Public release verification: PASS"
echo "Artifact: $ROOT/dist/LumaShrink-macOS.zip"
cat "$ROOT/dist/LumaShrink-macOS.zip.sha256"
