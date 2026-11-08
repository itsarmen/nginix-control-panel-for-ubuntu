#!/usr/bin/env bash
#
# restore.sh - Rebuild the nginx + MariaDB + phpMyAdmin stack from a bundle
# created by backup-server.sh. This file lives inside the extracted backup.
#
# Usage (on the new device, from the extracted backup directory):
#   sudo ./restore.sh
#
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

for f in config.tar.gz database-all.sql.gz MANIFEST.txt packages.txt; do
  [ -f "${DIR}/${f}" ] || die "Missing ${f}. Extract the backup archive and run restore.sh from inside it."
done

PHP_VER="$(sed -n 's/^php_ver: *//p' "${DIR}/MANIFEST.txt" | head -1)"
PHP_VER="${PHP_VER:-8.5}"
SITE_NAME="$(sed -n 's/^site: *//p' "${DIR}/MANIFEST.txt" | head -1)"
SITE_NAME="${SITE_NAME:-demoweb.local}"

log "Backup source: $(sed -n 's/^source_host: *//p' "${DIR}/MANIFEST.txt" | head -1)"
log "Restoring site '${SITE_NAME}', PHP ${PHP_VER}"

# ---------------------------------------------------------------------------
# 1. Install the same package stack
# ---------------------------------------------------------------------------
log "Installing packages (nginx, MariaDB, PHP ${PHP_VER}, phpMyAdmin)..."
export DEBIAN_FRONTEND=noninteractive
printf '%s\n' \
  "phpmyadmin phpmyadmin/dbconfig-install boolean false" \
  "phpmyadmin phpmyadmin/reconfigure-webserver multiselect" \
  "phpmyadmin phpmyadmin/setup-username string phpmyadmin" \
  | debconf-set-selections || true

apt-get update -y
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends $(grep -v '^#' "${DIR}/packages.txt")

# ---------------------------------------------------------------------------
# 2. Make sure MariaDB is up for the import
# ---------------------------------------------------------------------------
log "Starting MariaDB..."
systemctl stop nginx 2>/dev/null || true
systemctl enable --now mariadb
for _ in $(seq 1 30); do
  [ -S /run/mysqld/mysqld.sock ] && break
  sleep 1
done
[ -S /run/mysqld/mysqld.sock ] || die "MariaDB socket did not appear."

# ---------------------------------------------------------------------------
# 3. Restore configuration and website files
# ---------------------------------------------------------------------------
log "Restoring configuration and website files..."
tar -xzpf "${DIR}/config.tar.gz" -C /

# ---------------------------------------------------------------------------
# 4. Restore databases (users, grants, data, routines, triggers)
# ---------------------------------------------------------------------------
log "Restoring MariaDB databases..."
gunzip -c "${DIR}/database-all.sql.gz" | mariadb --protocol=socket --skip-ssl
ok "Databases restored."

# ---------------------------------------------------------------------------
# 5. Permissions / symlinks
# ---------------------------------------------------------------------------
log "Fixing ownership and permissions..."
chown -R www-data:www-data /var/www 2>/dev/null || true
find /var/www -name '.env' -exec chmod 640 {} \; 2>/dev/null || true
[ -f /etc/nginx/.nginix-htpasswd ] && chown root:www-data /etc/nginx/.nginix-htpasswd && chmod 640 /etc/nginx/.nginix-htpasswd
[ -f /etc/nginx/ssl/server.key ] && chmod 600 /etc/nginx/ssl/server.key
[ -f /etc/mariadb-backup.key ] && chmod 600 /etc/mariadb-backup.key
chmod 700 /usr/local/bin/backup-db.sh /usr/local/bin/restore-db.sh 2>/dev/null || true
chmod 700 /opt/nginix-control-panel /opt/nginix-control-panel/secrets 2>/dev/null || true
chmod 600 /opt/nginix-control-panel/secrets/* 2>/dev/null || true
chmod 600 /root/."${SITE_NAME}"-* 2>/dev/null || true

if [ -d /etc/mysql/certs ]; then
  chown -R mysql:mysql /etc/mysql/certs
  chmod 600 /etc/mysql/certs/server-key.pem 2>/dev/null || true
fi

ln -sf "/etc/nginx/sites-available/${SITE_NAME}" "/etc/nginx/sites-enabled/${SITE_NAME}" 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default

# ---------------------------------------------------------------------------
# 6. Services, validation, firewall, cron
# ---------------------------------------------------------------------------
log "Enabling and restarting services..."
systemctl enable "php${PHP_VER}-fpm"
systemctl restart "php${PHP_VER}-fpm"
systemctl enable mariadb
systemctl restart mariadb

log "Testing nginx configuration..."
nginx -t
systemctl enable nginx
systemctl restart nginx
systemctl enable --now cron 2>/dev/null || warn "Could not enable cron."

if command -v ufw >/dev/null 2>&1; then
  log "Configuring firewall (allowing SSH before enabling)..."
  ufw allow 'Nginx Full' >/dev/null 2>&1 || true
  if ufw app list 2>/dev/null | grep -q '^ *OpenSSH$'; then
    ufw allow OpenSSH >/dev/null 2>&1 || true
  else
    ufw allow 22/tcp >/dev/null 2>&1 || true
  fi
  ufw --force enable >/dev/null 2>&1 || warn "Could not enable UFW."
fi

# Passwordless sudo for the dashboard user who ran this restore (mirrors setup).
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
  log "Granting passwordless sudo to '${SUDO_USER}' for the dashboard..."
  printf '# Passwordless sudo for the Nginix Control Panel desktop user.\n%s ALL=(ALL) NOPASSWD: ALL\n' "${SUDO_USER}" \
    > /etc/sudoers.d/nginix-control-panel
  chmod 440 /etc/sudoers.d/nginix-control-panel
  visudo -cf /etc/sudoers.d/nginix-control-panel >/dev/null 2>&1 \
    || { warn "Invalid sudoers file; removing."; rm -f /etc/sudoers.d/nginix-control-panel; }
fi

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
ok "Restore complete."
echo
echo "  Website        : https://${IP:-<server-ip>}/"
echo "  phpMyAdmin     : https://${IP:-<server-ip>}/phpmyadmin"
if [ -f /etc/nginx/phpmyadmin-gate.json ]; then
  echo "  phpMyAdmin login: $(sed -n 's/.*"user": *"\([^"]*\)".*/\1/p' /etc/nginx/phpmyadmin-gate.json) / $(sed -n 's/.*"password": *"\([^"]*\)".*/\1/p' /etc/nginx/phpmyadmin-gate.json)"
fi
if [ -f "/root/.${SITE_NAME}-db-credentials" ]; then
  echo "  DB credentials  : /root/.${SITE_NAME}-db-credentials"
fi
echo "  Encrypted DB backups: /var/backups/mariadb"
echo
warn "If the new device uses a different hostname/IP, update server_name in /etc/nginx/sites-available/${SITE_NAME} if needed."
