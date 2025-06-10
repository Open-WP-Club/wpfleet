#!/bin/bash
set -e

# Function to wait for database
wait_for_db() {
    echo "Waiting for MariaDB to be ready..."
    while ! mysqladmin ping -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" --silent; do
        sleep 1
    done
    echo "MariaDB is ready!"
}

# Wait for database
wait_for_db

# Create necessary directories
mkdir -p /var/log/caddy /var/log/php /etc/caddy/sites
touch /var/log/php/error.log
chmod 666 /var/log/php/error.log

# Ensure Caddyfile exists
if [ ! -f /etc/caddy/Caddyfile ]; then
    echo "ERROR: Caddyfile not found!"
    exit 1
fi

# Fix permissions
chown -R www-data:www-data /var/www/html /var/log 2>/dev/null || true
chown -R caddy:caddy /data /config 2>/dev/null || true

# Execute the main command
exec "$@"