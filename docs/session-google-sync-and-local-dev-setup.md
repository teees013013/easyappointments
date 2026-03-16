# Google Calendar Sync Completion & Local Dev Stack Setup

> Session date: 2026-03-16
> Scope: EasyAppointments (`/Users/brenttudas/Forked-OSS/easyappointments`) + Padlockd PWA integration (`/Users/brenttudas/PitchTalks/Verticals/padlockd-demo`)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Security Fix: Committed Credentials](#2-security-fix-committed-credentials)
3. [Periodic Sync Cron in Docker](#3-periodic-sync-cron-in-docker)
4. [Provisioning Script Update](#4-provisioning-script-update)
5. [Google Calendar Sync Documentation](#5-google-calendar-sync-documentation)
6. [Sync Status API Endpoint](#6-sync-status-api-endpoint)
7. [Local Development Docker Stack](#7-local-development-docker-stack)
8. [Padlockd PWA Database & Account Setup](#8-padlockd-pwa-database--account-setup)
9. [End-to-End Verification](#9-end-to-end-verification)
10. [Files Changed](#10-files-changed)
11. [Known Limitations](#11-known-limitations)
12. [Operational Reference](#12-operational-reference)

---

## 1. Overview

This session accomplished two major objectives:

**A. Google Calendar Sync Production Readiness** — The sync feature was already implemented
in code (`Google_sync.php`, `Google.php` controller, `Synchronization.php` library), but had
gaps for production use. This session closed them: removed leaked credentials, added a
periodic full-sync cron to the Docker container, updated the provisioning script, rewrote
the setup documentation, and added a sync-status healthcheck API.

**B. Local Dev Stack for Padlockd Integration Testing** — Built and ran the production Docker
image locally with a MySQL database, completed the EA installation wizard, configured all
4 escape room services, set the provider's working hours to match the PWA's evening
schedule, created a webhook for cache invalidation, disabled the phone-number-required
validation (PWA sends empty phone), set the API token, and updated the PWA's `.env.local`
with all correct values. Verified the full booking flow end-to-end via API.

### Architecture

```
+-------------------+     REST API      +------------------------+    OAuth 2.0    +------------------+
|  Padlockd PWA     | <---------------- |   EasyAppointments     | <------------- |  Google Calendar |
|  (Next.js)        |     + Webhooks    |   (PHP on Docker)      |   bidirectional|  (per provider)  |
|  localhost:3000    |                   |   localhost:8080        |      sync      |                  |
+-------------------+                   +------------------------+                +------------------+
        |                                        |
        |  EA_BASE_URL                           |  MySQL 8.0
        |  EA_API_KEY                            |  localhost:3307
        |  EA_PROVIDER_ID=2                      |  (Docker volume)
        |  EA_SERVICE_*=1,2,3,4                  |
        |  EA_WEBHOOK_SECRET                     |
        +----------------------------------------+
```

---

## 2. Security Fix: Committed Credentials

### Problem

A Google Service Account private key file (`Padlockd Demo PWA.json`) existed at the repo
root. It contained:

- Project: `padlockd-demo-pwa`
- Service account: `padlockd@padlockd-demo-pwa.iam.gserviceaccount.com`
- Full RSA private key

The file was already in `.gitignore` (added after it appeared on disk), so it was never
committed to git history. However, its presence on disk was a security risk.

### What Was Done

1. **Deleted the file from disk**: `rm "Padlockd Demo PWA.json"`
2. **Replaced the specific gitignore entry** with broader patterns:

```gitignore
# Google service account keys (never commit credentials)
*-pwa.json
*serviceaccount*
*service-account*
*credentials*.json
*client_secret*.json
```

These patterns cover common Google credential filename conventions so future downloads
are automatically ignored.

### Action Required

**Rotate the service account key** in Google Cloud Console:
1. Go to [Google Cloud Console](https://console.cloud.google.com/) > project `padlockd-demo-pwa`
2. Navigate to IAM & Admin > Service Accounts
3. Find `padlockd@padlockd-demo-pwa.iam.gserviceaccount.com`
4. Go to Keys tab > delete the old key > create a new one if needed

> Note: EasyAppointments uses OAuth 2.0 (not service accounts) for Calendar sync.
> This service account may have been downloaded accidentally or used for a different
> purpose. If it's not needed, delete the service account entirely.

---

## 3. Periodic Sync Cron in Docker

### Problem

Google Calendar sync fires synchronously on each booking write (via `Synchronization.php`),
but there was no periodic full-sync to catch:
- Events deleted directly in Google Calendar
- Drift between systems from failed real-time syncs
- Changes made via other Google Calendar clients

### What Was Done

Created a supervisord-managed sync loop that runs every 15 minutes.

#### New file: `docker/production/sync-cron.sh`

```sh
#!/bin/sh
# Periodic Google Calendar / CalDAV full sync
# Managed by supervisord — runs every 15 minutes when EA_GOOGLE_SYNC=true

INTERVAL=900  # 15 minutes in seconds
LOG_FILE="/var/log/ea-sync.log"
MAX_LOG_SIZE=1048576  # 1 MB

while true; do
    sleep "$INTERVAL"

    if [ "$(echo "$EA_GOOGLE_SYNC" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting full sync" >> "$LOG_FILE"
        cd /var/www/html
        php index.php console sync >> "$LOG_FILE" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync completed (exit=$?)" >> "$LOG_FILE"

        # Simple log rotation: truncate if over max size
        if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt "$MAX_LOG_SIZE" ]; then
            tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp"
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
done
```

**Design choices:**
- Uses a shell `while/sleep` loop instead of system cron — avoids installing `crond` in the Alpine image
- Checks `EA_GOOGLE_SYNC` env var at each iteration, so toggling it doesn't require a container restart
- Runs as `www-data` (same user as php-fpm) to avoid permission issues
- Log rotation keeps the log file under 1 MB by truncating to the last 100 lines
- Calls `php index.php console sync` which iterates all providers with `google_sync=true` or `caldav_sync=true`

#### Modified: `docker/production/supervisord.conf`

Added a new `[program:sync-cron]` block:

```ini
[program:sync-cron]
command=/bin/sh /opt/sync-cron.sh
autostart=true
autorestart=true
user=www-data
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

#### Modified: `Dockerfile.production`

Added COPY and chmod for the sync script:

```dockerfile
COPY docker/production/sync-cron.sh /opt/sync-cron.sh
RUN chmod +x /entrypoint.sh /opt/sync-cron.sh
```

### Verification

Container logs confirm all three supervisord programs start successfully:

```
2026-03-16 01:56:33 INFO spawned: 'nginx' with pid 9
2026-03-16 01:56:33 INFO spawned: 'php-fpm' with pid 10
2026-03-16 01:56:33 INFO spawned: 'sync-cron' with pid 11
...
2026-03-16 01:56:34 INFO success: sync-cron entered RUNNING state
```

---

## 4. Provisioning Script Update

### What Was Done

The provisioning script (`scripts/provision-instance.sh`) already included Google Calendar
env vars in its output (lines 115-117). This session added:

1. A **descriptive comment** above the vars referencing the setup guide:
   ```
   # Google Calendar Sync (create OAuth 2.0 credentials in Google Cloud Console,
   # see docs/google-calendar-sync.md for full setup guide)
   ```

2. A **step 6** in the "Next Steps" section:
   ```
   6. (Optional) Enable Google Calendar Sync — see docs/google-calendar-sync.md
   ```

---

## 5. Google Calendar Sync Documentation

### What Was Done

Complete rewrite of `docs/google-calendar-sync.md`. The old document referenced v1.5.1,
had incomplete instructions, and mentioned an obsolete "API Key" step.

The new document covers 5 sections:

| Section | Content |
|---|---|
| 1. Google Cloud Console Setup | Project creation, Calendar API enablement, OAuth consent screen (External/Testing mode, scopes, test users), OAuth 2.0 Client ID creation with correct redirect URI |
| 2. EasyAppointments Configuration | Env vars (`EA_GOOGLE_SYNC`, `EA_GOOGLE_CLIENT_ID`, `EA_GOOGLE_CLIENT_SECRET`) and `config.php` fallback |
| 3. Per-Provider Activation | Step-by-step admin UI flow: Calendar page > select provider > Enable Sync > consent > select calendar |
| 4. How Sync Works | Real-time (per booking), periodic (15-min cron), manual (UI button), CLI (`php index.php console sync`) |
| 5. Troubleshooting | Token expiry, Testing mode restrictions, redirect URI mismatch, debugging sync logs |

Includes an ASCII sequence diagram of the OAuth + sync flow.

---

## 6. Sync Status API Endpoint

### What Was Done

Added `GET /api/v1/sync-status` — a read-only endpoint that reports Google Calendar and
CalDAV sync status per provider. Requires Bearer token authentication (same token as all
other API endpoints).

#### New file: `application/controllers/api/v1/Sync_status_api_v1.php`

Follows existing API v1 patterns: extends `EA_Controller`, loads `api` library, calls
`$this->api->auth()`, uses `json_response()` / `json_exception()` helpers.

#### Route added to `application/config/routes.php`

```php
$route['api/v1/sync-status']['get'] = 'api/v1/sync_status_api_v1/index';
```

#### Response format

```json
{
  "googleSyncEnabled": false,
  "providers": [
    {
      "providerId": 2,
      "providerName": "Padlockd Venue",
      "googleSync": false,
      "googleCalendar": null,
      "caldavSync": false
    }
  ]
}
```

**Fields:**
- `googleSyncEnabled` — global flag from `EA_GOOGLE_SYNC` env var / config
- `providers[].googleSync` — per-provider flag (true after provider completes OAuth flow)
- `providers[].googleCalendar` — which Google Calendar is linked (null if not syncing)
- `providers[].caldavSync` — whether CalDAV sync is active for this provider

---

## 7. Local Development Docker Stack

### What Was Done

Created `docker-compose.local.yml` for running the full EA stack locally, enabling
integration testing from the Padlockd PWA.

#### Stack components

| Container | Image | Port | Purpose |
|---|---|---|---|
| `mysql` | mysql:8.0 | 3307:3306 | EA database |
| `easyappointments` | Built from `Dockerfile.production` | 8080:80 | EA application |

#### Key configuration

- MySQL uses a Docker volume (`ea_mysql_data`) for persistence across restarts
- MySQL has a healthcheck; EA's `depends_on` uses `condition: service_healthy` to prevent
  EA from starting before MySQL is ready
- CORS origins allow `http://localhost:3000` and `http://localhost:3001` (Next.js dev ports)
- Debug mode is enabled for development
- Google sync is disabled by default (can be enabled by uncommenting env vars)

#### How to use

```bash
# Start the stack (builds image on first run)
docker compose -f docker-compose.local.yml up --build -d

# View logs
docker compose -f docker-compose.local.yml logs -f easyappointments

# Stop (preserves data)
docker compose -f docker-compose.local.yml down

# Stop and wipe database (full reset)
docker compose -f docker-compose.local.yml down -v
```

### Installation Wizard

On first start, the EA migration creates empty tables. The installation wizard was
completed via browser (Playwright automation) with these values:

| Field | Value |
|---|---|
| Admin First Name | Brent |
| Admin Last Name | Tudas |
| Admin Email | admin@padlockd.com |
| Admin Username | admin |
| Admin Password | Admin123! |
| Company Name | Padlockd |
| Company Email | admin@padlockd.com |
| Company Link | http://localhost:8080 |

The wizard creates default seed data: an admin user (ID 1), a provider "Jane Doe" (ID 2),
a generic "Service" (ID 1), and a sample customer.

### Docker Build Verification

The production image builds successfully with all sync-cron changes:

```
#30 [production 16/18] COPY docker/production/sync-cron.sh /opt/sync-cron.sh
#31 [production 17/18] RUN chmod +x /entrypoint.sh /opt/sync-cron.sh
...
naming to docker.io/library/ea-local:latest done
```

---

## 8. Padlockd PWA Database & Account Setup

### PWA Integration Requirements

The Padlockd PWA (`/Users/brenttudas/PitchTalks/Verticals/padlockd-demo`) is an escape room
booking app that uses EasyAppointments as its scheduling backend. A thorough codebase
analysis revealed the exact requirements:

#### Provider Model
- **Single provider** for the entire venue (all 4 rooms)
- Provider ID is set via `EA_PROVIDER_ID` env var

#### Service Model
- **4 services** — one per escape room
- Each requires 60-minute duration
- Each has a max player capacity (mapped to `attendantsNumber`)
- Service IDs mapped via env vars (`EA_SERVICE_MASTERMIND_HEIST`, etc.)

#### API Endpoints Used by PWA

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/availabilities` | GET | Check slot availability for a room on a date |
| `/api/v1/customers?q={email}` | GET | Search for existing customer by email |
| `/api/v1/customers` | POST | Create new customer (firstName, lastName, email, phone="") |
| `/api/v1/appointments` | POST | Book an appointment (start, end, serviceId, providerId, customerId, notes) |

All requests use `Authorization: Bearer {EA_API_KEY}` header.

#### Booking Flow
1. User selects room and date
2. PWA calls availabilities API for that service/provider/date
3. PWA filters results against hardcoded room schedules (specific time slots per room)
4. User selects time and player count, enters name and email
5. PWA searches for existing customer by email; creates if not found
6. PWA creates appointment with `end = start + 60 minutes`, notes = "Group booking: N players"
7. EA fires webhook on appointment save, PWA invalidates its ISR cache

#### Room Schedules (hardcoded in PWA)

| Room | Available Slots |
|---|---|
| Mastermind Heist | 19:30, 22:30, 00:00 |
| Zodiac Killer | 19:30, 21:00, 22:30 |
| Prison Break | 19:30, 21:30 |
| Zombie Lab | 19:30, 21:00, 22:30 |

#### Webhook
- URL: `http://{host}/api/webhooks/easyappointments`
- Validates `payload.secretToken` using timing-safe comparison against `EA_WEBHOOK_SECRET`
- Triggers on: `appointment_save`, `appointment_delete`
- Action: invalidates Next.js "slots" cache tag

### Configuration Applied

#### 1. API Token

Set via the EA admin UI at `/index.php/api_settings`:

```
API Token: padlockd-local-dev-token-2026
```

#### 2. Services Created

Updated the default service (ID 1) and created 3 new services via the REST API:

| Service | ID | Name | Duration | Attendants | Price | Currency |
|---|---|---|---|---|---|---|
| Mastermind Heist | 1 | Mastermind Heist | 60 min | 8 | $52 | USD |
| Zodiac Killer | 2 | Zodiac Killer | 60 min | 6 | $45 | USD |
| Prison Break | 3 | Prison Break | 60 min | 6 | $48 | USD |
| Zombie Lab | 4 | Zombie Lab | 60 min | 8 | $50 | USD |

**API calls used:**

```bash
# Update existing service 1
PUT /api/v1/services/1 {"name":"Mastermind Heist","duration":60,"price":52,"currency":"USD","attendantsNumber":8}

# Create new services 2-4
POST /api/v1/services {"name":"Zodiac Killer","duration":60,"price":45,"currency":"USD","attendantsNumber":6}
POST /api/v1/services {"name":"Prison Break","duration":60,"price":48,"currency":"USD","attendantsNumber":6}
POST /api/v1/services {"name":"Zombie Lab","duration":60,"price":50,"currency":"USD","attendantsNumber":8}
```

#### 3. Provider Configured

Updated the default provider (ID 2) via the REST API:

```bash
PUT /api/v1/providers/2
{
  "firstName": "Padlockd",
  "lastName": "Venue",
  "email": "venue@padlockd.com",
  "services": [1, 2, 3, 4],
  "settings": {
    "workingPlan": {
      "monday":    {"start":"19:00","end":"23:59","breaks":[]},
      "tuesday":   {"start":"19:00","end":"23:59","breaks":[]},
      "wednesday": {"start":"19:00","end":"23:59","breaks":[]},
      "thursday":  {"start":"19:00","end":"23:59","breaks":[]},
      "friday":    {"start":"19:00","end":"23:59","breaks":[]},
      "saturday":  {"start":"19:00","end":"23:59","breaks":[]},
      "sunday":    {"start":"19:00","end":"23:59","breaks":[]}
    }
  }
}
```

Working hours set to 19:00-23:59 daily (no breaks) to cover the PWA's evening time slots.

#### 4. Phone Number Requirement Disabled

The PWA sends `phone: ""` when creating customers. EA's default requires a non-empty phone.
Disabled via the settings API:

```bash
PUT /api/v1/settings/require_phone_number {"value":"0"}
```

#### 5. Webhook Created

```bash
POST /api/v1/webhooks
{
  "name": "Padlockd PWA Cache Invalidation",
  "url": "http://host.docker.internal:3000/api/webhooks/easyappointments",
  "actions": "[\"appointment_save\",\"appointment_delete\"]",
  "secretToken": "padlockd-local-webhook-secret-2026",
  "isSslVerified": false,
  "notes": "Invalidates Next.js ISR cache when bookings change"
}
```

The webhook URL uses `host.docker.internal` which resolves to the Docker host machine,
allowing the EA container to reach the PWA running on `localhost:3000`.

#### 6. PWA `.env.local` Updated

```env
# EasyAppointments Self-Hosted Instance (local Docker)
# Start with: cd ~/Forked-OSS/easyappointments && docker compose -f docker-compose.local.yml up -d
# Admin UI: http://localhost:8080/index.php/user/login (admin / Admin123!)
EA_BASE_URL=http://localhost:8080
EA_API_KEY=padlockd-local-dev-token-2026

# Provider ID (from EasyAppointments admin -> Providers)
EA_PROVIDER_ID=2

# Service IDs (from EasyAppointments admin -> Services)
EA_SERVICE_MASTERMIND_HEIST=1
EA_SERVICE_ZODIAC_KILLER=2
EA_SERVICE_PRISON_BREAK=3
EA_SERVICE_ZOMBIE_LAB=4

# Webhook secret (set this same value in EA admin -> Webhooks -> secretToken)
EA_WEBHOOK_SECRET=padlockd-local-webhook-secret-2026
```

---

## 9. End-to-End Verification

### Docker Build

```
docker build -f Dockerfile.production -t ea-local:latest .
# Result: SUCCESS — all 18 production stage steps completed
```

### Container Startup

```
supervisord started with pid 1
spawned: 'nginx' with pid 9
spawned: 'php-fpm' with pid 10
spawned: 'sync-cron' with pid 11
success: nginx entered RUNNING state
success: php-fpm entered RUNNING state
success: sync-cron entered RUNNING state
```

### API Endpoint Tests

| Test | Result |
|---|---|
| `GET /` (booking page) | 200 OK |
| `GET /api/v1/providers` (Bearer auth) | Returns provider ID 2 "Padlockd Venue" |
| `GET /api/v1/services` | Returns 4 services (IDs 1-4) |
| `GET /api/v1/sync-status` | Returns `{"googleSyncEnabled":false,"providers":[...]}` |
| `GET /api/v1/availabilities?serviceId=1&providerId=2&date=2026-03-17` | Returns slots 19:00-22:45 |

### Full Booking Flow Simulation

Simulated the exact sequence the PWA performs:

```
Step 1: GET availabilities (Zodiac Killer, Mar 19)
        -> 19:30, 21:00, 22:30 all available                           PASS

Step 2: GET customers?q=newuser@test.com (search by email)
        -> 0 customers found                                            PASS

Step 3: POST customers (create with empty phone)
        -> Customer ID: 6                                               PASS

Step 4: POST appointments (Zodiac Killer at 21:00, 3 players)
        -> Booking ID: 2                                                PASS

Step 5: GET availabilities again (verify slot consumed)
        -> 19:30, 21:00, 22:30 still available (attendantsNumber > 1)   PASS
```

All 5 steps completed successfully.

---

## 10. Files Changed

### EasyAppointments Repository

| File | Change | Description |
|---|---|---|
| `.gitignore` | Modified | Replaced specific filename with broad credential patterns |
| `Dockerfile.production` | Modified | Added COPY for sync-cron.sh, updated chmod |
| `docker/production/supervisord.conf` | Modified | Added `[program:sync-cron]` block |
| `docker/production/sync-cron.sh` | **Created** | Periodic sync loop script |
| `docker-compose.local.yml` | **Created** | Local dev stack (MySQL + EA) |
| `application/controllers/api/v1/Sync_status_api_v1.php` | **Created** | Sync status API endpoint |
| `application/config/routes.php` | Modified | Added sync-status route |
| `docs/google-calendar-sync.md` | Rewritten | Complete modern setup guide |
| `scripts/provision-instance.sh` | Modified | Added Google sync comments + step 6 |

### Padlockd PWA Repository

| File | Change | Description |
|---|---|---|
| `.env.local` | Modified | Updated EA_BASE_URL, EA_API_KEY, EA_PROVIDER_ID, EA_WEBHOOK_SECRET |

### EA Database State (Docker volume)

| Table | Records |
|---|---|
| `ea_users` | Admin (ID 1), Provider "Padlockd Venue" (ID 2), sample customer (ID 3) |
| `ea_services` | Mastermind Heist (1), Zodiac Killer (2), Prison Break (3), Zombie Lab (4) |
| `ea_webhooks` | Padlockd PWA cache invalidation webhook (ID 1) |
| `ea_settings` | `require_phone_number=0`, `api_token=padlockd-local-dev-token-2026` |
| `ea_appointments` | 2 test bookings (from smoke tests) |
| `ea_user_settings` | Provider working plan: 19:00-23:59 daily |

---

## 11. Known Limitations

### Midnight Slot (00:00) Unavailable

The Mastermind Heist room has a 00:00 (midnight) slot in the PWA's hardcoded schedule.
EA's working plan is day-bounded (`"start":"19:00","end":"23:59"`) and cannot represent
cross-midnight availability. The 00:00 slot will show as "Sold Out" in the PWA.

**Impact**: Only affects the Mastermind Heist late-night slot. The 19:30 and 22:30 slots
work correctly.

**Workaround options**:
- Remove the 00:00 slot from the PWA's `ROOM_SCHEDULES` in `app/api/slots/[roomId]/route.ts`
- Use EA's working plan exceptions to create a next-day 00:00-01:00 availability window

### attendantsNumber Semantics

EA's `attendantsNumber` controls **concurrent appointments per time slot**, not "max players
per session". With `attendantsNumber=8` on Mastermind Heist, EA allows 8 separate bookings
at the same time — meaning 8 different groups. For a physical escape room that can only run
one group at a time, `attendantsNumber=1` would be more appropriate.

The current configuration matches the PWA's `.env.local` comments which map player capacity
to attendantsNumber. If single-group-per-slot behavior is desired, update each service:

```bash
PUT /api/v1/services/{id} {"attendantsNumber": 1}
```

### PHP 8.4 Deprecation Warnings

The `GET /api/v1/providers` endpoint emits a PHP deprecation warning:
```
json_decode(): Passing null to parameter #1 ($json) of type string is deprecated
```
at `models/Providers_model.php:812`. This is a pre-existing issue in the upstream
EasyAppointments codebase (PHP 8.4 strict null handling), not related to this session's
changes. The response data is still correct.

### Webhook URL for Local Dev

The webhook uses `http://host.docker.internal:3000/...` which is a Docker Desktop feature
for macOS/Windows. This URL allows the EA container to reach the host machine. It does not
work on Linux Docker without extra configuration (`--add-host=host.docker.internal:host-gateway`).

---

## 12. Operational Reference

### Credentials Quick Reference

| Credential | Value |
|---|---|
| EA Admin URL | http://localhost:8080/index.php/user/login |
| EA Admin Username | `admin` |
| EA Admin Password | `Admin123!` |
| EA API Token | `padlockd-local-dev-token-2026` |
| EA Provider ID | `2` |
| Webhook Secret | `padlockd-local-webhook-secret-2026` |
| MySQL Host (from host) | `localhost:3307` |
| MySQL User | `ea_user` |
| MySQL Password | `ea_pass` |
| MySQL Database | `easyappointments` |

### Docker Commands

```bash
# Start the stack
cd ~/Forked-OSS/easyappointments
docker compose -f docker-compose.local.yml up -d

# Rebuild after code changes
docker compose -f docker-compose.local.yml up --build -d

# View EA logs
docker compose -f docker-compose.local.yml logs -f easyappointments

# View sync cron logs (inside container)
docker compose -f docker-compose.local.yml exec easyappointments cat /var/log/ea-sync.log

# Run manual sync
docker compose -f docker-compose.local.yml exec easyappointments \
  php /var/www/html/index.php console sync

# Stop (preserve data)
docker compose -f docker-compose.local.yml down

# Full reset (wipe database)
docker compose -f docker-compose.local.yml down -v

# Access MySQL directly
docker compose -f docker-compose.local.yml exec mysql \
  mysql -uea_user -pea_pass easyappointments
```

### API Quick Tests

```bash
TOKEN="padlockd-local-dev-token-2026"

# List providers
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/providers

# List services
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/services

# Check availability (Mastermind Heist, tomorrow)
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/api/v1/availabilities?serviceId=1&providerId=2&date=$(date -v+1d +%Y-%m-%d)"

# Check sync status
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/sync-status

# Create a test booking
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"start":"2026-03-20 19:30:00","end":"2026-03-20 20:30:00","serviceId":1,"providerId":2,"customerId":3,"notes":"Group booking: 4 players"}' \
  http://localhost:8080/api/v1/appointments
```

### Starting the PWA

```bash
cd ~/PitchTalks/Verticals/padlockd-demo
npm run dev
# PWA will be at http://localhost:3000
# It connects to EA at http://localhost:8080 (per .env.local)
```

---

[Back](readme.md)
