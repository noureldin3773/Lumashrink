#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate

if ! python -c "import PIL, tkinterdnd2" >/dev/null 2>&1; then
  python -m pip install --disable-pip-version-check -i https://pypi.org/simple -r requirements.txt
fi

python compress_image_app.py
