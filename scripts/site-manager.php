#!/bin/bash

# WPFleet Site Manager
# Manage WordPress sites in the WPFleet environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CADDY_SITES_DIR="$PROJECT_ROOT/config/caddy/sites"
SITE_TEMPLATE="$PROJECT_ROOT/config/caddy/site-template.caddy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
fi

# Functions
print_error() {
echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
echo -e "${YELLOW}INFO: $1${NC}"
}

validate_domain() {
local domain=$1
if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
print_error "Invalid domain format: $domain"
return 1
fi
return 0
}

sanitize_domain_for_db() {
echo "$1" | tr '.' '_' | tr '-' '_'
}

reload_caddy() {
print_info "Reloading Caddy configuration..."
docker exec wpfleet_frankenphp caddy reload --config /etc/caddy/Caddyfile || {
print_error "Failed to reload Caddy configuration"
return 1
}
}

add_site() {
local domain=$1
local memory_limit=${2:-256M}

# Validate domain
if ! validate_domain "$domain"; then
exit 1
fi

local db_name="wp_$(sanitize_domain_for_db $domain)"
local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
local log_dir="$PROJECT_ROOT/data/logs/$domain"
local caddy_config="$CADDY_SITES_DIR/${domain}.caddy"

print_info "Adding site: $domain"

# Check if site already exists
if [ -f "$caddy_config" ]; then
print_error "Site $domain already exists!"
exit 1
fi

# Create directories
mkdir -p "$site_dir"
mkdir -p "$log_dir"
mkdir -p "$CADDY_SITES_DIR"

# Create database
print_info "Creating database: $db_name"
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "
CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
" || {
print_error "Failed to create database"
exit 1
}

# Create .user.ini for site-specific PHP settings
cat > "$site_dir/.user.ini" << EOF
    ; Site-specific PHP configuration for $domain
    open_basedir=/var/www/html/$domain:/tmp:/usr/share/php
    memory_limit=$memory_limit
    max_execution_time=300
    upload_max_filesize=64M
    post_max_size=64M
    error_log=/var/log/$domain/php-error.log
    EOF

    # Create Caddy configuration from template
    if [ ! -f "$SITE_TEMPLATE" ]; then
    print_error "Site template not found at $SITE_TEMPLATE"
    exit 1
    fi

    cp "$SITE_TEMPLATE" "$caddy_config"
    sed -i "s/DOMAIN_PLACEHOLDER/$domain/g" "$caddy_config"
    sed -i "s/DB_NAME_PLACEHOLDER/$db_name/g" "$caddy_config"
    sed -i "s/MEMORY_LIMIT_PLACEHOLDER/$memory_limit/g" "$caddy_config"

    # Reload Caddy
    reload_caddy

    # Wait a moment for Caddy to process
    sleep 2

    # Configure WordPress
    print_info "Configuring WordPress for $domain..."

    # Create wp-config.php
    docker exec -u www-data -w "/var/www/html/$domain" wpfleet_frankenphp bash -c "
        # Download WordPress if not present
        if [ ! -f wp-load.php ]; then
            wp core download --path=/var/www/html/$domain
        fi
        
        # Create wp-config.php
        wp config create \
            --dbname='$db_name' \
            --dbuser='${DB_USER}' \
            --dbpass='${DB_PASSWORD}' \
            --dbhost='${DB_HOST}' \
            --dbcharset='utf8mb4' \
            --dbcollate='utf8mb4_unicode_ci' \
            --extra-php <<PHP
// Redis Object Cache
define( 'WP_REDIS_HOST', '${REDIS_HOST}' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PREFIX', '${db_name}' );
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
define( 'WP_HOME', 'https://$domain' );
define( 'WP_SITEURL', 'https://$domain' );

// Force SSL
define( 'FORCE_SSL_ADMIN', true );
if (isset(\\\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \\\$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \\\$_SERVER['HTTPS'] = 'on';
}

// Memory limits
define( 'WP_MEMORY_LIMIT', '$memory_limit' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Debug (disable in production)
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
define( 'WP_DEBUG_DISPLAY', false );
define( 'SCRIPT_DEBUG', false );

// Disable cron (use system cron instead)
define( 'DISABLE_WP_CRON', true );
PHP
    "

    # Install WordPress
    print_info "Installing WordPress..."
    docker exec -u www-data -w "/var/www/html/$domain" wpfleet_frankenphp wp core install \
    --url="https://$domain" \
    --title="$domain" \
    --admin_user="${WP_ADMIN_USER:-admin}" \
    --admin_password="${WP_ADMIN_PASSWORD:-$(openssl rand -base64 12)}" \
    --admin_email="${WP_ADMIN_EMAIL:-admin@$domain}" \
    --skip-email

    # Install and activate Redis object cache plugin
    docker exec -u www-data -w "/var/www/html/$domain" wpfleet_frankenphp wp plugin install redis-cache --activate
    docker exec -u www-data -w "/var/www/html/$domain" wpfleet_frankenphp wp redis enable

    print_success "Site $domain has been added successfully!"
    print_info "Database: $db_name"
    print_info "Files: $site_dir"
    print_info "Memory limit: $memory_limit"
    print_info "Access your site at: https://$domain"
    }

    remove_site() {
    local domain=$1

    # Validate domain
    if ! validate_domain "$domain" ; then
    exit 1
    fi

    local db_name="wp_$(sanitize_domain_for_db $domain)"
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    local caddy_config="$CADDY_SITES_DIR/${domain}.caddy"

    print_info "Removing site: $domain"

    # Check if site exists
    if [ ! -f "$caddy_config" ]; then
    print_error "Site $domain not found!"
    exit 1
    fi

    # Confirm removal
    read -p "Are you sure you want to remove $domain? This will delete all data! (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY=~ ^[Yy]$ ]]; then
    print_info "Removal cancelled"
    exit 0
    fi

    # Remove Caddy configuration
    rm -f "$caddy_config"

    # Reload Caddy
    reload_caddy

    # Drop database
    print_info "Dropping database..."
    docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "
        DROP DATABASE IF EXISTS \`$db_name\`;
    " || print_error "Failed to drop database"

    # Backup and remove files
    local backup_name="backup_${domain}_$(date +%Y%m%d_%H%M%S).tar.gz"
    print_info "Creating backup: $backup_name"
    tar -czf "$PROJECT_ROOT/$backup_name" -C "$PROJECT_ROOT/data/wordpress" "$domain" 2>/dev/null || true

    # Remove directories
    rm -rf "$site_dir"
    rm -rf "$PROJECT_ROOT/data/logs/$domain"

    print_success "Site $domain has been removed!"
    print_info "Backup saved as: $backup_name"
    }

    list_sites() {
    print_info "Active WordPress sites:"
    echo ""
    printf "%-30s %-20s %-15s\n" "DOMAIN" "DATABASE" "SIZE"
    printf "%-30s %-20s %-15s\n" "------" "--------" "----"

    for caddy_file in "$CADDY_SITES_DIR"/*.caddy; do
    if [ -f "$caddy_file" ]; then
    local domain=$(basename "$caddy_file" .caddy)
    local db_name="wp_$(sanitize_domain_for_db $domain)"
    local site_size=$(du -sh "$PROJECT_ROOT/data/wordpress/$domain" 2>/dev/null | cut -f1 || echo "N/A")
    printf "%-30s %-20s %-15s\n" "$domain" "$db_name" "$site_size"
    fi
    done
    }

    restart_site() {
    local domain=$1

    print_info "Restarting site: $domain"

    # For single container, we just reload Caddy
    reload_caddy

    print_success "Site configuration reloaded!"
    }

    # Main script logic
    case "$1" in
    add)
    if [ -z "$2" ]; then
    print_error "Usage: $0 add <domain> [memory_limit]"
        echo " memory_limit: PHP memory limit (default: 256M)"
        exit 1
        fi
        add_site "$2" "${3:-256M}"
        ;;
        remove)
        if [ -z "$2" ]; then
        print_error "Usage: $0 remove <domain>"
            exit 1
            fi
            remove_site "$2"
            ;;
            list)
            list_sites
            ;;
            restart)
            if [ -z "$2" ]; then
            print_error "Usage: $0 restart <domain>"
                exit 1
                fi
                restart_site "$2"
                ;;
                reload)
                reload_caddy
                print_success "Caddy configuration reloaded!"
                ;;
                *)
                echo "WPFleet Site Manager"
                echo ""
                echo "Usage: $0 {add|remove|list|restart|reload} [domain] [options]"
                echo ""
                echo "Commands:"
                echo " add <domain> [memory] - Add a new WordPress site"
                    echo " remove <domain> - Remove a WordPress site"
                        echo " list - List all sites"
                        echo " restart <domain> - Restart a site (reload config)"
                            echo " reload - Reload all Caddy configurations"
                            echo ""
                            echo "Examples:"
                            echo " $0 add example.com"
                            echo " $0 add example.com 512M"
                            echo " $0 remove example.com"
                            echo " $0 list"
                            exit 1
                            ;;
                            esac