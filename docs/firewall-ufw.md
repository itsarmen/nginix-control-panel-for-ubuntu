# Firewall (UFW)

This guide covers the **UFW firewall** as used by the **Nginix Control Panel**
setup: how the app manages it, how `setup-server.sh` configures it, and the
manual commands you may need.

UFW (Uncomplicated Firewall) is a front-end for `iptables`/`nftables`. On the
default Ubuntu install its **service is always "active"**, but the firewall is
**inactive** until you explicitly enable it — meaning no rules are enforced.

> Check the *enforcement* state, not the daemon state:
>
> ```bash
> systemctl is-active ufw   # active  -> daemon is running
> sudo ufw status           # inactive -> NOT enforcing anything
> ```

---

## 1. What the Control Panel does

The **Firewall** page in the app:

| Element              | What it does                                                           |
| -------------------- | ---------------------------------------------------------------------- |
| Status chip          | Reads `ufw status`; shows **Active**, **Inactive** or **Unknown**      |
| HTTP / HTTPS toggles | `ufw allow 80/tcp` and `ufw allow 443/tcp` (add/delete rules)          |
| Custom Port          | Open/close any `port/tcp` or `port/udp`                                |
| ENABLE button        | Enables UFW **safely** (see below)                                     |
| Port Status Checker  | Local listener (`ss`), UFW allowance, and a live TCP connection test   |

The Services page's **UFW Firewall** tile also reflects the real enforcement
state (`ufw status`), so it shows **Stopped** until the firewall is enabled.

### Safe enable

Enabling UFW switches the default policy to `deny (incoming)`. If SSH is not
allowed *before* enabling, a remote session can be locked out. So the app:

1. Allows **Nginx Full** (80 + 443). If this fails, it **aborts** and does not
   enable.
2. Allows **SSH** — using the `OpenSSH` app profile when present, otherwise
   opening **22/tcp** only if an SSH server (`ssh`/`sshd`) is actually running.
   If neither exists (no SSH on the machine) it simply skips SSH.
3. Runs `ufw --force enable`.

---

## 2. What `setup-server.sh` does

During installation the script configures and enables UFW:

```bash
ufw allow 'Nginx Full'

if ufw app list | grep -q '^ *OpenSSH$'; then
  ufw allow OpenSSH
elif systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
  ufw allow 22/tcp
fi

ufw --force enable
```

The conditional is important: many minimal servers ship **without** the
`OpenSSH` profile (and sometimes without an SSH server at all). Hardcoding
`ufw allow OpenSSH` then fails and prevents the firewall from ever being
enabled.

---

## 3. Manual commands

```bash
# Status
sudo ufw status verbose
sudo ufw app list                 # available application profiles

# Allow / deny
sudo ufw allow 'Nginx Full'       # 80 + 443
sudo ufw allow 22/tcp             # SSH by port
sudo ufw allow OpenSSH            # SSH by profile (if it exists)
sudo ufw allow 8080/tcp
sudo ufw deny 3306/tcp            # keep MariaDB private
sudo ufw delete allow 8080/tcp

# Enable / disable
sudo ufw --force enable
sudo ufw disable
sudo ufw reset                     # wipe all rules (use with care)

# Numbered rules
sudo ufw status numbered
sudo ufw delete <number>
```

### Application profiles

Profiles live in `/etc/ufw/applications.d/`. `Nginx Full` maps to `80,443/tcp`.
List what is available with `sudo ufw app list` and inspect one with
`sudo ufw app info OpenSSH`.

---

## 4. Recommended baseline

After setting up the stack you usually want:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 'Nginx Full'
sudo ufw allow 22/tcp        # only if you need SSH
sudo ufw --force enable
sudo ufw status verbose
```

Keep database and internal admin ports **closed** to the outside world:

```bash
sudo ufw deny 3306/tcp       # MariaDB
```

---

## 5. Troubleshooting

| Symptom                                       | Cause / fix                                                              |
| --------------------------------------------- | ------------------------------------------------------------------------ |
| `ERROR: Could not find a profile matching 'OpenSSH'` | Profile not installed — use `sudo ufw allow 22/tcp` instead       |
| Rule added but port still unreachable         | Something isn't listening (`ss -ltnH`), or another device/upstream blocks |
| App shows **Unknown** firewall status         | `sudo -n ufw status` failed — grant passwordless sudo (see README)        |
| Can't connect over SSH after enabling         | Allow SSH *before* enabling; use console access to `sudo ufw allow 22/tcp` |
| `ufw` service active but nothing enforced     | Expected — `ufw status` (enforcement), not the daemon, is the truth      |

---

## 6. Quick reference

```bash
sudo ufw status verbose           # what is enforced now
sudo ufw app list                 # profiles (OpenSSH, Nginx Full, …)
sudo ufw allow 'Nginx Full'       # web traffic
sudo ufw allow 22/tcp             # remote access (if needed)
sudo ufw --force enable           # turn it on
sudo ufw reload                   # apply rule changes
```
