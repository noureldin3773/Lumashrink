#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"

DESKTOP_APP_PATH="$HOME/Desktop/Image Compressor.app"

echo "Building latest Swift desktop app from current repo..."
"$PWD/create_desktop_launcher.sh"

if [ -d "$DESKTOP_APP_PATH" ]; then
  echo "Launching: $DESKTOP_APP_PATH"
  open "$DESKTOP_APP_PATH"
  exit 0
fi

echo "Desktop app build not found. Falling back to Python UI launcher."
if [ ! -d ".venv" ]; then
  /usr/bin/python3 -m venv .venv
fi
source .venv/bin/activate
if ! python -c "import PIL, tkinterdnd2" >/dev/null 2>&1; then
  python -m pip install --disable-pip-version-check -i https://pypi.org/simple -r requirements.txt
fi
python compress_image_app.py
