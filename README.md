# Nginix Control Panel

A Flutter-based desktop control panel for Ubuntu servers running the
**Nginx + PHP-FPM + MariaDB** stack. It gives you a native GTK app to manage
services, host websites, databases, backups, scheduled jobs, firewall rules,
config files, a terminal, and network status — with a bundled provisioning
script that sets the whole stack up from scratch.

- Repository: <https://github.com/itsarmen/nginix-control-panel-for-ubuntu>

---

## Features

| Screen         | What it does                                                                 |
| -------------- | ---------------------------------------------------------------------------- |
| **Services**   | Start/stop/restart and inspect system services (nginx, php-fpm, mariadb, …)   |
| **Websites**   | Lists virtual hosts from `/etc/nginx/websites.json`; open site root or config |
| **Databases**  | Create/drop databases and users, change passwords                            |
| **Backups**    | Encrypted (AES-256-CBC) backups of selected databases or all of them          |
| **Restore**    | Restore a database from an encrypted backup with a confirmation step          |
| **Cron Jobs**  | Choose an automatic backup period and which databases to include              |
| **Configs**    | Edit and save key config files (nginx, site vhost, `.env`, `php.ini`, `my.cnf`) |
| **Terminal**   | Run shell commands and view output                                            |
| **Network**    | Connection status, IP/subnet/gateway and DNS details                          |
| **Firewall**   | UFW status, HTTP/HTTPS toggles, custom port open/close, and a port checker     |

The interface is built with [`yaru`](https://pub.dev/packages/yaru) for a native
Ubuntu look and feel.

---

## Screens

- **Services** – per-service status with start / stop / restart actions.
- **Websites** – one card per configured host, with quick jumps to its web root
  and nginx config.
- **Databases** – inline create form plus per-database password reset and delete.
- **Backups** – pick a database (or *All databases*), run a backup with a live
  spinner, and browse the resulting encrypted dumps.
- **Restore** – pick an encrypted dump, confirm, and restore it into MariaDB.
- **Cron Jobs** – set the auto-backup period (hourly / daily / weekly / monthly /
  custom cron) and target databases; previews the exact cron entry before saving.
- **Firewall** – enable UFW safely, toggle ports 80 and 443, open/close any custom
  port, inspect active rules, and check whether a port is listening, allowed, and
  reachable.

---

## Requirements

- Ubuntu 24.04+ (developed against Ubuntu 26.04 LTS)
- [Flutter SDK](https://docs.flutter.dev/get-started/install/linux) (stable)
- `libgtk-3-dev`, `ninja-build`, `clang`, `cmake`, `pkg-config`
- A user allowed to run `sudo` non-interactively (`sudo -n`), since the app
  performs privileged operations (nginx, MariaDB, UFW, writing system configs)

The managed stack on the server side:

- Nginx
- PHP 8.5 FPM
- MariaDB
- phpMyAdmin (under `/phpmyadmin`)

---

## Quick start

```bash
git clone https://github.com/itsarmen/nginix-control-panel-for-ubuntu.git
cd nginix-control-panel-for-ubuntu

flutter pub get
flutter run -d linux
```

Build a release binary:

```bash
flutter build linux --release
# -> build/linux/x64/release/bundle/nginix-control-panel
```

Or launch the built/installed app with the helper script:

```bash
./launch-dashboard.sh
```

---

## Provisioning a server

`setup-server.sh` installs and configures the full stack in one shot:

```bash
sudo ./setup-server.sh            # interactive
sudo ./setup-server.sh --yes      # non-interactive
sudo ./setup-server.sh --keep-devrow
```

It performs, idempotently:

- Installs **Nginx**, **MariaDB**, **PHP 8.5 FPM**, and **phpMyAdmin**
- Removes common conflicting stacks (Apache, MySQL) and cleans legacy artifacts
- Creates the demo website `demoweb.local`, its database/user, and a self-signed
  TLS certificate in `/etc/nginx/ssl/`
- Writes `/etc/nginx/websites.json` (read by the **Websites** tab)
- Installs `/usr/local/bin/backup-db.sh` (encrypted backups) and
  `/usr/local/bin/restore-db.sh`, plus a weekly cron job
- Stores the backup key at `/etc/mariadb-backup.key` and a root-only copy under
  `/opt/nginix-control-panel/secrets/`

> The app reads and writes privileged files, so the account running it should
> have passwordless `sudo`. Review the script before running it on a production
> machine.

---

## Building a .deb package

```bash
./build-deb.sh 1.0.0
# -> dist/nginix-control-panel_1.0.0_amd64.deb
```

`build-deb.sh` builds the Flutter release bundle and assembles a Debian package
that installs the binary to `/opt/nginix-control-panel/`, together with a desktop
entry and hicolor icons.

Install it with:

```bash
sudo dpkg -i dist/nginix-control-panel_1.0.0_amd64.deb
```

---

## Repository layout

```
lib/main.dart              All app screens and logic
assets/app-icon.png        App icon source
icon.svg, icon_1024.png    Master branding assets
linux/                     Linux runner (window title, application id)
linux-icons/               hicolor icon set + desktop entry
setup-server.sh            Server provisioning script
build-deb.sh               .deb packaging
launch-dashboard.sh        Launch helper
docs/                      Documentation
  nginx-multiple-hosts.md  Guide: nginx virtual hosts (SSL, no-SSL, custom ports)
```

---

## Backups & restore

- Backups are encrypted with **AES-256-CBC** using `/etc/mariadb-backup.key`.
- Dumps are named `db-<database>-YYYY-MM-DD_HH-MM-SS.sql.enc` and stored in
  `/var/backups/mariadb/` (default retention: 30 days).
- The **Cron Jobs** screen writes the schedule to `/etc/cron.d/mariadb-backup`.
- The **Restore** screen decrypts a dump and imports it back into MariaDB.

---

## Documentation

- [Serving multiple hosts with nginx](docs/nginx-multiple-hosts.md) — virtual
  hosts with SSL, without SSL, and on custom ports.

---

## License

Proprietary — all rights reserved. Copyright © 2026 itsarmen.
