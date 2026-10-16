#!/usr/bin/env bash
#
# setup-server.sh - Provision the Nginix Control Panel stack on Ubuntu.
#
# Replaces the old Apache + MySQL ("xampp-ish") stack with:
#   nginx + php8.5-fpm + MariaDB + phpMyAdmin + self-signed TLS
# and creates the "demoweb.local" site exactly the way the dashboard expects:
#
#   /etc/nginx/sites-available/demoweb.local       nginx vhost
#   /var/www/websites/demoweb.local                document root + .env
#   /etc/nginx/websites.json                       website list for the app
#   /etc/nginx/ssl/server.{crt,key}                TLS cert the app reads
#   /var/log/nginx/demoweb.local-error.log         log opened by the app
#   /var/backups/mariadb/*.enc                     AES-256-CBC DB backups
#   /usr/local/bin/backup-db.sh                    backup script
#   /var/log/backup-db.log                         backup log
#   /etc/mariadb-backup.key                        AES-256 backup passphrase
#
# Run with:  sudo ./setup-server.sh            (asks for confirmation)
#            sudo ./setup-server.sh --yes      (non-interactive)
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
SITE_NAME="${SITE_NAME:-demoweb.local}"
SITE_ROOT="${SITE_ROOT:-/var/www/websites/${SITE_NAME}}"
PHP_VER="${PHP_VER:-8.5}"
PHP_SOCK="/run/php/php${PHP_VER}-fpm.sock"
DB_NAME="${DB_NAME:-demoweb}"
DB_USER="${DB_USER:-demoweb}"
DB_PASS="${DB_PASS:-}"
SSL_DIR="/etc/nginx/ssl"
NGINX_AVAIL="/etc/nginx/sites-available/${SITE_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
WEBSITES_JSON="/etc/nginx/websites.json"
# Legacy names from the original exams-platform deployment (cleaned up automatically)
LEGACY_SITE="exams-platform"
LEGACY_DB="exams_platform"
LEGACY_DB_USER="exams"
BACKUP_DIR="/var/backups/mariadb"
BACKUP_KEY="/etc/mariadb-backup.key"
BACKUP_SCRIPT="/usr/local/bin/backup-db.sh"
BACKUP_LOG="/var/log/backup-db.log"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
APP_DIR="${APP_DIR:-/opt/server_dashboard}"
APP_SECRETS="${APP_SECRETS:-${APP_DIR}/secrets}"
APACHE_BACKUP="/root/pre-nginx-setup-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

ASSUME_YES=0
KEEP_DEVROW=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --keep-devrow) KEEP_DEVROW=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  read -rp "$1 [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo $0"

. /etc/os-release 2>/dev/null || true
[ "${ID:-}" = "ubuntu" ] || warn "This script targets Ubuntu; '${ID:-unknown}' detected. Continuing anyway."

export DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------------
# 0. Confirmation
# ----------------------------------------------------------------------------
cat <<EOF
This will:
  * STOP and PURGE the existing Apache2 web server
  * PURGE MySQL server and install MariaDB instead
  * REMOVE /var/www/devrow and the old Apache vhosts/config
  * Install & configure nginx, php${PHP_VER}-fpm, phpMyAdmin, MariaDB
  * Create the '${SITE_NAME}' site and a self-signed TLS certificate
  * Create the encrypted DB backup script + weekly cron job

A backup of /var/www/devrow will be saved to:
  ${APACHE_BACKUP}
EOF
confirm "Proceed with the full setup?" || die "Aborted."

# ----------------------------------------------------------------------------
# 1. Back up anything worth keeping
# ----------------------------------------------------------------------------
if [ -d /var/www/devrow ]; then
  log "Backing up /var/www/devrow -> ${APACHE_BACKUP}"
  tar -czf "$APACHE_BACKUP" -C /var/www devrow || warn "Backup failed; continuing."
fi

# ----------------------------------------------------------------------------
# 2. Remove the old Apache / MySQL stack
# ----------------------------------------------------------------------------
log "Stopping and removing Apache2..."
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true
apt-get purge -y 'apache2*' 'libapache2-mod-php*' >/dev/null 2>&1 || true
rm -rf /etc/apache2 /var/log/apache2 /var/www/html 2>/dev/null || true

log "Removing MySQL server..."
systemctl stop mysql 2>/dev/null || true
apt-get purge -y 'mysql-server*' 'mysql-client*' 'mysql-common' >/dev/null 2>&1 || true
rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null || true

if [ "$KEEP_DEVROW" -eq 1 ]; then
  warn "Keeping /var/www/devrow (--keep-devrow)."
else
  log "Removing old /var/www/devrow web root..."
  rm -rf /var/www/devrow
fi

# Remove artifacts from the original 'exams-platform' deployment.
if [ "$SITE_NAME" != "$LEGACY_SITE" ]; then
  log "Removing legacy '${LEGACY_SITE}' site artifacts..."
  rm -f "/etc/nginx/sites-available/${LEGACY_SITE}" "/etc/nginx/sites-enabled/${LEGACY_SITE}"
  rm -rf "/var/www/websites/${LEGACY_SITE}"
fi

apt-get autoremove -y >/dev/null 2>&1 || true

# ----------------------------------------------------------------------------
# 3. Install the new stack
# ----------------------------------------------------------------------------
log "Updating package lists..."
if ! apt-get update -y >/dev/null 2>&1; then
  warn "apt-get update reported errors (see 'apt-get update'). Continuing anyway."
fi

log "Preseeding phpMyAdmin (no dbconfig prompts)..."
echo "phpmyadmin phpmyadmin/dbconfig-install boolean false"        | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect"    | debconf-set-selections
echo "phpmyadmin phpmyadmin/setup-username string"                | debconf-set-selections 2>/dev/null || true

log "Installing nginx, php${PHP_VER}-fpm, MariaDB, phpMyAdmin..."
apt-get install -y --no-install-recommends \
  nginx \
  mariadb-server \
  "php${PHP_VER}-fpm" "php${PHP_VER}-cli" "php${PHP_VER}-mysql" \
  "php${PHP_VER}-curl" "php${PHP_VER}-mbstring" "php${PHP_VER}-xml" \
  "php${PHP_VER}-gd" "php${PHP_VER}-zip" \
  phpmyadmin openssl ufw ca-certificates >/dev/null

# ----------------------------------------------------------------------------
# 4. Self-signed TLS certificate (what the app reads at /etc/nginx/ssl)
# ----------------------------------------------------------------------------
log "Generating self-signed TLS certificate..."
mkdir -p "$SSL_DIR"
HOST_IP="$(hostname -I | awk '{print $1}')"
if [ ! -f "${SSL_DIR}/server.crt" ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "${SSL_DIR}/server.key" \
    -out    "${SSL_DIR}/server.crt" \
    -subj   "/C=NA/ST=NA/L=NA/O=Nginix Control Panel/CN=${SITE_NAME}" \
    -addext "subjectAltName=IP:${HOST_IP:-127.0.0.1},DNS:${SITE_NAME},DNS:localhost" \
    >/dev/null 2>&1
  chmod 600 "${SSL_DIR}/server.key"
fi

# ----------------------------------------------------------------------------
# 5. Site document root + placeholder + .env
# ----------------------------------------------------------------------------
log "Creating document root ${SITE_ROOT}..."
mkdir -p "$SITE_ROOT"
if [ ! -f "${SITE_ROOT}/index.php" ]; then
  cat > "${SITE_ROOT}/index.php" <<PHP
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Nginix Control Panel</title>
  <style>
    body{font-family:system-ui,sans-serif;background:#1c1c1c;color:#eee;
         display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
    .card{background:#2b2b2b;padding:2.5rem 3rem;border-radius:14px;text-align:center;
          box-shadow:0 8px 30px rgba(0,0,0,.5)}
    code{background:#111;padding:.15rem .4rem;border-radius:5px}
  </style>
</head>
<body>
  <div class="card">
    <h1>Nginix Control Panel</h1>
    <p>The <code>${SITE_NAME}</code> site is up and running.</p>
    <p>PHP <?= htmlspecialchars(PHP_VERSION) ?> &middot; nginx</p>
    <p><a style="color:#7ab7ff" href="/phpmyadmin">Open phpMyAdmin</a></p>
  </div>
</body>
</html>
PHP
fi
chown -R www-data:www-data "$SITE_ROOT"

# ----------------------------------------------------------------------------
# 6. nginx virtual host
# ----------------------------------------------------------------------------
log "Writing nginx config ${NGINX_AVAIL}..."
cat > "$NGINX_AVAIL" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${SITE_NAME} _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    http2 on;
    server_name ${SITE_NAME} _;

    root ${SITE_ROOT};
    index index.php index.html;

    ssl_certificate     ${SSL_DIR}/server.crt;
    ssl_certificate_key ${SSL_DIR}/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/${SITE_NAME}-access.log;
    error_log  /var/log/nginx/${SITE_NAME}-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location /phpmyadmin {
        root /usr/share/;
        index index.php index.html;
        location ~ ^/phpmyadmin/(.+\.php)\$ {
            root /usr/share/;
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:${PHP_SOCK};
        }
        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))\$ {
            root /usr/share/;
        }
    }

    location ~ /\.ht { deny all; }
}
EOF

ln -sf "$NGINX_AVAIL" "$NGINX_ENABLED"
rm -f /etc/nginx/sites-enabled/default

# ----------------------------------------------------------------------------
# 6b. Website list consumed by the app (/etc/nginx/websites.json)
# ----------------------------------------------------------------------------
log "Writing website list ${WEBSITES_JSON}..."
cat > "$WEBSITES_JSON" <<EOF
{
  "websites": [
    {
      "name": "${SITE_NAME}",
      "url": "https://{serverIp}/",
      "root": "${SITE_ROOT}",
      "config": "${NGINX_AVAIL}",
      "description": "Public demo website"
    },
    {
      "name": "phpMyAdmin",
      "url": "https://{serverIp}/phpmyadmin",
      "root": "/usr/share/phpmyadmin",
      "config": "${NGINX_AVAIL}",
      "description": "Database administration"
    }
  ]
}
EOF
chmod 644 "$WEBSITES_JSON"

# ----------------------------------------------------------------------------
# 7. phpMyAdmin config (blowfish secret)
# ----------------------------------------------------------------------------
log "Configuring phpMyAdmin..."
mkdir -p /etc/phpmyadmin/conf.d
if [ ! -f /etc/phpmyadmin/conf.d/99-local.php ]; then
  BLOWFISH="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-32)"
  cat > /etc/phpmyadmin/conf.d/99-local.php <<EOF
<?php
\$cfg['blowfish_secret'] = '${BLOWFISH}';
\$cfg['Servers'][1]['auth_type'] = 'cookie';
\$cfg['Servers'][1]['host'] = 'localhost';
\$cfg['Servers'][1]['compress'] = false;
\$cfg['Servers'][1]['AllowNoPassword'] = false;
EOF
fi

# ----------------------------------------------------------------------------
# 8. MariaDB: database, user, .env
# ----------------------------------------------------------------------------
log "Enabling MariaDB..."
systemctl enable --now mariadb
# wait for the socket to come up
for _ in $(seq 1 30); do
  [ -S /run/mysqld/mysqld.sock ] && break
  sleep 1
done

if [ -z "$DB_PASS" ]; then
  DB_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
fi

log "Creating database '${DB_NAME}' and user '${DB_USER}'..."
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Drop the legacy exams-platform database/user if present.
if [ "$DB_NAME" != "$LEGACY_DB" ]; then
  log "Dropping legacy database '${LEGACY_DB}' (if present)..."
  mysql -e "DROP DATABASE IF EXISTS \`${LEGACY_DB}\`;" 2>/dev/null || true
fi
if [ "$DB_USER" != "$LEGACY_DB_USER" ]; then
  mysql -e "DROP USER IF EXISTS '${LEGACY_DB_USER}'@'localhost';" 2>/dev/null || true
fi

log "Writing ${SITE_ROOT}/.env..."
cat > "${SITE_ROOT}/.env" <<EOF
APP_NAME="Nginix Control Panel"
APP_ENV=production
APP_DEBUG=false

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}
EOF
chown www-data:www-data "${SITE_ROOT}/.env"
chmod 640 "${SITE_ROOT}/.env"

# root-only copy of the credentials
cat > /root/.${SITE_NAME}-db-credentials <<EOF
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
EOF
chmod 600 "/root/.${SITE_NAME}-db-credentials"

# ----------------------------------------------------------------------------
# 9. Encrypted backup script + key + cron
# ----------------------------------------------------------------------------
log "Installing encrypted backup script..."
mkdir -p "$BACKUP_DIR"
if [ ! -f "$BACKUP_KEY" ]; then
  openssl rand -base64 32 > "$BACKUP_KEY"
  chmod 600 "$BACKUP_KEY"
fi
touch "$BACKUP_LOG"
chmod 640 "$BACKUP_LOG"

# Keep a copy of the encryption key inside the app installation folder so it
# is preserved with the app. Root-only: never expose the key to other users.
log "Storing key copy in ${APP_SECRETS}..."
mkdir -p "$APP_SECRETS"
chmod 700 "$APP_DIR/secrets"
install -m 600 -o root -g root "$BACKUP_KEY" "${APP_SECRETS}/mariadb-backup.key"

cat > "$BACKUP_SCRIPT" <<'BASH'
#!/usr/bin/env bash
# Encrypted MariaDB backup (AES-256-CBC). Managed by setup-server.sh.
# Usage: backup-db.sh [database]   (no argument or "all" = every database)
set -euo pipefail

KEY_FILE="/etc/mariadb-backup.key"
DEST="/var/backups/mariadb"
LOG="/var/log/backup-db.log"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

DB="${1:-}"
if [ -z "$DB" ] || [ "$DB" = "all" ] || [ "$DB" = "--all" ]; then
  LABEL="all"
  DUMP_SCOPE=(--all-databases)
else
  LABEL="$(printf '%s' "$DB" | tr -c 'A-Za-z0-9_.-' '_')"
  DUMP_SCOPE=(--databases "$DB")
fi

STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
OUT="${DEST}/db-${LABEL}-${STAMP}.sql.enc"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

mkdir -p "$DEST"
log "Backup started (${LABEL})"

DUMP_BIN="$(command -v mariadb-dump || command -v mysqldump)"
ERR="$(mktemp)"
if "$DUMP_BIN" "${DUMP_SCOPE[@]}" --single-transaction --quick \
        --routines --events --triggers 2>"$ERR" \
   | openssl enc -aes-256-cbc -salt -pbkdf2 -pass "file:${KEY_FILE}" -out "$OUT"; then
  chmod 600 "$OUT"
  log "Backup OK: ${OUT} ($(du -h "$OUT" | cut -f1))"
else
  log "ERROR: backup failed"; cat "$ERR" >> "$LOG"; rm -f "$OUT" "$ERR"; exit 1
fi
rm -f "$ERR"

find "$DEST" -type f -name 'db-*.sql.enc' -mtime +"$RETENTION_DAYS" -delete
log "Pruned backups older than ${RETENTION_DAYS} days"
BASH
chmod 700 "$BACKUP_SCRIPT"

RESTORE_SCRIPT="/usr/local/bin/restore-db.sh"
log "Installing restore script ${RESTORE_SCRIPT}..."
cat > "$RESTORE_SCRIPT" <<'BASH'
#!/usr/bin/env bash
# Restore a database from an encrypted MariaDB backup (AES-256-CBC).
# Usage: restore-db.sh /var/backups/mariadb/db-<name>-<stamp>.sql.enc
set -euo pipefail

KEY_FILE="/etc/mariadb-backup.key"
BACKUP="${1:?usage: restore-db.sh <backup.sql.enc>}"

[ -f "$BACKUP" ] || { echo "backup file not found: ${BACKUP}" >&2; exit 1; }
[ -f "$KEY_FILE" ] || { echo "encryption key not found: ${KEY_FILE}" >&2; exit 1; }

openssl enc -d -aes-256-cbc -pbkdf2 -pass "file:${KEY_FILE}" -in "$BACKUP" | mariadb
echo "Restore complete from ${BACKUP}"
BASH
chmod 700 "$RESTORE_SCRIPT"

log "Installing weekly cron job (Monday 02:00)..."
cat > /etc/cron.d/mariadb-backup <<EOF
# Encrypted MariaDB backup - weekly, Monday 02:00 (managed by setup-server.sh)
0 2 * * 1 root ${BACKUP_SCRIPT} >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/mariadb-backup

# ----------------------------------------------------------------------------
# 10. Firewall, PHP-FPM, services, validation
# ----------------------------------------------------------------------------
if command -v ufw >/dev/null; then
  log "Allowing Nginx Full through UFW..."
  ufw allow 'Nginx Full' >/dev/null 2>&1 || true
fi

log "Enabling services..."
systemctl enable --now "php${PHP_VER}-fpm"

log "Validating nginx configuration..."
nginx -t

log "Restarting nginx..."
systemctl enable --now nginx
systemctl restart nginx

# ----------------------------------------------------------------------------
# 11. Summary
# ----------------------------------------------------------------------------
SUMMARY_FILE="/root/${SITE_NAME}-setup-summary.txt"
cat > "$SUMMARY_FILE" <<EOF
Nginix Control Panel server setup - $(date)
===================================================================
Web root     : ${SITE_ROOT}
nginx vhost  : ${NGINX_AVAIL}
Websites JSON: ${WEBSITES_JSON}
TLS cert     : ${SSL_DIR}/server.crt
phpMyAdmin   : https://<server-ip>/phpmyadmin
Site URL     : https://<server-ip>/
DB name      : ${DB_NAME}
DB user      : ${DB_USER}
DB password  : ${DB_PASS}   (also in /root/.${SITE_NAME}-db-credentials)
Backup script: ${BACKUP_SCRIPT}
Restore script: ${RESTORE_SCRIPT}
Backup key   : ${BACKUP_KEY}
Key copy     : ${APP_SECRETS}/mariadb-backup.key
Backup dir   : ${BACKUP_DIR}
Backup log   : ${BACKUP_LOG}
Cron         : /etc/cron.d/mariadb-backup (Mon 02:00)
Restore cmd  : openssl enc -d -aes-256-cbc -pbkdf2 -pass file:${BACKUP_KEY} \\
                 -in ${BACKUP_DIR}/db-<stamp>.sql.enc | mysql
EOF

log "Done."
echo
cat "$SUMMARY_FILE"
echo
warn "phpMyAdmin + the site use a self-signed certificate; your browser will warn."
