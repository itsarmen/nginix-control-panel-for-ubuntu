#!/usr/bin/env bash
#
# backup-server.sh - Create a portable, self-contained backup of the
# nginx + MariaDB (+ phpMyAdmin) stack provisioned by setup-server.sh.
#
# The produced archive contains:
#   * all nginx config, TLS certs, htpasswd gate, websites.json
#   * all website files (/var/www)
#   * MariaDB config + a full logical dump of every database (incl. users)
#   * PHP / PHP-FPM and phpMyAdmin config
#   * the encrypted-backup key + existing encrypted DB backups
#   * cron jobs, UFW rules, backup/restore scripts, credentials, dashboard app
#   * restore.sh - run it on the new device to rebuild everything
#
# Usage:
#   sudo ./backup-server.sh                 # writes ./backups/nginix-backup-<stamp>.tar.gz
#   sudo OUTDIR=/mnt/usb ./backup-server.sh
#   sudo BACKUP_PASSPHRASE='secret' ./backup-server.sh   # encrypt the final archive
#
set -euo pipefail

# Re-exec with sudo if needed so all privileged files can be read.
if [ "${EUID}" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="${OUTDIR:-${SCRIPT_DIR}/backups}"
NAME="nginix-backup-${STAMP}"
WORK="${OUTDIR}/${NAME}"
SITE_NAME="${SITE_NAME:-demoweb.local}"
PHP_VER="$(ls -1 /etc/php 2>/dev/null | sort -V | tail -1 || true)"
PHP_VER="${PHP_VER:-8.5}"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "${SCRIPT_DIR}/restore-server.sh" ] || die "restore-server.sh not found next to this script."
command -v mariadb-dump >/dev/null 2>&1 || die "mariadb-dump not found."

mkdir -p "$WORK"
chmod 700 "$OUTDIR" "$WORK"

# ---------------------------------------------------------------------------
# Collect the paths that make up the setup
# ---------------------------------------------------------------------------
PATHS=(
  etc/nginx
  etc/mysql
  etc/php
  etc/phpmyadmin
  etc/mariadb-backup.key
  etc/cron.d/mariadb-backup
  var/www
  var/lib/phpmyadmin
  var/backups/mariadb
  usr/local/bin/backup-db.sh
  usr/local/bin/restore-db.sh
  opt/nginix-control-panel
)

for p in \
  etc/ufw/user.rules \
  etc/ufw/user6.rules \
  etc/letsencrypt \
  usr/share/applications/com.nginix.controlpanel.desktop \
  usr/share/pixmaps/nginix-control-panel.png \
  "root/.${SITE_NAME}-db-credentials" \
  "root/.${SITE_NAME}-phpmyadmin-credentials" \
  "root/${SITE_NAME}-setup-summary.txt"; do
  [ -e "/${p}" ] && PATHS+=("$p")
done

# ---------------------------------------------------------------------------
# Metadata + package list
# ---------------------------------------------------------------------------
log "Writing manifest and package list..."
{
  echo "format: nginix-server-backup/1"
  echo "created: $(date -Is)"
  echo "source_host: $(hostname)"
  echo "source_os: $(. /etc/os-release && echo "${PRETTY_NAME}")"
  echo "site: ${SITE_NAME}"
  echo "php_ver: ${PHP_VER}"
  echo "nginx: $(nginx -v 2>&1)"
  echo "mariadb: $(mariadb --version 2>/dev/null | head -1)"
  echo "web_root: /var/www/websites/${SITE_NAME}"
} > "${WORK}/MANIFEST.txt"

cat > "${WORK}/packages.txt" <<EOF
nginx
mariadb-server
php${PHP_VER}-fpm
php${PHP_VER}-cli
php${PHP_VER}-mysql
php${PHP_VER}-curl
php${PHP_VER}-mbstring
php${PHP_VER}-xml
php${PHP_VER}-gd
php${PHP_VER}-zip
phpmyadmin
openssl
ufw
ca-certificates
xdg-utils
iproute2
procps
network-manager
EOF

# ---------------------------------------------------------------------------
# Config + data archive (paths relative to /)
# ---------------------------------------------------------------------------
log "Archiving configuration and website files..."
tar -czpf "${WORK}/config.tar.gz" -C / "${PATHS[@]}"

# ---------------------------------------------------------------------------
# Full MariaDB logical dump (all databases, users, routines, triggers)
# ---------------------------------------------------------------------------
log "Dumping MariaDB (all databases)..."
mariadb-dump \
  --protocol=socket --skip-ssl \
  --all-databases --single-transaction --quick \
  --routines --events --triggers --default-character-set=utf8mb4 \
  | gzip -9 > "${WORK}/database-all.sql.gz"
ok "Database dump: $(du -h "${WORK}/database-all.sql.gz" | cut -f1)"

# ---------------------------------------------------------------------------
# Ship the scripts needed on the target device
# ---------------------------------------------------------------------------
install -m 700 "${SCRIPT_DIR}/restore-server.sh" "${WORK}/restore.sh"
install -m 700 "${SCRIPT_DIR}/backup-server.sh"  "${WORK}/backup.sh"

# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------
log "Computing checksums..."
( cd "$WORK" && sha256sum config.tar.gz database-all.sql.gz packages.txt MANIFEST.txt > SHA256SUMS )

# ---------------------------------------------------------------------------
# Build the final archive
# ---------------------------------------------------------------------------
log "Creating final archive..."
ARCHIVE="${OUTDIR}/${NAME}.tar.gz"
tar -czpf "$ARCHIVE" -C "$OUTDIR" "$NAME"
chmod 600 "$ARCHIVE"

if [ -n "${BACKUP_PASSPHRASE:-}" ]; then
  log "Encrypting archive with AES-256-CBC..."
  openssl enc -aes-256-cbc -salt -pbkdf2 -pass "env:BACKUP_PASSPHRASE" \
    -in "$ARCHIVE" -out "${ARCHIVE}.enc"
  chmod 600 "${ARCHIVE}.enc"
  shred -u "$ARCHIVE"
  ARCHIVE="${ARCHIVE}.enc"
fi

rm -rf "$WORK"

# Hand the result back to the desktop user who ran sudo (keeps 600 perms).
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
  chown "${SUDO_USER}:$(id -gn "${SUDO_USER}")" "$OUTDIR" "$ARCHIVE" 2>/dev/null || true
fi

ok "Backup complete: ${ARCHIVE}"
echo
echo "Copy that file to the new device, then:"
if [ "${ARCHIVE%.enc}" != "$ARCHIVE" ]; then
  echo "  openssl enc -d -aes-256-cbc -pbkdf2 -in $(basename "$ARCHIVE") -out ${NAME}.tar.gz"
  echo "  tar -xzf ${NAME}.tar.gz"
else
  echo "  tar -xzf $(basename "$ARCHIVE")"
fi
echo "  cd ${NAME}"
echo "  sudo ./restore.sh"
echo
warn "The archive contains secrets (DB dump, TLS private key, passwords). Keep it private."
