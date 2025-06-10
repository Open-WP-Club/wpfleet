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

# Function to configure WordPress
configure_wordpress() {
    if [ ! -f wp-config.php ]; then
        echo "WordPress not found. Installing..."
        
        # Download WordPress
        wp core download --allow-root || true
        
        # Create wp-config.php
        wp config create \
            --dbname="${DB_NAME}" \
            --dbuser="${DB_USER}" \
            --dbpass="${DB_PASSWORD}" \
            --dbhost="${DB_HOST}" \
            --dbcharset="utf8mb4" \
            --dbcollate="utf8mb4_unicode_ci" \
            --extra-php <<PHP
// Redis Object Cache
define( 'WP_REDIS_HOST', '${REDIS_HOST}' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${DB_NAME}' );
define( 'WP_REDIS_DATABASE', 0 );
define( 'WP_REDIS_TIMEOUT', 1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );

// Security
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_AUTO_UPDATE_CORE', false );

// Performance
define( 'WP_CACHE', true );
define( 'COMPRESS_CSS', true );
define( 'COMPRESS_SCRIPTS', true );
define( 'CONCATENATE_SCRIPTS', false );
define( 'ENFORCE_GZIP', true );

// URLs
define( 'WP_HOME', 'https://${SERVER_NAME}' );
define( 'WP_SITEURL', 'https://${SERVER_NAME}' );

// Force SSL
define( 'FORCE_SSL_ADMIN', true );
\$_SERVER['HTTPS'] = 'on';

// Increase memory limit
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Debug (disable in production)
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
define( 'WP_DEBUG_DISPLAY', false );
define( 'SCRIPT_DEBUG', false );

// Disable cron (use system cron instead)
define( 'DISABLE_WP_CRON', true );
PHP
            --allow-root
        
        echo "WordPress configuration created!"
    fi
}

# Generate Caddyfile from template
if [ -f /etc/caddy/Caddyfile.template ]; then
    envsubst < /etc/caddy/Caddyfile.template > /etc/caddy/Caddyfile
fi

# Wait for database
wait_for_db

# Configure WordPress if needed
if [ "${AUTO_CONFIGURE_WP}" = "true" ]; then
    configure_wordpress
fi

# Create necessary directories
mkdir -p /var/log/caddy /var/log/php
touch /var/log/php/error.log
chmod 666 /var/log/php/error.log

# Fix permissions
chown -R www-data:www-data /var/www/html /var/log/caddy /var/log/php 2>/dev/null || true

# Execute the main command
exec "$@"