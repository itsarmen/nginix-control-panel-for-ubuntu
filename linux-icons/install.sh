#!/bin/sh
# Installs the app icon and desktop entry for the current user (no root needed).
#
# On Wayland/GNOME the dock icon is resolved from a .desktop file whose name
# matches the application id (com.nginix.controlpanel), so we install it here.
set -e
cd "$(dirname "$0")"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
ICON_DIR="$DATA_HOME/icons"
APPS_DIR="$DATA_HOME/applications"

# Resolve the binary to launch: explicit arg > /opt install > local bundle.
if [ -n "${1:-}" ]; then
  BIN="$1"
elif [ -x /opt/nginix-control-panel/nginix-control-panel ]; then
  BIN=/opt/nginix-control-panel/nginix-control-panel
elif [ -x "$PWD/../build/linux/x64/release/bundle/nginix-control-panel" ]; then
  BIN="$PWD/../build/linux/x64/release/bundle/nginix-control-panel"
else
  echo "Could not find the nginix-control-panel binary." >&2
  echo "Usage: $0 [/path/to/nginix-control-panel]" >&2
  exit 1
fi
BIN="$(readlink -f "$BIN")"

mkdir -p "$ICON_DIR" "$APPS_DIR"
cp -r hicolor "$ICON_DIR/"
gtk-update-icon-cache -f -t "$ICON_DIR/hicolor" 2>/dev/null || true

sed "s|^Exec=.*|Exec=\"$BIN\"|" com.nginix.controlpanel.desktop \
  > "$APPS_DIR/com.nginix.controlpanel.desktop"
update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo "Installed desktop entry: $APPS_DIR/com.nginix.controlpanel.desktop"
echo "  Exec=$BIN"
echo "Installed icons: $ICON_DIR/hicolor"
