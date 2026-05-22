#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Compatibility wrapper from the copied project. Keep one canonical Desktop app.
"$PROJECT_DIR/create_desktop_launcher.sh"
