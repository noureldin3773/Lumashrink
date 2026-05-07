#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_DIR="$HOME/Desktop"
APP_NAME="Image Compressor.app"
APP_PATH="$DESKTOP_DIR/$APP_NAME"
ICONSET_DIR="$PROJECT_DIR/icon.iconset"
ICON_SOURCE="$PROJECT_DIR/icon_source.svg"
BASE_PNG="$PROJECT_DIR/.icon_base.png"
BUILD_DIR="$(mktemp -d)"
TEMP_APP_PATH="$BUILD_DIR/$APP_NAME"
RUNTIME_DIR="$TEMP_APP_PATH/Contents/Resources/runtime"
EXECUTABLE_NAME="Image Compressor"
BINARY_PATH="$TEMP_APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
VENV_SOURCE="$PROJECT_DIR/.venv"
RUNTIME_VENV_DIR="$RUNTIME_DIR/.venv"

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

rm -rf "$APP_PATH" "$TEMP_APP_PATH"
mkdir -p "$TEMP_APP_PATH/Contents/MacOS" "$TEMP_APP_PATH/Contents/Resources" "$RUNTIME_DIR"

cp "$PROJECT_DIR/compress_image.py" "$RUNTIME_DIR/compress_image.py"
cp "$PROJECT_DIR/compress_video.py" "$RUNTIME_DIR/compress_video.py"
if [ -d "$VENV_SOURCE" ]; then
  cp -R "$VENV_SOURCE" "$RUNTIME_VENV_DIR"
fi
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
  <string>Image Compressor</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>applet</string>
  <key>CFBundleIdentifier</key>
  <string>local.codex.image-compressor</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Image Compressor</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0</string>
  <key>CFBundleVersion</key>
  <string>2</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

chmod +x "$BINARY_PATH"
codesign --force --deep --sign - "$TEMP_APP_PATH" >/dev/null 2>&1 || true

mv "$TEMP_APP_PATH" "$APP_PATH"

rm -rf "$ICONSET_DIR" "$BASE_PNG" "$BUILD_DIR"

echo "Created desktop launcher: $APP_PATH"
