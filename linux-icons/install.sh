#!/bin/sh
# Installs the icon for the current user (no root needed)
set -e
cd "$(dirname "$0")"
cp -r hicolor "${XDG_DATA_HOME:-$HOME/.local/share}/icons/"
gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
echo "Installed. Use Icon=app-icon in your .desktop file."
