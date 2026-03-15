#!/bin/bash
set -e

# =============================================================================
# EasyAppointments Database Backup Script
#
# Backs up all ea_* databases. Designed to be run as an hourly cron job.
#
# Config lookup order (first found wins):
#   1. EA_BACKUP_ENV_FILE env var (explicit override)
#   2. /etc/ea-backup.env          (written by setup-backup-cron.sh on VPS)
#   3. <script-dir>/.env           (scripts/.env in the repo, for local use)
#
# Retention per database:
#   - 24 hourly backups (rolling 1-day window)
#   - 8 weekly backups  (promoted from hourly each Sunday at 00:xx)
#
# Usage (manual): ./scripts/backup-databases.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Locate and source the config file ---------------------------------------
# Only sets variables that are NOT already in the environment, so explicit
# overrides like `BACKUP_DIR=/tmp bash backup-databases.sh` are preserved.
_load_env() {
    local f="$1"
    [ -n "$f" ] && [ -f "$f" ] || return 1
    local key val line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in '#'*|'') continue ;; esac          # skip comments/blank
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            [ -z "${!key+isset}" ] && export "${key}=${val}"  # skip if already set
        fi
    done < "$f"
    return 0
}

_load_env "${EA_BACKUP_ENV_FILE:-}" \
    || _load_env "/etc/ea-backup.env" \
    || _load_env "${SCRIPT_DIR}/.env" \
    || true   # proceed — required vars checked explicitly below

# --- Required configuration --------------------------------------------------
: "${MYSQL_HOST:?Missing MYSQL_HOST — set it in scripts/.env or /etc/ea-backup.env}"
: "${MYSQL_ADMIN_USER:?Missing MYSQL_ADMIN_USER — set it in scripts/.env or /etc/ea-backup.env}"
: "${MYSQL_ADMIN_PASS:?Missing MYSQL_ADMIN_PASS — set it in scripts/.env or /etc/ea-backup.env}"

MYSQL_PORT="${MYSQL_PORT:-3306}"

# --- Optional configuration --------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/ea-mysql}"
KEEP_HOURLY="${KEEP_HOURLY:-24}"
KEEP_WEEKLY="${KEEP_WEEKLY:-8}"
LOG_FILE="${LOG_FILE:-/var/log/ea-backup.log}"

# --- SSL: required for any non-localhost host (e.g. Aiven) -------------------
if [ "$MYSQL_HOST" = "localhost" ] || [ "$MYSQL_HOST" = "127.0.0.1" ]; then
    SSL_MODE_FLAG=""
else
    SSL_MODE_FLAG="--ssl-mode=REQUIRED"
fi

# --column-statistics=0 was added in mysqldump 8.0 to suppress histogram errors.
# MySQL 5.7 does not recognise it and will exit with an error, so only add it
# when the installed mysqldump is version 8 or higher.
MYSQLDUMP_MAJOR=$(mysqldump --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
if [ "${MYSQLDUMP_MAJOR:-0}" -ge 8 ]; then
    COL_STATS_FLAG="--column-statistics=0"
else
    COL_STATS_FLAG=""
fi

TIMESTAMP=$(date +%Y-%m-%d_%H-%M)
WEEKDAY=$(date +%u)   # 1=Mon … 7=Sun
HOUR=$(date +%H)

# --- Logging helper ----------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- Ensure backup root exists -----------------------------------------------
mkdir -p "$BACKUP_DIR"

log "=== EA Database Backup Started (${MYSQL_HOST}:${MYSQL_PORT}) ==="

# --- Discover all ea_* databases ---------------------------------------------
# NOTE: Each flag is a discrete quoted argument — no MYSQL_FLAGS variable —
# to avoid word-splitting bugs when host/password contain special characters.
DATABASES=$(mysql \
    -h "${MYSQL_HOST}" \
    -P "${MYSQL_PORT}" \
    -u "${MYSQL_ADMIN_USER}" \
    -p"${MYSQL_ADMIN_PASS}" \
    ${SSL_MODE_FLAG} \
    --batch --skip-column-names \
    -e "SHOW DATABASES LIKE 'ea\_%';" 2>/dev/null) || {
    log "ERROR: Could not connect to MySQL at ${MYSQL_HOST}:${MYSQL_PORT}"
    exit 1
}

if [ -z "$DATABASES" ]; then
    log "WARNING: No ea_* databases found. Nothing to back up."
    exit 0
fi

# --- Back up each database ---------------------------------------------------
BACKED_UP=0
FAILED=0

for DB in $DATABASES; do
    DB_BACKUP_DIR="${BACKUP_DIR}/${DB}/hourly"
    DB_WEEKLY_DIR="${BACKUP_DIR}/${DB}/weekly"
    mkdir -p "$DB_BACKUP_DIR" "$DB_WEEKLY_DIR"

    DUMP_FILE="${DB_BACKUP_DIR}/${DB}_${TIMESTAMP}.sql.gz"

    log "Backing up: ${DB} → ${DUMP_FILE}"

    # mysqldump flags:
    #   --single-transaction  consistent InnoDB snapshot (no table locks)
    #   --routines            include stored procedures/functions
    #   --events              include scheduled events
    #   --column-statistics=0 suppress MySQL 8 histogram stats errors
    if mysqldump \
        -h "${MYSQL_HOST}" \
        -P "${MYSQL_PORT}" \
        -u "${MYSQL_ADMIN_USER}" \
        -p"${MYSQL_ADMIN_PASS}" \
        ${SSL_MODE_FLAG} \
        --single-transaction \
        --routines \
        --events \
        ${COL_STATS_FLAG} \
        "${DB}" 2>>"$LOG_FILE" | gzip > "${DUMP_FILE}"; then

        SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
        log "  OK (${SIZE})"
        BACKED_UP=$((BACKED_UP + 1))

        # --- Promote to weekly on Sunday at midnight (00:xx) -----------------
        if [ "$WEEKDAY" = "7" ] && [ "$HOUR" = "00" ]; then
            WEEKLY_FILE="${DB_WEEKLY_DIR}/${DB}_week-$(date +%Y-W%V).sql.gz"
            cp "$DUMP_FILE" "$WEEKLY_FILE"
            log "  Promoted to weekly: ${WEEKLY_FILE}"

            # Rotate weekly — keep newest KEEP_WEEKLY, delete the rest
            ls -1t "${DB_WEEKLY_DIR}"/*.sql.gz 2>/dev/null \
                | tail -n +$((KEEP_WEEKLY + 1)) \
                | xargs -r rm -f --
        fi

        # --- Rotate hourly — keep newest KEEP_HOURLY, delete the rest --------
        ls -1t "${DB_BACKUP_DIR}"/*.sql.gz 2>/dev/null \
            | tail -n +$((KEEP_HOURLY + 1)) \
            | xargs -r rm -f --

    else
        log "  FAILED: ${DB}"
        rm -f "${DUMP_FILE}"   # remove partial/empty dump
        FAILED=$((FAILED + 1))
    fi
done

log "=== Backup Complete: ${BACKED_UP} succeeded, ${FAILED} failed ==="

# Exit non-zero if any database failed so cron can report the error via MAILTO
[ "$FAILED" -eq 0 ] || exit 1
