#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_DIR="$HOME/Desktop"
APP_NAME="LumaShrink.app"
APP_PATH="$DESKTOP_DIR/$APP_NAME"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"
SIGNING_IDENTITY="${LUMASHRINK_SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${LUMASHRINK_NOTARY_PROFILE:-}"
PUBLIC_RELEASE="${LUMASHRINK_PUBLIC_RELEASE:-0}"
ICONSET_DIR="$PROJECT_DIR/icon.iconset"
ICON_SOURCE="$PROJECT_DIR/icon_source.svg"
BASE_PNG="$PROJECT_DIR/.icon_base.png"
BUILD_DIR="$(mktemp -d)"
TEMP_APP_PATH="$BUILD_DIR/$APP_NAME"
RUNTIME_DIR="$TEMP_APP_PATH/Contents/Resources/runtime"
EXECUTABLE_NAME="LumaShrink"
BINARY_PATH="$TEMP_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
VENV_SOURCE="$PROJECT_DIR/.venv"
PYINSTALLER="$VENV_SOURCE/bin/pyinstaller"
HELPER_DIST="$BUILD_DIR/helpers"
HELPER_WORK="$BUILD_DIR/pyinstaller"

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

qlmanage -t -s 1024 -o "$PROJECT_DIR" "$ICON_SOURCE" >/dev/null 2>&1
mv "$PROJECT_DIR/$(basename "$ICON_SOURCE").png" "$BASE_PNG"

cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$PROJECT_DIR/icon.icns"

rm -rf "$TEMP_APP_PATH"
mkdir -p "$TEMP_APP_PATH/Contents/MacOS" "$TEMP_APP_PATH/Contents/Resources" "$RUNTIME_DIR"

cp "$PROJECT_DIR/compress_image.py" "$RUNTIME_DIR/compress_image.py"
cp "$PROJECT_DIR/compress_video.py" "$RUNTIME_DIR/compress_video.py"
if [ ! -x "$PYINSTALLER" ]; then
  echo "Missing build dependency: PyInstaller"
  echo "Run: $VENV_SOURCE/bin/python -m pip install -r $PROJECT_DIR/requirements-build.txt"
  exit 1
fi

"$PYINSTALLER" --onedir --clean --noconfirm \
  --name lumashrink-image-helper \
  --distpath "$HELPER_DIST" \
  --workpath "$HELPER_WORK/image" \
  --specpath "$BUILD_DIR" \
  "$PROJECT_DIR/compress_image.py" >/dev/null 2>&1

"$PYINSTALLER" --onedir --clean --noconfirm \
  --name lumashrink-video-helper \
  --distpath "$HELPER_DIST" \
  --workpath "$HELPER_WORK/video" \
  --specpath "$BUILD_DIR" \
  "$PROJECT_DIR/compress_video.py" >/dev/null 2>&1

cp -R "$HELPER_DIST/lumashrink-image-helper" "$RUNTIME_DIR/lumashrink-image-helper"
cp -R "$HELPER_DIST/lumashrink-video-helper" "$RUNTIME_DIR/lumashrink-video-helper"
cp "$PROJECT_DIR/icon.icns" "$TEMP_APP_PATH/Contents/Resources/applet.icns"

swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  "$PROJECT_DIR/ImageCompressorNative.swift" \
  -o "$BINARY_PATH"

cat > "$TEMP_APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>LumaShrink</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>applet</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.lumashrink.desktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LumaShrink</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Media</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.image</string>
        <string>public.movie</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
EOF

chmod +x "$BINARY_PATH"
if [ "$PUBLIC_RELEASE" = "1" ] && [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "Public release requires LUMASHRINK_SIGNING_IDENTITY to name a Developer ID Application certificate."
  exit 1
fi

if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$TEMP_APP_PATH" >/dev/null
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$TEMP_APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$TEMP_APP_PATH"

rm -rf "$APP_PATH"
mv "$TEMP_APP_PATH" "$APP_PATH"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR/LumaShrink-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/LumaShrink-macOS.zip"

if [ "$PUBLIC_RELEASE" = "1" ]; then
  if [ -z "$NOTARY_PROFILE" ]; then
    echo "Public release requires LUMASHRINK_NOTARY_PROFILE."
    exit 1
  fi
  xcrun notarytool submit "$DIST_DIR/LumaShrink-macOS.zip" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$DIST_DIR/LumaShrink-macOS.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$DIST_DIR/LumaShrink-macOS.zip"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

shasum -a 256 "$DIST_DIR/LumaShrink-macOS.zip" > "$DIST_DIR/LumaShrink-macOS.zip.sha256"

rm -rf "$ICONSET_DIR" "$BASE_PNG" "$BUILD_DIR"

echo "Created desktop launcher: $APP_PATH"
echo "Created release archive: $DIST_DIR/LumaShrink-macOS.zip"
if [ "$PUBLIC_RELEASE" = "1" ]; then
  echo "Created Developer ID signed, notarized, and stapled public release."
else
  echo "Release note: this local build is ad-hoc signed. Set LUMASHRINK_PUBLIC_RELEASE=1 with signing and notarization variables for public distribution."
fi
