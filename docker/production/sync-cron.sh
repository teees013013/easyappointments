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
