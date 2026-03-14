#!/bin/bash
set -e

echo ">>> Setting storage directory permissions"
chown -R www-data:www-data /var/www/html/storage

echo ">>> Running database migrations"
cd /var/www/html
php index.php console migrate || echo ">>> Migration skipped (database may not be initialized yet)"

echo ">>> Starting supervisord"
exec /usr/bin/supervisord -c /etc/supervisord.conf
