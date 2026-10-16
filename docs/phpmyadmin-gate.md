# phpMyAdmin Login Gate

This guide explains the extra **login layer** that `setup-server.sh` places in
front of phpMyAdmin, how the **Nginix Control Panel** shows and manages it, and
how to change or remove it by hand.

phpMyAdmin is reachable at `https://<server-ip>/phpmyadmin`. It is protected by
**two** logins:

1. **Nginx HTTP Basic auth** — the native browser popup (realm *Nginix Control
   Panel*) requested by nginx *before* phpMyAdmin is served at all.
2. **phpMyAdmin's own login** — the MariaDB database user/password form
   (`auth_type = 'cookie'`).

So a visitor must pass the nginx gate first, then authenticate to MariaDB.

---

## 1. Files involved

| Path                                        | Purpose                                              | Permissions        |
| ------------------------------------------- | ---------------------------------------------------- | ------------------ |
| `/etc/nginx/.nginix-htpasswd`               | The gate login (user + `$apr1$` password hash)       | `640 root:www-data` |
| `/etc/nginx/phpmyadmin-gate.json`           | Machine-readable copy read by the app (incl. plaintext password) | `600 root:root`     |
| `/root/.demoweb.local-phpmyadmin-credentials` | Human-readable copy written at setup              | `600 root:root`     |
| `/etc/phpmyadmin/conf.d/99-local.php`       | phpMyAdmin config (cookie auth + blowfish secret)    | default            |

The gate is applied in the site vhost
(`/etc/nginx/sites-available/demoweb.local`):

```nginx
location ^~ /phpmyadmin {
    auth_basic "Nginix Control Panel";
    auth_basic_user_file /etc/nginx/.nginix-htpasswd;

    root /usr/share/;
    index index.php index.html;

    location ~ ^/phpmyadmin/(.+\.php)$ {
        root /usr/share/;
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
    location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
        root /usr/share/;
    }
}
```

> **Why `location ^~ /phpmyadmin` (and not a plain `location /phpmyadmin`)?**
> nginx checks **regex** locations before plain prefix locations. A request for
> `/phpmyadmin/index.php` also matches the site's `location ~ \.php$`, which is
> declared earlier and has **no** `auth_basic` — so phpMyAdmin would be served
> directly, bypassing the gate. The `^~` modifier tells nginx not to evaluate
> regex locations for this prefix, so the gate always applies.

---

## 2. What the app shows

Open **Configs → phpMyAdmin Gate**. The tab displays:

- the gate **URL**, **username**, and **password** (masked, with a show toggle),
- **copy** buttons for each field and for `user / password`,
- **Open** — launches the URL in the browser,
- **folder** — opens `/etc/nginx`,
- **Change Password** — see below.

The credentials come from `/etc/nginx/phpmyadmin-gate.json`; because the file is
root-only the app reads it through `sudo -n cat`.

### Change Password

The dialog accepts a new password (or generates one). On save the app:

1. hashes it with `openssl passwd -apr1`,
2. rewrites `/etc/nginx/.nginix-htpasswd` (restores `root:www-data`, `640`),
3. rewrites `/etc/nginx/phpmyadmin-gate.json` with the new password
   (restores `root:root`, `600`),
4. refreshes the card.

Changes are effective immediately — HTTP Basic auth reads the htpasswd file per
request, so **no nginx reload is required**.

> The app does **not** update `/root/.demoweb.local-phpmyadmin-credentials`
> (it doesn't know the site name). Update that root file manually if you rely on
> it, or treat the JSON as the source of truth.

---

## 3. Manual commands

```bash
# Inspect
sudo cat /etc/nginx/.nginix-htpasswd          # user:hash (no plaintext)
sudo cat /etc/nginx/phpmyadmin-gate.json      # user + plaintext password

# Change the password with openssl (no apache2-utils needed)
printf 'nginix:%s\n' "$(openssl passwd -apr1 'NEW_PASSWORD')" \
  | sudo tee /etc/nginx/.nginix-htpasswd >/dev/null
sudo chown root:www-data /etc/nginx/.nginix-htpasswd
sudo chmod 640 /etc/nginx/.nginix-htpasswd
# then update phpmyadmin-gate.json to match

# Or with htpasswd (if apache2-utils is installed)
sudo htpasswd /etc/nginx/.nginix-htpasswd nginix

# Verify the gate (401 without creds, 200 with)
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/phpmyadmin/
curl -sk -o /dev/null -w '%{http_code}\n' -u 'nginix:NEW_PASSWORD' https://127.0.0.1/phpmyadmin/
```

---

## 4. Removing the gate

Delete the two `auth_basic*` lines from the `/phpmyadmin` block (or drop the
`^~` back to a plain prefix, which re-opens the bypass) and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

To gate a **different** path, apply the same two directives in that `location`,
always using the `^~` prefix.

---

## 5. Troubleshooting

| Symptom                                        | Cause / fix                                                                 |
| ---------------------------------------------- | --------------------------------------------------------------------------- |
| phpMyAdmin opens with no popup                 | The `location` is a plain prefix (regex `\.php$` wins) — use `location ^~ /phpmyadmin` |
| Popup reappears on every request / assets too  | Expected: Basic auth covers the whole `/phpmyadmin` prefix                  |
| Still asks for the old password                | Browser cached it — close the tab or restart the browser                    |
| `500` after editing htpasswd                    | File not readable by `www-data` — `chown root:www-data`, `chmod 640`        |
| App shows no gate card / "No phpmyadmin-gate.json found" | Run `setup-server.sh`, or create `/etc/nginx/phpmyadmin-gate.json` |
| App can't read/change the password             | Needs passwordless `sudo` (see README)                                      |

---

## 6. Security notes

- Serve phpMyAdmin over **HTTPS only** (the setup vhost forces the 301 redirect).
- The plaintext gate password lives in `phpmyadmin-gate.json` and the root creds
  file — keep them root-only (`600`).
- The gate is an nginx-level lock; it does not replace phpMyAdmin's own MariaDB
  authentication.
