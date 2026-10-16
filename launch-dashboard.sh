#!/usr/bin/env bash
# Launch Nginix Control Panel
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/tmp/nginix-control-panel.log

if [ -x /opt/nginix-control-panel/nginix-control-panel ]; then
  BIN=/opt/nginix-control-panel/nginix-control-panel
elif [ -x "$SCRIPT_DIR/build/linux/x64/release/bundle/nginix-control-panel" ]; then
  BIN="$SCRIPT_DIR/build/linux/x64/release/bundle/nginix-control-panel"
else
  echo "Nginix Control Panel binary not found." >&2
  echo "Build it with: flutter build linux --release" >&2
  exit 1
fi

nohup "$BIN" >"$LOG" 2>&1 &
disown
echo "Nginix Control Panel launched (pid $!) — logs: $LOG"
