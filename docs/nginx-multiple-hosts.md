# Nginx: Serving Multiple Hosts (Virtual Hosts)

This guide shows how to configure nginx to serve **several websites/hosts** from
a single server, with examples for **hosts using SSL**, **hosts without SSL**,
and **hosts on different ports**, following the conventions used by the
**Nginix Control Panel** setup (`nginx` + `php8.5-fpm` + MariaDB).

A "host" is a virtual host — a `server { ... }` block that nginx picks based on
the `listen` port/address and the incoming `Host` header (`server_name`).

---

## 1. Directory layout

Debian/Ubuntu nginx splits site configs in two:

| Path                             | Purpose                                             |
| -------------------------------- | --------------------------------------------------- |
| `/etc/nginx/nginx.conf`          | Global config; `http {}` includes the two dirs below |
| `/etc/nginx/sites-available/`    | All site config files (not active until linked)      |
| `/etc/nginx/sites-enabled/`      | Symlinks to the sites that are actually served       |

`/etc/nginx/nginx.conf` already contains:

```nginx
http {
    # ... global settings ...

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

So anything you place (or symlink) into `sites-enabled/` is loaded.

### Recommended: one file per host

```
/etc/nginx/sites-available/
├── demoweb.local.conf
├── shop.local.conf
├── api.local.conf
└── blog.local.conf

/etc/nginx/sites-enabled/
├── demoweb.local.conf -> ../sites-available/demoweb.local.conf
├── shop.local.conf    -> ../sites-available/shop.local.conf
└── api.local.conf     -> ../sites-available/api.local.conf
```

---

## 2. A single host with SSL (baseline)

This mirrors the `demoweb.local` vhost created by `setup-server.sh`: HTTP is
redirected to HTTPS, and PHP is served through `php8.5-fpm`.

`/etc/nginx/sites-available/demoweb.local.conf`

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name demoweb.local;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name demoweb.local;

    root /var/www/websites/demoweb.local;
    index index.php index.html;

    ssl_certificate     /etc/nginx/ssl/demoweb.local.crt;
    ssl_certificate_key /etc/nginx/ssl/demoweb.local.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/demoweb.local-access.log;
    error_log  /var/log/nginx/demoweb.local-error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }

    location ~ /\.ht { deny all; }
}
```

Only **one** site should be marked `default_server` (see section 7) — the block
above is not, so it can safely coexist with others.

---

## 3. Multiple hosts in one file

If you prefer to keep every host in a single file, you can put multiple
`server {}` blocks in `sites-enabled/hosts.conf`. Nginx evaluates them in order;
each request is matched by `listen` then `server_name`.

`/etc/nginx/sites-enabled/hosts.conf`

```nginx
# ------------------------------------------------------------------
# Shared TLS settings (apply to every SSL host below)
# ------------------------------------------------------------------
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;

# ------------------------------------------------------------------
# demo.local  ->  PHP app  (HTTP -> HTTPS)
# ------------------------------------------------------------------
server {
    listen 80;
    listen [::]:80;
    server_name demo.local www.demo.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name demo.local www.demo.local;

    root /var/www/websites/demo.local;
    index index.php index.html;

    ssl_certificate     /etc/nginx/ssl/demo.local.crt;
    ssl_certificate_key /etc/nginx/ssl/demo.local.key;

    access_log /var/log/nginx/demo.local-access.log;
    error_log  /var/log/nginx/demo.local-error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}

# ------------------------------------------------------------------
# shop.local  ->  PHP app on its own PHP-FPM pool
# ------------------------------------------------------------------
server {
    listen 80;
    listen [::]:80;
    server_name shop.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name shop.local;

    root /var/www/websites/shop.local;
    index index.php index.html;

    ssl_certificate     /etc/nginx/ssl/shop.local.crt;
    ssl_certificate_key /etc/nginx/ssl/shop.local.key;

    access_log /var/log/nginx/shop.local-access.log;
    error_log  /var/log/nginx/shop.local-error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm-shop.sock;
    }
}

# ------------------------------------------------------------------
# api.local  ->  static files + a proxied backend
# ------------------------------------------------------------------
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name api.local;

    root /var/www/websites/api.local;
    index index.html;

    ssl_certificate     /etc/nginx/ssl/api.local.crt;
    ssl_certificate_key /etc/nginx/ssl/api.local.key;

    access_log /var/log/nginx/api.local-access.log;
    error_log  /var/log/nginx/api.local-error.log;

    location / {
        try_files $uri $uri/ =404;
    }
    location /v1/ {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

> Tip: `ssl_protocols`, `ssl_ciphers`, and other `ssl_*` directives can be set
> once at the `http {}` level (as shown) instead of repeating them per host.

---

## 4. Hosts **without** SSL (plain HTTP)

A host that doesn't use SSL simply has no `ssl` on `listen`, no certificate
directives, and **no redirect** to HTTPS. It serves everything over HTTP.

```nginx
# plain.local -- HTTP only, no TLS, no redirect
server {
    listen 80;
    listen [::]:80;
    server_name plain.local www.plain.local;

    root /var/www/websites/plain.local;
    index index.php index.html;

    access_log /var/log/nginx/plain.local-access.log;
    error_log  /var/log/nginx/plain.local-error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}
```

Key differences vs. an SSL host:

| Feature             | With SSL                 | Without SSL          |
| ------------------- | ------------------------ | -------------------- |
| `listen`            | `80` + `443 ssl`         | `80` only            |
| Redirect block      | `return 301 https://…`   | none                 |
| `ssl_certificate*`  | required                 | **not present**      |
| `http2 on`          | optional                 | not applicable       |
| URL scheme          | `https://`               | `http://`            |

A host can be reachable on **both** schemes: keep the port-80 block that
redirects, and the port-443 block that serves.

---

## 5. Hosts on **different ports**

`listen` accepts any port. This is useful for internal dashboards, alternate
stacks, or when you can't use 80/443 (already taken, or blocked by policy).

```nginx
# Internal dashboard: plain HTTP on port 8080
server {
    listen 8080;
    server_name dashboard.internal;

    root /var/www/websites/dashboard;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}

# Admin panel: HTTPS on port 8443 (own certificate)
server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    http2 on;
    server_name admin.local;

    root /var/www/websites/admin;
    index index.php index.html;

    ssl_certificate     /etc/nginx/ssl/admin.local.crt;
    ssl_certificate_key /etc/nginx/ssl/admin.local.key;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}

# Same host on two ports: 80 (redirect) and 8080 (plain) both hit the app
server {
    listen 8080;
    server_name demo.local;

    root /var/www/websites/demo.local;
    index index.php index.html;
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}
```

Notes:

- Each **port** has its own independent `default_server`. You can have one
  `default_server` on `:80`, another on `:8443`, etc.
- 443 and 8443 don't conflict — they are different sockets.
- Open non-standard ports in the firewall:

  ```bash
  sudo ufw allow 8080/tcp
  sudo ufw allow 8443/tcp
  ```

- Update `server_name` matching won't help if a port isn't open; test with
  `curl -I http://localhost:8080/` from the server itself first.

---

## 6. All three in one file (SSL, no-SSL, custom ports)

A single host can also participate in several modes. The combined picture:

```nginx
# ---- with SSL (default ports) -------------------------------------
server {
    listen 80;
    listen [::]:80;
    server_name secure.local;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name secure.local;

    root /var/www/websites/secure.local;
    index index.php index.html;
    ssl_certificate     /etc/nginx/ssl/secure.local.crt;
    ssl_certificate_key /etc/nginx/ssl/secure.local.key;

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}

# ---- without SSL (plain HTTP) -------------------------------------
server {
    listen 80;
    server_name plain.local;
    root /var/www/websites/plain.local;
    index index.html;
    location / { try_files $uri $uri/ =404; }
}

# ---- custom port, no SSL ------------------------------------------
server {
    listen 8080;
    server_name legacy.local;
    root /var/www/websites/legacy.local;
    index index.php index.html;
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}

# ---- custom port, with SSL ----------------------------------------
server {
    listen 8443 ssl;
    http2 on;
    server_name staging.local;
    root /var/www/websites/staging.local;
    index index.php index.html;
    ssl_certificate     /etc/nginx/ssl/staging.local.crt;
    ssl_certificate_key /etc/nginx/ssl/staging.local.key;
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.5-fpm.sock;
    }
}
```

Summary:

| Host             | Ports        | SSL  | Reached at                        |
| ---------------- | ------------ | ---- | --------------------------------- |
| `secure.local`   | 80, 443      | yes  | `https://secure.local/`           |
| `plain.local`    | 80           | no   | `http://plain.local/`             |
| `legacy.local`   | 8080         | no   | `http://legacy.local:8080/`       |
| `staging.local`  | 8443         | yes  | `https://staging.local:8443/`     |

---

## 7. Enable a site, test, and reload

Always validate the config **before** reloading — a bad config can take nginx
down on the next restart.

```bash
# Link the site into sites-enabled (one file per host)
sudo ln -s /etc/nginx/sites-available/demo.local.conf /etc/nginx/sites-enabled/

# Test the whole config
sudo nginx -t

# Apply (reload = zero downtime)
sudo systemctl reload nginx
```

Disable a host without deleting it:

```bash
sudo rm /etc/nginx/sites-enabled/demo.local.conf
sudo systemctl reload nginx
```

Check which hosts and ports nginx is actually listening on:

```bash
sudo nginx -T | grep -E 'server_name|listen'
# or, live sockets:
sudo ss -ltnp | grep nginx
```

---

## 8. Default server and host matching

nginx picks the `server` block as follows:

1. Match the `listen` port + address.
2. Among those, match `server_name` (exact, then leading wildcard, then regex).
3. If nothing matches, use the block flagged `default_server` **for that port**.

Keep **exactly one** `default_server` per port. In the single-host baseline the
catch-all is:

```nginx
listen 443 ssl default_server;
server_name _;
```

The literal `_` is just a placeholder meaning "no real name". If you have
multiple hosts, give the catch-all to one block (or a dedicated block) so
unrecognized hosts don't accidentally hit the wrong site.

---

## 9. TLS certificates

### Self-signed (LAN / local dev)

```bash
sudo openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/demo.local.key \
  -out    /etc/nginx/ssl/demo.local.crt \
  -subj   "/CN=demo.local" \
  -addext "subjectAltName=DNS:demo.local,DNS:www.demo.local"
```

### Let's Encrypt (public hosts only)

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d demo.local -d www.demo.local
```

Certbot edits the vhost to add `ssl_certificate` lines and a renewal timer.
It handles **one** host per invocation; run it again for each public host.
Let's Encrypt requires the host to be reachable over HTTP **on port 80** with a
valid public DNS name.

---

## 10. Optional: separate PHP-FPM pool per host

Running each host under its own pool isolates PHP processes and lets you set
different resource limits or users.

Create a pool, e.g. `/etc/php/8.5/fpm/pool.d/shop.conf`:

```ini
[shop]
user = www-data
group = www-data
listen = /run/php/php8.5-fpm-shop.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

Then point that host's `fastcgi_pass` at the new socket (as in the `shop.local`
block above) and reload:

```bash
sudo systemctl reload php8.5-fpm
```

---

## 11. Integrating with Nginix Control Panel

The panel's **Websites** tab reads `/etc/nginx/websites.json`. Add an entry for
each host so it shows up in the UI:

```json
{
  "websites": [
    {
      "name": "demo.local",
      "url": "https://{serverIp}/",
      "root": "/var/www/websites/demo.local",
      "config": "/etc/nginx/sites-available/demo.local.conf",
      "description": "Main demo site"
    },
    {
      "name": "plain.local",
      "url": "http://{serverIp}/",
      "root": "/var/www/websites/plain.local",
      "config": "/etc/nginx/sites-available/plain.local.conf",
      "description": "HTTP-only site"
    },
    {
      "name": "legacy.local",
      "url": "http://{serverIp}:8080/",
      "root": "/var/www/websites/legacy.local",
      "config": "/etc/nginx/sites-available/legacy.local.conf",
      "description": "Custom-port site"
    },
    {
      "name": "staging.local",
      "url": "https://{serverIp}:8443/",
      "root": "/var/www/websites/staging.local",
      "config": "/etc/nginx/sites-available/staging.local.conf",
      "description": "Custom SSL port"
    }
  ]
}
```

`{serverIp}` is replaced at runtime with the machine's IP. The panel's
**Configs** tab can then open each host's config file directly.

---

## 12. Common pitfalls

- **Config not applied** — the file was created but never symlinked into
  `sites-enabled/`, or you forgot `systemctl reload nginx`.
- **All hosts show the same site** — a `default_server` is catching unfamiliar
  `Host` headers, or two blocks share a `server_name` on the same port.
- **Duplicate `default_server`** — nginx fails with `a duplicate default server`.
  There must be only one per port.
- **Port not reachable** — the port isn't open in the firewall (`ufw allow
  8080/tcp`) or isn't listening (`ss -ltnp | grep nginx`).
- **Mixing SSL and non-SSL on one port** — you can't serve both `http` and
  `https` on the same port; use different ports (e.g. 80 vs 443, 8080 vs 8443).
- **500 / blank PHP page** — wrong `fastcgi_pass` socket (check the PHP version),
  or `php8.5-fpm` isn't running (`systemctl status php8.5-fpm`).
- **`conflicting server name` warning** — the same `server_name` appears on two
  hosts; nginx uses the first and warns about the rest.
- **Permission denied reading the site** — `root` must be readable by the
  `www-data` (nginx/PHP-FPM) user.
- **Changes lost on the next server setup** — keep site configs in source
  control and reproduce them from `setup-server.sh`, not by hand.

---

## 13. Minimal checklist

1. Create `/var/www/websites/<host>` and set ownership (`www-data`).
2. Create `/etc/nginx/sites-available/<host>.conf`.
   - SSL host: `listen 80` (redirect) + `listen 443 ssl` with certs.
   - No-SSL host: `listen 80` only, no redirect, no certs.
   - Custom port: `listen <port>` (and `ssl` if using a cert).
3. Generate or obtain the certificate in `/etc/nginx/ssl/` (SSL hosts only).
4. `sudo ln -s /etc/nginx/sites-available/<host>.conf /etc/nginx/sites-enabled/`.
5. `sudo nginx -t` then `sudo systemctl reload nginx`.
6. Open any custom ports in the firewall (`ufw allow <port>/tcp`).
7. Add the host to `/etc/nginx/websites.json` so the panel lists it.
8. For local names, add entries to `/etc/hosts`:
   `127.0.0.1 demo.local plain.local legacy.local staging.local`
