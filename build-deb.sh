#!/usr/bin/env bash
# Build a .deb package for Nginix Control Panel from the Flutter release bundle.
# Requires: flutter (to build), dpkg-deb, root for --root-owner-group.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-1.0.0}"
PKG_NAME="server-dashboard"
ARCH="amd64"
OUT_DIR="$REPO_DIR/dist"
BUNDLE="$REPO_DIR/build/linux/x64/release/bundle"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Building Flutter release bundle..."
cd "$REPO_DIR"
flutter build linux --release

echo "==> Assembling package layout..."
PKG="$TMP/pkg"
mkdir -p "$PKG/DEBIAN" \
         "$PKG/opt/server_dashboard/data" \
         "$PKG/opt/server_dashboard/lib" \
         "$PKG/usr/share/applications" \
         "$PKG/usr/share/pixmaps" \
         "$PKG/usr/share/doc/$PKG_NAME" \
         "$PKG/usr/share/icons/hicolor"

cp "$BUNDLE/server_dashboard" "$PKG/opt/server_dashboard/"
cp -r "$BUNDLE/data/." "$PKG/opt/server_dashboard/data/"
cp -r "$BUNDLE/lib/." "$PKG/opt/server_dashboard/lib/"
cp "$REPO_DIR/icon_1024.png" "$PKG/usr/share/pixmaps/server-dashboard.png"

cat > "$PKG/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: itsarmen <itsarmen@users.noreply.github.com>
 Homepage: https://github.com/itsarmen/ubuntu-nginix-control-panel
 Description: Nginix Control Panel
 Flutter-based control panel for the College Examination Platform.
 Manages Nginx, PHP-FPM, MariaDB services, websites, backups,
 configs, terminal diagnostics and network status.
EOF

cat > "$PKG/usr/share/applications/$PKG_NAME.desktop" << 'EOF'
[Desktop Entry]
Name=Nginix Control Panel
Comment=Nginix Control Panel
Exec=/opt/server_dashboard/server_dashboard
Icon=/usr/share/pixmaps/server-dashboard.png
Type=Application
Categories=System;Monitor;
Terminal=false
StartupWMClass=com.example.server_dashboard
EOF

cat > "$PKG/usr/share/doc/$PKG_NAME/copyright" << 'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: server-dashboard
Source: https://github.com/itsarmen/ubuntu-nginix-control-panel
Files: *
Copyright: 2026 itsarmen
 License: Proprietary - All rights reserved
EOF

python3 "$REPO_DIR/make-rounded-icon.py" --icon-dir "$PKG/usr/share/icons/hicolor" >/dev/null

mkdir -p "$OUT_DIR"
echo "==> Building .deb..."
dpkg-deb --build --root-owner-group "$PKG" "$OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo "==> Done: $OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"