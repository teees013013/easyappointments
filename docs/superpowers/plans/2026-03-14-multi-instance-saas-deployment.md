# Multi-Instance EasyAppointments SaaS Deployment — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make EasyAppointments deployable as isolated, per-product instances on Coolify using a single production Docker image with env-var-driven configuration.

**Architecture:** Multi-stage Docker build producing one image. Each SaaS product gets a separate Coolify service (container) using the same image but with unique env vars pointing to its own database. One shared MySQL server hosts all databases. Nginx + PHP-FPM run inside each container via supervisord.

**Tech Stack:** PHP 8.4, CodeIgniter 3, Docker (multi-stage Alpine), Nginx, supervisord, MySQL 8.0, Bash

**Spec:** `docs/superpowers/specs/2026-03-14-multi-instance-saas-deployment-design.md`

---

## Chunk 1: Environment Variable Config Layer

These tasks modify existing PHP config files so the app reads from environment variables at runtime, falling back to `Config::` constants as defaults.

### Task 1: Add env-var overrides to database config

**Files:**
- Modify: `application/config/database.php:52-55`

- [ ] **Step 1: Modify database.php to read from env vars**

Replace lines 52-55 in `application/config/database.php`:

```php
// Before:
$db['default']['hostname'] = Config::DB_HOST;
$db['default']['username'] = Config::DB_USERNAME;
$db['default']['password'] = Config::DB_PASSWORD;
$db['default']['database'] = Config::DB_NAME;

// After:
$db['default']['hostname'] = getenv('EA_DB_HOST') ?: Config::DB_HOST;
$db['default']['username'] = getenv('EA_DB_USERNAME') ?: Config::DB_USERNAME;
$db['default']['password'] = getenv('EA_DB_PASSWORD') ?: Config::DB_PASSWORD;
$db['default']['database'] = getenv('EA_DB_NAME') ?: Config::DB_NAME;
```

- [ ] **Step 2: Verify the app still loads with defaults**

Run: `cd /Users/brenttudas/Forked-OSS/easyappointments && docker compose up -d && sleep 5 && curl -s -o /dev/null -w '%{http_code}' http://localhost/booking`

Expected: `200` (app loads normally with the `Config::` constant defaults)

- [ ] **Step 3: Commit**

```bash
git add application/config/database.php
git commit -m "feat: add env-var overrides for database config

EA_DB_HOST, EA_DB_NAME, EA_DB_USERNAME, EA_DB_PASSWORD env vars
now override Config:: constants when set. Falls back to defaults."
```

---

### Task 2: Add env-var overrides to Google Calendar config

**Files:**
- Modify: `application/config/google.php:13-17`

- [ ] **Step 1: Modify google.php to read from env vars**

Replace lines 13-17 in `application/config/google.php`:

```php
// Before:
$config['google_sync_feature'] = Config::GOOGLE_SYNC_FEATURE;
$config['google_client_id'] = Config::GOOGLE_CLIENT_ID;
$config['google_client_secret'] = Config::GOOGLE_CLIENT_SECRET;

// After:
$config['google_sync_feature'] = filter_var(
    getenv('EA_GOOGLE_SYNC') ?: Config::GOOGLE_SYNC_FEATURE,
    FILTER_VALIDATE_BOOLEAN,
);
$config['google_client_id'] = getenv('EA_GOOGLE_CLIENT_ID') ?: Config::GOOGLE_CLIENT_ID;
$config['google_client_secret'] = getenv('EA_GOOGLE_CLIENT_SECRET') ?: Config::GOOGLE_CLIENT_SECRET;
```

- [ ] **Step 2: Commit**

```bash
git add application/config/google.php
git commit -m "feat: add env-var overrides for Google Calendar config

EA_GOOGLE_SYNC, EA_GOOGLE_CLIENT_ID, EA_GOOGLE_CLIENT_SECRET env
vars now override Config:: constants when set."
```

---

### Task 3: Add env-var overrides to app config

**Files:**
- Modify: `application/config/app.php:14-16`

- [ ] **Step 1: Modify app.php to read from env vars**

Replace lines 14-16 in `application/config/app.php`:

```php
// Before:
$config['url'] = Config::BASE_URL;
$config['debug'] = Config::DEBUG_MODE;

// After:
$config['url'] = getenv('EA_BASE_URL') ?: Config::BASE_URL;
$config['debug'] = filter_var(
    getenv('EA_DEBUG_MODE') ?: Config::DEBUG_MODE,
    FILTER_VALIDATE_BOOLEAN,
);
```

- [ ] **Step 2: Commit**

```bash
git add application/config/app.php
git commit -m "feat: add env-var overrides for app URL and debug mode

EA_BASE_URL, EA_DEBUG_MODE env vars now override Config:: constants."
```

---

### Task 4: Add env-var overrides to email config

**Files:**
- Modify: `application/config/email.php:8-19`

- [ ] **Step 1: Modify email.php to read SMTP settings from env vars**

Replace lines 8-19 in `application/config/email.php` (everything between the `$config['useragent']` line and the `$config['crlf']` line):

```php
// Before:
$config['protocol'] = 'mail'; // or 'smtp'
$config['mailtype'] = 'html'; // or 'text'
// $config['smtp_debug'] = '0'; // or '1'
// $config['smtp_auth'] = TRUE; //or FALSE for anonymous relay.
// $config['smtp_host'] = '';
// $config['smtp_user'] = '';
// $config['smtp_pass'] = '';
// $config['smtp_crypto'] = 'ssl'; // or 'tls'
// $config['smtp_port'] = 25;
// $config['from_name'] = '';
// $config['from_address'] = '';
// $config['reply_to'] = '';

// After:
$config['protocol'] = getenv('EA_MAIL_PROTOCOL') ?: 'mail';
$config['mailtype'] = 'html';

$smtp_host = getenv('EA_SMTP_HOST');

if ($smtp_host) {
    $config['protocol'] = getenv('EA_MAIL_PROTOCOL') ?: 'smtp';
    $config['smtp_host'] = $smtp_host;
    $config['smtp_user'] = getenv('EA_SMTP_USER') ?: '';
    $config['smtp_pass'] = getenv('EA_SMTP_PASS') ?: '';
    $config['smtp_crypto'] = getenv('EA_SMTP_CRYPTO') ?: 'tls';
    $config['smtp_port'] = (int) (getenv('EA_SMTP_PORT') ?: 587);
    $config['smtp_auth'] = true;
}

$from_address = getenv('EA_MAIL_FROM_ADDRESS');

if ($from_address) {
    $config['from_address'] = $from_address;
    $config['from_name'] = getenv('EA_MAIL_FROM_NAME') ?: '';
}
```

- [ ] **Step 2: Commit**

```bash
git add application/config/email.php
git commit -m "feat: add env-var overrides for SMTP email config

EA_SMTP_HOST, EA_SMTP_USER, EA_SMTP_PASS, EA_SMTP_PORT,
EA_SMTP_CRYPTO, EA_MAIL_PROTOCOL, EA_MAIL_FROM_ADDRESS,
EA_MAIL_FROM_NAME env vars enable SMTP without editing files."
```

---

### Task 5: Add env-var overrides to main config.php (encryption key, language, proxy IPs)

**Files:**
- Modify: `application/config/config.php:136-140` (language)
- Modify: `application/config/config.php:348` (encryption key)
- Modify: `application/config/config.php:465` (proxy IPs)

- [ ] **Step 1: Modify config.php language resolution (line 136-140)**

Replace lines 136-140:

```php
// Before:
$config['language'] =
    $_GET['language'] ??
    (isset($_SERVER['HTTP_ACCEPT_LANGUAGE'], $languages[$language_code])
        ? $languages[$language_code]
        : Config::LANGUAGE);

// After:
$ea_language = getenv('EA_LANGUAGE');

$config['language'] =
    $_GET['language'] ??
    ($ea_language ?: (isset($_SERVER['HTTP_ACCEPT_LANGUAGE'], $languages[$language_code])
        ? $languages[$language_code]
        : Config::LANGUAGE));
```

- [ ] **Step 2: Modify config.php encryption key (line 348)**

Replace line 348:

```php
// Before:
$config['encryption_key'] = base64_encode(APPPATH);

// After:
$config['encryption_key'] = getenv('EA_ENCRYPTION_KEY') ?: base64_encode(APPPATH);
```

- [ ] **Step 3: Modify config.php proxy IPs (line 465)**

Replace line 465:

```php
// Before:
$config['proxy_ips'] = '';

// After:
$config['proxy_ips'] = getenv('EA_PROXY_IPS') ?: '';
```

- [ ] **Step 4: Commit**

```bash
git add application/config/config.php
git commit -m "feat: add env-var overrides for language, encryption key, proxy IPs

EA_LANGUAGE, EA_ENCRYPTION_KEY, EA_PROXY_IPS env vars. Encryption
key override is critical for multi-instance session security."
```

---

### Task 6: Add env-var overrides to index.php (debug mode)

**Files:**
- Modify: `index.php:108-114`

- [ ] **Step 1: Modify index.php environment detection**

Replace lines 108-114 in `index.php`:

```php
// Before:
$app_env = getenv('APP_ENV');

if ($app_env) {
    define('ENVIRONMENT', $app_env);
} else {
    define('ENVIRONMENT', Config::DEBUG_MODE ? 'development' : 'production');
}

// After:
$app_env = getenv('APP_ENV');
$debug_mode = filter_var(getenv('EA_DEBUG_MODE') ?: Config::DEBUG_MODE, FILTER_VALIDATE_BOOLEAN);

if ($app_env) {
    define('ENVIRONMENT', $app_env);
} else {
    define('ENVIRONMENT', $debug_mode ? 'development' : 'production');
}
```

- [ ] **Step 2: Commit**

```bash
git add index.php
git commit -m "feat: add EA_DEBUG_MODE env-var override for environment detection"
```

---

### Task 7: Add env-var overrides to language defaults in libraries

**Files:**
- Modify: `application/libraries/Accounts.php:78`
- Modify: `application/libraries/Ldap_client.php:94`

- [ ] **Step 1: Modify Accounts.php language fallback**

Replace line 78 in `application/libraries/Accounts.php`:

```php
// Before:
'language' => !empty($user['language']) ? $user['language'] : Config::LANGUAGE,

// After:
'language' => !empty($user['language']) ? $user['language'] : (getenv('EA_LANGUAGE') ?: Config::LANGUAGE),
```

- [ ] **Step 2: Modify Ldap_client.php language fallback**

Replace line 94 in `application/libraries/Ldap_client.php`:

```php
// Before:
'language' => !empty($user['language']) ? $user['language'] : Config::LANGUAGE,

// After:
'language' => !empty($user['language']) ? $user['language'] : (getenv('EA_LANGUAGE') ?: Config::LANGUAGE),
```

- [ ] **Step 3: Commit**

```bash
git add application/libraries/Accounts.php application/libraries/Ldap_client.php
git commit -m "feat: add EA_LANGUAGE env-var override to library language defaults"
```

---

### Task 8: Replace CORS with env-var-driven allowlist in routes.php

**Files:**
- Modify: `application/config/routes.php:88-106`

- [ ] **Step 1: Replace CORS block in routes.php**

Replace lines 88-106 in `application/config/routes.php` (the entire CORS section after the comment block):

```php
// Before (lines 88-106):
header('Access-Control-Allow-Origin: ' . ($_SERVER['HTTP_ORIGIN'] ?? '*'));
header('Access-Control-Allow-Credentials: "true"');
if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'])) {
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
}
if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'])) {
    header('Access-Control-Allow-Headers: ' . $_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS']);
}
if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

// After:
$allowed_origins_raw = getenv('EA_CORS_ORIGINS') ?: '';
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';

if (!empty($allowed_origins_raw)) {
    $allowed_origins = array_filter(array_map('trim', explode(',', $allowed_origins_raw)));

    if (in_array($origin, $allowed_origins, true)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Access-Control-Allow-Credentials: true');
    }
} else {
    // No CORS origins configured — allow all (dev/backwards compat)
    header('Access-Control-Allow-Origin: *');
    // Note: Do NOT set Allow-Credentials with wildcard origin (browsers reject this)
}

if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'])) {
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD');
}

if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'])) {
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
}

// CSP frame-ancestors for iframe embedding control
$frame_ancestors = getenv('EA_FRAME_ANCESTORS') ?: '*';

if ($frame_ancestors !== '*') {
    header("Content-Security-Policy: frame-ancestors 'self' " . $frame_ancestors);
}

if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}
```

- [ ] **Step 2: Verify the app still loads with default (no env vars set)**

Run: `curl -s -o /dev/null -w '%{http_code}' http://localhost/booking`

Expected: `200`

- [ ] **Step 3: Commit**

```bash
git add application/config/routes.php
git commit -m "feat: secure CORS with env-var-driven origin allowlist

EA_CORS_ORIGINS restricts allowed origins. Access-Control-Allow-Headers
uses explicit allowlist instead of reflecting request headers.
EA_FRAME_ANCESTORS adds CSP frame-ancestors header for iframe control.
Falls back to wildcard for dev/backwards compatibility."
```

---

### Task 9: Update config-sample.php with documentation comments

**Files:**
- Modify: `config-sample.php`

- [ ] **Step 1: Add env-var documentation comments to config-sample.php**

Replace the class body in `config-sample.php` (lines 27-53):

```php
class Config
{
    // ------------------------------------------------------------------------
    // GENERAL SETTINGS
    // ------------------------------------------------------------------------
    // These are compile-time defaults only.
    // Environment variables override these at the point of use:
    //   EA_BASE_URL, EA_LANGUAGE, EA_DEBUG_MODE

    const BASE_URL = 'http://localhost';
    const LANGUAGE = 'english';
    const DEBUG_MODE = false;

    // ------------------------------------------------------------------------
    // DATABASE SETTINGS
    // ------------------------------------------------------------------------
    // Override with: EA_DB_HOST, EA_DB_NAME, EA_DB_USERNAME, EA_DB_PASSWORD

    const DB_HOST = 'mysql';
    const DB_NAME = 'easyappointments';
    const DB_USERNAME = 'user';
    const DB_PASSWORD = 'password';

    // ------------------------------------------------------------------------
    // GOOGLE CALENDAR SYNC
    // ------------------------------------------------------------------------
    // Override with: EA_GOOGLE_SYNC, EA_GOOGLE_CLIENT_ID, EA_GOOGLE_CLIENT_SECRET

    const GOOGLE_SYNC_FEATURE = false; // Enter TRUE or FALSE
    const GOOGLE_CLIENT_ID = '';
    const GOOGLE_CLIENT_SECRET = '';
}
```

- [ ] **Step 2: Commit**

```bash
git add config-sample.php
git commit -m "docs: add env-var override documentation to config-sample.php"
```

---

## Chunk 2: Production Docker Infrastructure

These tasks create the production Docker image, Nginx config, supervisord config, and entrypoint script.

### Task 10: Create .dockerignore

**Files:**
- Create: `.dockerignore`

- [ ] **Step 1: Create .dockerignore file**

```
# Dev Docker configs (keep docker/production/)
docker/php-fpm/
docker/nginx/
docker/mysql/
docker/baikal/
docker/openldap/

# Dev tools
docker-compose.yml
tests/
node_modules/
phpunit.xml
babel.config.json

# VCS and docs
.git/
.gitignore
docs/
*.md

# Runtime data (recreated in container)
storage/logs/*
storage/sessions/*
storage/cache/*

# IDE
.idea/
.DS_Store
```

- [ ] **Step 2: Commit**

```bash
git add .dockerignore
git commit -m "feat: add .dockerignore for production image builds

Excludes dev configs, tests, docs, and runtime data while
keeping docker/production/ for the production build."
```

---

### Task 11: Create production Nginx config

**Files:**
- Create: `docker/production/nginx.conf`

- [ ] **Step 1: Create the production Nginx config**

```nginx
server {
    listen 80 default;

    server_name _;

    client_max_body_size 20M;

    root /var/www/html;

    index index.php index.html;

    # Deny access to sensitive files
    location ~ /(config\.php|config-sample\.php|composer\.(json|lock)) {
        deny all;
        return 404;
    }

    location ~ ^/storage/ {
        deny all;
        return 404;
    }

    location ~ /\.ht {
        deny all;
    }

    # Static assets with cache headers
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # PHP handling
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ ^.+\.php {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_index index.php;
        include fastcgi_params;
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add docker/production/nginx.conf
git commit -m "feat: add production Nginx config

Denies access to config.php, composer files, and storage/.
Adds cache headers for static assets. Proxies PHP to FPM on 127.0.0.1:9000."
```

---

### Task 12: Create supervisord config

**Files:**
- Create: `docker/production/supervisord.conf`

- [ ] **Step 1: Create supervisord.conf**

```ini
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:php-fpm]
command=php-fpm --nodaemonize
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

- [ ] **Step 2: Commit**

```bash
git add docker/production/supervisord.conf
git commit -m "feat: add supervisord config for production container

Runs Nginx and PHP-FPM in foreground mode within a single container."
```

---

### Task 13: Create entrypoint script

**Files:**
- Create: `docker/production/entrypoint.sh`

- [ ] **Step 1: Create entrypoint.sh**

```bash
#!/bin/bash
set -e

echo ">>> Setting storage directory permissions"
chown -R www-data:www-data /var/www/html/storage

echo ">>> Running database migrations"
cd /var/www/html
php index.php console migrate || echo ">>> Migration skipped (database may not be initialized yet)"

echo ">>> Starting supervisord"
exec /usr/bin/supervisord -c /etc/supervisord.conf
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x docker/production/entrypoint.sh`

- [ ] **Step 3: Commit**

```bash
git add docker/production/entrypoint.sh
git commit -m "feat: add production container entrypoint script

Sets storage permissions, runs DB migrations automatically,
then starts supervisord. Migration failure is non-fatal for
first-time installs that use the /installation wizard."
```

---

### Task 14: Create production Dockerfile

**Files:**
- Create: `Dockerfile.production`

- [ ] **Step 1: Create the multi-stage Dockerfile**

```dockerfile
# =============================================================================
# Stage 1: Builder — install dependencies and compile assets
# =============================================================================
FROM php:8.4.3-fpm AS builder

WORKDIR /var/www/html

# Install system dependencies for building
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git zip unzip \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && curl -sLS https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first (Docker layer caching)
COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader --no-interaction

COPY package.json package-lock.json gulpfile.js babel.config.json ./
RUN npm ci

# Copy source and build assets
COPY . .
RUN npx gulp compile

# =============================================================================
# Stage 2: Production — minimal runtime image
# =============================================================================
FROM php:8.4.3-fpm-alpine3.21 AS production

WORKDIR /var/www/html

# Install runtime dependencies
RUN apk add --no-cache \
        nginx \
        supervisor \
        curl \
    && curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o /usr/local/bin/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions \
        gd intl ldap mbstring mysqli pdo_mysql soap xml zip bcmath gettext \
    && rm /usr/local/bin/install-php-extensions

# Copy application source
COPY --from=builder /var/www/html/application ./application
COPY --from=builder /var/www/html/system ./system
COPY --from=builder /var/www/html/index.php ./index.php
COPY --from=builder /var/www/html/config-sample.php ./config-sample.php
COPY --from=builder /var/www/html/patch.php ./patch.php

# Copy built assets and vendor
COPY --from=builder /var/www/html/assets ./assets
COPY --from=builder /var/www/html/vendor ./vendor

# Create storage directories with proper permissions
RUN mkdir -p /var/www/html/storage/{logs,cache,sessions,uploads,backups} \
    && chown -R www-data:www-data /var/www/html/storage

# Copy config.php from sample (env vars override at runtime)
RUN cp config-sample.php config.php

# Copy production configs
COPY docker/production/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/production/supervisord.conf /etc/supervisord.conf
COPY docker/production/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Remove default nginx config that conflicts
RUN rm -f /etc/nginx/http.d/default.conf.bak 2>/dev/null; true

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost/booking || exit 1

ENTRYPOINT ["/entrypoint.sh"]
```

- [ ] **Step 2: Verify the Dockerfile builds successfully**

Run: `docker build -f Dockerfile.production -t ea-production:test .`

Expected: Build completes with no errors. Final image is created.

- [ ] **Step 3: Verify the image runs and responds**

Run:
```bash
docker run -d --name ea-test \
  -p 8888:80 \
  -e EA_DB_HOST=host.docker.internal \
  -e EA_DB_NAME=easyappointments \
  -e EA_DB_USERNAME=user \
  -e EA_DB_PASSWORD=password \
  ea-production:test
sleep 10
curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/
```

Expected: `200` or `302` (redirect to installation if DB not set up)

- [ ] **Step 4: Cleanup test container**

Run: `docker stop ea-test && docker rm ea-test`

- [ ] **Step 5: Commit**

```bash
git add Dockerfile.production
git commit -m "feat: add multi-stage production Dockerfile

Two-stage build: builder installs deps and compiles assets,
production stage uses alpine with minimal runtime extensions.
Runs Nginx + PHP-FPM via supervisord. Entrypoint handles
migrations. Includes health check."
```

---

## Chunk 3: Provisioning Script and Final Verification

### Task 15: Create the provisioning script

**Files:**
- Create: `scripts/provision-instance.sh`

- [ ] **Step 1: Create the provisioning script**

```bash
#!/bin/bash
set -e

# =============================================================================
# EasyAppointments Instance Provisioner
#
# Creates a MySQL database and user for a new EasyAppointments instance,
# generates a unique encryption key, and outputs the env vars for Coolify.
#
# Usage: ./scripts/provision-instance.sh <product-name> [mysql-host] [mysql-root-password]
#
# Example: ./scripts/provision-instance.sh my-product localhost secret
# =============================================================================

PRODUCT_NAME="${1:?Usage: $0 <product-name> [mysql-host] [mysql-root-password]}"
MYSQL_HOST="${2:-localhost}"
MYSQL_ROOT_PASS="${3:-secret}"

# Sanitize product name (alphanumeric and hyphens only)
SANITIZED=$(echo "$PRODUCT_NAME" | tr -cd 'a-zA-Z0-9-' | tr '-' '_')
DB_NAME="ea_${SANITIZED}"
DB_USER="ea_${SANITIZED}"
DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
ENCRYPTION_KEY=$(openssl rand -base64 32)

echo "=== EasyAppointments Instance Provisioner ==="
echo ""
echo "Product:  ${PRODUCT_NAME}"
echo "Database: ${DB_NAME}"
echo "DB User:  ${DB_USER}"
echo ""

# Create database and user (idempotent)
mysql -h "${MYSQL_HOST}" -u root -p"${MYSQL_ROOT_PASS}" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci;

    CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';

    GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';

    FLUSH PRIVILEGES;
EOSQL

echo ""
echo "=== Database created successfully ==="
echo ""
echo "=== Coolify Environment Variables ==="
echo "Copy these into your Coolify service configuration:"
echo ""
echo "EA_BASE_URL=https://${PRODUCT_NAME}.bookings.yourdomain.com"
echo "EA_DB_HOST=${MYSQL_HOST}"
echo "EA_DB_NAME=${DB_NAME}"
echo "EA_DB_USERNAME=${DB_USER}"
echo "EA_DB_PASSWORD=${DB_PASS}"
echo "EA_ENCRYPTION_KEY=${ENCRYPTION_KEY}"
echo "EA_CORS_ORIGINS=https://app.${PRODUCT_NAME}.com"
echo "EA_FRAME_ANCESTORS=https://app.${PRODUCT_NAME}.com"
echo "EA_PROXY_IPS=172.16.0.0/12"
echo "# EA_SMTP_HOST="
echo "# EA_SMTP_USER="
echo "# EA_SMTP_PASS="
echo "# EA_SMTP_PORT=587"
echo "# EA_MAIL_FROM_ADDRESS="
echo "# EA_MAIL_FROM_NAME="
echo "# EA_GOOGLE_SYNC=false"
echo "# EA_GOOGLE_CLIENT_ID="
echo "# EA_GOOGLE_CLIENT_SECRET="
echo ""
echo "=== Next Steps ==="
echo "1. Deploy the service in Coolify with the env vars above"
echo "2. Visit https://${PRODUCT_NAME}.bookings.yourdomain.com/installation"
echo "3. Set up admin account, company name, and branding"
echo "4. Generate API token in Settings > API Token"
echo "5. Register webhooks for your product backend"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/provision-instance.sh`

- [ ] **Step 3: Verify script syntax**

Run: `bash -n scripts/provision-instance.sh`

Expected: No output (no syntax errors)

- [ ] **Step 4: Commit**

```bash
git add scripts/provision-instance.sh
git commit -m "feat: add instance provisioning script

Creates MySQL database and user for a new EasyAppointments instance.
Generates unique encryption key. Outputs all Coolify env vars.
Idempotent — safe to re-run."
```

---

### Task 16: Final integration verification

- [ ] **Step 1: Build the production image**

Run: `docker build -f Dockerfile.production -t ea-production:final .`

Expected: Build completes successfully.

- [ ] **Step 2: Run the production image with the dev MySQL**

Run:
```bash
docker compose up -d mysql
sleep 5
docker run -d --name ea-final-test \
  -p 8888:80 \
  --network easyappointments_default \
  -e EA_DB_HOST=mysql \
  -e EA_DB_NAME=easyappointments \
  -e EA_DB_USERNAME=user \
  -e EA_DB_PASSWORD=password \
  -e EA_ENCRYPTION_KEY=test-key-for-verification \
  -e EA_CORS_ORIGINS=http://localhost:3000 \
  ea-production:final
sleep 15
```

- [ ] **Step 3: Verify the app responds**

Run: `curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/booking`

Expected: `200` (booking page loads)

- [ ] **Step 4: Verify CORS headers work**

Run: `curl -s -H "Origin: http://localhost:3000" -I http://localhost:8888/api/v1/availabilities 2>&1 | grep -i 'access-control'`

Expected: `Access-Control-Allow-Origin: http://localhost:3000`

- [ ] **Step 5: Verify sensitive files are blocked**

Run:
```bash
curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/config.php
curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/composer.json
curl -s -o /dev/null -w '%{http_code}' http://localhost:8888/storage/logs/
```

Expected: All return `403` or `404`

- [ ] **Step 6: Cleanup test container**

Run: `docker stop ea-final-test && docker rm ea-final-test`

- [ ] **Step 7: Final commit — tag as ready**

```bash
git add -A
git status  # Verify nothing unexpected is staged
git commit -m "chore: multi-instance SaaS deployment infrastructure complete

Production Docker image, env-var config layer, CORS security,
SMTP support, provisioning script. Ready for Coolify deployment."
```

---

## Summary of All Files

| # | Action | File | Task |
|---|---|---|---|
| 1 | Modify | `application/config/database.php` | Task 1 |
| 2 | Modify | `application/config/google.php` | Task 2 |
| 3 | Modify | `application/config/app.php` | Task 3 |
| 4 | Modify | `application/config/email.php` | Task 4 |
| 5 | Modify | `application/config/config.php` | Task 5 |
| 6 | Modify | `index.php` | Task 6 |
| 7 | Modify | `application/libraries/Accounts.php` | Task 7 |
| 8 | Modify | `application/libraries/Ldap_client.php` | Task 7 |
| 9 | Modify | `application/config/routes.php` | Task 8 |
| 10 | Modify | `config-sample.php` | Task 9 |
| 11 | Create | `.dockerignore` | Task 10 |
| 12 | Create | `docker/production/nginx.conf` | Task 11 |
| 13 | Create | `docker/production/supervisord.conf` | Task 12 |
| 14 | Create | `docker/production/entrypoint.sh` | Task 13 |
| 15 | Create | `Dockerfile.production` | Task 14 |
| 16 | Create | `scripts/provision-instance.sh` | Task 15 |
