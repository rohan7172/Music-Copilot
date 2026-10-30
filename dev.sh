#!/usr/bin/env bash
# Starts everything for local development with one command:
#   - the backend (installing/updating its Python packages when needed),
#   - the Flutter web app on http://localhost:8080, opened in your browser.
# Ctrl+C stops both. Backend output goes to .dev/backend.log.
#
# Usage: ./dev.sh
# Set NO_BROWSER=1 to skip opening the browser.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKEND_PORT=8000
APP_PORT=8080
LOG_DIR="$ROOT/.dev"
BACKEND_LOG="$LOG_DIR/backend.log"

BACKEND_PID=""
OPENER_PID=""

say() { printf '\033[1m▸ %s\033[0m\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

cleanup() {
  trap - EXIT INT TERM
  [ -n "$OPENER_PID" ] && kill "$OPENER_PID" 2>/dev/null || true
  if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
    say "Stopping backend"
    kill "$BACKEND_PID" 2>/dev/null || true
    wait "$BACKEND_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Frees $1 (a port) if what's listening there is one of our own leftover
# servers (its command line matches $2). Anything else is left alone.
free_port() {
  local port="$1" pattern="$2" name="$3" pids pid cmd ours=""
  pids="$(lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  [ -z "${pids// /}" ] && return 0
  for pid in $pids; do
    cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if printf '%s' "$cmd" | grep -Eq "$pattern"; then
      ours="$ours $pid"
    fi
  done
  if [ -z "$ours" ]; then
    fail "Port $port is in use by something else (PID ${pids% }). Stop it and try again."
  fi
  say "Stopping a leftover $name on port $port"
  # shellcheck disable=SC2086 # one argument per PID
  kill $ours 2>/dev/null || true
  for _ in $(seq 1 20); do
    lsof -nP -t -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 || return 0
    sleep 0.25
  done
  fail "Couldn't free port $port. Stop PID(s)$ours and try again."
}

command -v lsof >/dev/null || fail "lsof is needed to check ports."
command -v curl >/dev/null || fail "curl is needed to check the backend."
command -v flutter >/dev/null || fail "flutter isn't on your PATH."

# --- Backend ----------------------------------------------------------------

cd "$ROOT/backend"
if [ ! -x venv/bin/python ]; then
  command -v python3.11 >/dev/null || fail "python3.11 not found (on a Mac: brew install python@3.11)."
  say "Creating the backend's Python environment"
  python3.11 -m venv venv
fi
# Reinstall only when requirements.txt changed since the last install.
if ! cmp -s requirements.txt venv/.requirements.installed; then
  say "Installing backend packages (first run or requirements changed)"
  venv/bin/pip install -q -r requirements.txt
  cp requirements.txt venv/.requirements.installed
fi

# Check both ports before starting anything.
free_port "$BACKEND_PORT" "uvicorn app\.main:app" "backend"
free_port "$APP_PORT" "flutter_tools.*web-server" "app server"
mkdir -p "$LOG_DIR"
say "Starting backend (log: .dev/backend.log)"
(exec venv/bin/uvicorn app.main:app --reload --port "$BACKEND_PORT") >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

printf 'Waiting for the backend to load the model'
for i in $(seq 1 360); do
  if curl -s -m 1 "http://127.0.0.1:$BACKEND_PORT/health" >/dev/null 2>&1; then
    printf '\n'
    break
  fi
  if ! kill -0 "$BACKEND_PID" 2>/dev/null || [ "$i" -eq 360 ]; then
    printf '\n'
    tail -n 25 "$BACKEND_LOG" >&2
    fail "The backend didn't start. Full log: .dev/backend.log"
  fi
  [ $((i % 4)) -eq 0 ] && printf '.'
  sleep 0.5
done
say "Backend ready on http://127.0.0.1:$BACKEND_PORT"

# --- App --------------------------------------------------------------------

cd "$ROOT/app"
flutter pub get >/dev/null

if [ -z "${NO_BROWSER:-}" ]; then
  # Open the browser once the app is actually being served.
  (
    for _ in $(seq 1 360); do
      if curl -s -m 1 -o /dev/null "http://localhost:$APP_PORT/"; then
        if command -v open >/dev/null; then
          open "http://localhost:$APP_PORT"
        elif command -v xdg-open >/dev/null; then
          xdg-open "http://localhost:$APP_PORT" >/dev/null 2>&1
        fi
        exit 0
      fi
      sleep 0.5
    done
  ) &
  OPENER_PID=$!
fi

say "Starting the app on http://localhost:$APP_PORT  (r = reload, R = restart, Ctrl+C = stop everything)"
flutter run -d web-server --web-port "$APP_PORT"
