#!/bin/bash
set -e

# =============================================================================
# EasyAppointments Backup Cron Installer
#
# Installs backup-databases.sh as an hourly cron job on your Coolify VPS.
# Run this once on the server after cloning the repo.
#
# If scripts/.env exists, values are pre-populated — just press Enter to accept.
# Otherwise, you will be prompted for each value.
#
# Usage: sudo ./scripts/setup-backup-cron.sh
#
# What it does:
#   1. Reads connection details from scripts/.env (with interactive fallback)
#   2. Writes /etc/ea-backup.env with those credentials (mode 600, root-only)
#   3. Copies backup-databases.sh to /usr/local/bin/ea-backup
#   4. Installs /etc/cron.d/ea-backup (runs at :05 every hour)
#   5. Runs a test backup immediately to verify connectivity
# =============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root (sudo ./scripts/setup-backup-cron.sh)" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_ENV="${SCRIPT_DIR}/.env"
SERVER_ENV="/etc/ea-backup.env"
BACKUP_SCRIPT="/usr/local/bin/ea-backup"
LOG_FILE_DEFAULT="/var/log/ea-backup.log"
CRON_FILE="/etc/cron.d/ea-backup"

# --- Pre-populate from scripts/.env if present -------------------------------
if [ -f "$LOCAL_ENV" ]; then
    set -o allexport
    # shellcheck disable=SC1090
    source "$LOCAL_ENV"
    set +o allexport
    echo "✓ Loaded defaults from ${LOCAL_ENV}"
fi

echo ""
echo "=== EasyAppointments Backup Cron Installer ==="
echo "Press Enter to accept the value shown in [brackets], or type a new one."
echo ""

# --- Prompt for each value with pre-populated defaults -----------------------
prompt() {
    local var_name="$1"
    local label="$2"
    local current_val="${!var_name}"
    local input

    if [ -n "$current_val" ]; then
        read -rp "${label} [${current_val}]: " input
        printf '%s' "${input:-$current_val}"
    else
        read -rp "${label}: " input
        printf '%s' "$input"
    fi
}

prompt_secret() {
    local var_name="$1"
    local label="$2"
    local current_val="${!var_name}"
    local input

    if [ -n "$current_val" ]; then
        # Show masked hint so user knows a value is pre-loaded
        read -rsp "${label} [loaded from .env — press Enter to keep]: " input
        echo ""
        printf '%s' "${input:-$current_val}"
    else
        read -rsp "${label}: " input
        echo ""
        printf '%s' "$input"
    fi
}

INPUT_HOST=$(prompt MYSQL_HOST "MySQL host")
INPUT_PORT=$(prompt MYSQL_PORT "MySQL port")
INPUT_USER=$(prompt MYSQL_ADMIN_USER "MySQL admin user")
INPUT_PASS=$(prompt_secret MYSQL_ADMIN_PASS "MySQL admin password")
INPUT_DIR=$(prompt BACKUP_DIR "Backup directory")
INPUT_KEEP_H=$(prompt KEEP_HOURLY "Keep hourly backups (per DB)")
INPUT_KEEP_W=$(prompt KEEP_WEEKLY "Keep weekly backups (per DB)")

# Apply fallback defaults for optional fields that may still be empty
INPUT_PORT="${INPUT_PORT:-12476}"
INPUT_USER="${INPUT_USER:-avnadmin}"
INPUT_DIR="${INPUT_DIR:-/opt/backups/ea-mysql}"
INPUT_KEEP_H="${INPUT_KEEP_H:-24}"
INPUT_KEEP_W="${INPUT_KEEP_W:-8}"

# Validate required fields
if [ -z "$INPUT_HOST" ] || [ -z "$INPUT_PASS" ]; then
    echo "ERROR: MySQL host and password are required." >&2
    exit 1
fi

# --- Write /etc/ea-backup.env ------------------------------------------------
# Quote the password value to handle any special characters
cat > "$SERVER_ENV" <<EOF
# EasyAppointments backup configuration
# Written by setup-backup-cron.sh — edit directly to update credentials
MYSQL_HOST=${INPUT_HOST}
MYSQL_PORT=${INPUT_PORT}
MYSQL_ADMIN_USER=${INPUT_USER}
MYSQL_ADMIN_PASS=${INPUT_PASS}
BACKUP_DIR=${INPUT_DIR}
KEEP_HOURLY=${INPUT_KEEP_H}
KEEP_WEEKLY=${INPUT_KEEP_W}
LOG_FILE=${LOG_FILE_DEFAULT}
EOF

chmod 600 "$SERVER_ENV"
echo ""
echo "✓ Config written to ${SERVER_ENV} (mode 600, root-only)"

# --- Install the backup script -----------------------------------------------
cp "${SCRIPT_DIR}/backup-databases.sh" "$BACKUP_SCRIPT"
chmod 755 "$BACKUP_SCRIPT"
echo "✓ Backup script installed at ${BACKUP_SCRIPT}"

# --- Create backup directory -------------------------------------------------
mkdir -p "$INPUT_DIR"
echo "✓ Backup directory ready: ${INPUT_DIR}"

# --- Install cron job --------------------------------------------------------
cat > "$CRON_FILE" <<EOF
# EasyAppointments hourly database backup
# Runs at minute 5 of every hour (offset to avoid top-of-hour load spikes)
MAILTO=root
5 * * * * root ${BACKUP_SCRIPT} >> ${LOG_FILE_DEFAULT} 2>&1
EOF

chmod 644 "$CRON_FILE"
echo "✓ Cron job installed at ${CRON_FILE} (runs at :05 every hour)"

# --- Run a test backup to verify connectivity --------------------------------
echo ""
echo "Running a test backup now to verify connectivity..."
echo ""

if EA_BACKUP_ENV_FILE="$SERVER_ENV" "$BACKUP_SCRIPT"; then
    echo ""
    echo "=== Setup Complete ==="
    echo ""
    echo "Backups stored in:   ${INPUT_DIR}/<db-name>/hourly/"
    echo "Weekly snapshots:    ${INPUT_DIR}/<db-name>/weekly/"
    echo "Logs:                ${LOG_FILE_DEFAULT}"
    echo ""
    echo "Useful commands:"
    echo "  tail -50 ${LOG_FILE_DEFAULT}    # check recent backup log"
    echo "  ${BACKUP_SCRIPT}                # run manually"
else
    echo ""
    echo "ERROR: Test backup failed. Check the log: ${LOG_FILE_DEFAULT}"
    echo "The cron job IS installed but will fail until connectivity is resolved."
    exit 1
fi
