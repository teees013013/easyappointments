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
# Password uses base64 with /+= stripped — intentionally restricted to [a-zA-Z0-9]
# to prevent SQL injection via heredoc interpolation below
DB_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
ENCRYPTION_KEY=$(openssl rand -base64 32)

if [ -z "$SANITIZED" ]; then
    echo "ERROR: Product name contains no valid characters after sanitization" >&2
    exit 1
fi

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
