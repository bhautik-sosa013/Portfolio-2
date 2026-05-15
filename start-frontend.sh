#!/bin/bash
# Start frontend dev server — reads port from vite.config.ts, kills old process, starts fresh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/frontend-dev.log"
MAX_WAIT=60

# Extract port from vite.config.ts (compatible with macOS + Linux)
PORT=$(grep 'port:' "$SCRIPT_DIR/vite.config.ts" 2>/dev/null | head -1 | sed 's/[^0-9]//g')
if [ -z "$PORT" ]; then
  PORT=8080
fi

echo "==> Frontend start (port $PORT)"

# Kill existing process on this port
pids=$(lsof -ti :"$PORT" 2>/dev/null)
if [ -n "$pids" ]; then
  echo "    Killing PID(s) on port $PORT: $pids"
  echo "$pids" | xargs kill 2>/dev/null
  sleep 2
  pids=$(lsof -ti :"$PORT" 2>/dev/null)
  if [ -n "$pids" ]; then
    echo "    Force killing: $pids"
    echo "$pids" | xargs kill -9 2>/dev/null
    sleep 1
  fi
else
  echo "    Port $PORT is free"
fi

# Kill orphaned vite/esbuild processes from this directory
pkill -f "$SCRIPT_DIR/node_modules/.bin/vite" 2>/dev/null
pkill -f "$SCRIPT_DIR/node_modules/@esbuild" 2>/dev/null
sleep 1

# Install deps if missing
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
  echo "==> Installing dependencies..."
  (cd "$SCRIPT_DIR" && npm install --include=dev)
fi

# Start dev server
echo "==> Starting frontend dev server..."
> "$LOG_FILE"
(cd "$SCRIPT_DIR" && exec npm run dev >> "$LOG_FILE" 2>&1) &
disown

# Wait for port to be ready
echo "==> Waiting for port $PORT..."
elapsed=0
while ! (echo >/dev/tcp/127.0.0.1/"$PORT") 2>/dev/null; do
  if [ $elapsed -ge $MAX_WAIT ]; then
    echo "    TIMEOUT: Frontend did not start within ${MAX_WAIT}s"
    echo "    Check log: $LOG_FILE"
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "    Frontend ready at http://localhost:$PORT (~${elapsed}s)"
echo "==> Done"
