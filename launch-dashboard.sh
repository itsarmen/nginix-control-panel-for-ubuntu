#!/usr/bin/env bash
# Launch Nginix Control Panel
LOG=/tmp/dashboard.log
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec nohup python3 "$SCRIPT_DIR/server-dashboard.py" >"$LOG" 2>&1 &
disown
echo "Dashboard launched (pid $!)"