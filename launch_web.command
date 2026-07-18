#!/bin/zsh
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/.env" ]; then
  set -a
  source "$DIR/.env"
  set +a
fi
cd "$DIR/server"
VENV_PY="$DIR/.venv/bin/python"
echo "Starting LumaShrink web server..."
"$VENV_PY" main.py &
SERVER_PID=$!
sleep 2
open http://localhost:8000
echo "Landing page: http://localhost:8000"
echo "App tool:     http://localhost:8000/app"
echo ""
echo "Press Ctrl+C to stop the server."
wait $SERVER_PID
