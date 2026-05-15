#!/bin/bash
# Stop frontend dev server

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=$(grep 'port:' "$SCRIPT_DIR/vite.config.ts" 2>/dev/null | head -1 | sed 's/[^0-9]//g')
if [ -z "$PORT" ]; then PORT=8080; fi

pids=$(lsof -ti :"$PORT" 2>/dev/null)
if [ -n "$pids" ]; then
  echo "$pids" | xargs kill 2>/dev/null
  echo "Stopped frontend on port $PORT"
else
  echo "Frontend not running on port $PORT"
fi
pkill -f "$SCRIPT_DIR/node_modules/.bin/vite" 2>/dev/null
pkill -f "$SCRIPT_DIR/node_modules/@esbuild" 2>/dev/null
