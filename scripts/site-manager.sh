#!/bin/bash

# WPFleet Site Manager
# Manage WordPress sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Input validation function
validate_domain() {
    if [[ -z "$1" ]]; then
        print_error "Domain cannot be empty"
        return 1
    fi
    if [[ ! "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        print_error "Invalid domain format: $1"
        return 1
    fi
    return 0
}

sanitize_domain_for_db() {
    echo "$1" | tr '.' '_' | tr '-' '_'
}

# Check if Docker is running and containers exist
check_docker() {
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible!"
        exit 1
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "^wpfleet_frankenphp$"; then
        print_error "FrankenPHP container not running! Start it first with: docker-compose up -d"
        exit 1
    fi
}

# Update Caddyfile to include new domain
update_caddyfile() {
    local domain=$1
    local action=$2  # "add" or "remove"
    local db_name=$(sanitize_domain_for_db "$domain")

    local site_config="$PROJECT_ROOT/config/caddy/sites/${domain}.caddy"

    if [ "$action" = "add" ]; then
        # Create site-specific Caddy configuration file
        print_info "Creating Caddy configuration for $domain..."

        mkdir -p "$PROJECT_ROOT/config/caddy/sites"

        cat > "$site_config" << EOF
# Site configuration for $domain
$domain {
    # Enable compression with optimal settings
    encode {
        zstd
        gzip 6
        minimum_length 1024
    }

    # Security headers
    header {
        # Remove sensitive headers
        -Server
        -X-Powered-By
        -X-Generator

        # WordPress security headers
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"

        # CSP for WordPress (allows inline scripts/styles needed by WP admin)
        Content-Security-Policy "default-src 'self' https: data: 'unsafe-inline' 'unsafe-eval'; img-src 'self' https: data:; font-src 'self' https: data:;"

        # Permissions Policy
        Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=(), usb=(), bluetooth=()"
    }

    # Document root for this domain
    root * /var/www/html/$domain

    # Redirect www to non-www
    @www {
        host www.$domain
    }
    redir @www https://$domain{uri} permanent

    # WordPress security rules - block dangerous files
    @disallowed {
        path /xmlrpc.php
        path /wp-config.php
        path /.user.ini
        path /.htaccess
        path /wp-content/debug.log
        path /wp-content/backups/*
        path /wp-content/ai1wm-backups/*
        path */.*
        path */.git/*
        path */node_modules/*
        path */vendor/*
    }

    respond @disallowed 403 {
        body "Access Denied"
        close
    }

    # Handle static assets with aggressive caching
    @static {
        path *.css *.js *.ico *.gif *.jpg *.jpeg *.png *.svg *.woff *.woff2 *.ttf *.eot *.webp *.avif
    }

    header @static {
        Cache-Control "public, max-age=31536000, immutable"
        Vary "Accept-Encoding"
    }

    # Handle media uploads with moderate caching
    @uploads {
        path /wp-content/uploads/*
    }

    header @uploads {
        Cache-Control "public, max-age=86400"
        Vary "Accept-Encoding"
    }

    # Handle WordPress with FrankenPHP
    php {
        root /var/www/html/$domain
    }

    file_server {
        precompressed gzip br
    }

    # Site-specific logging
    log {
        output file /var/log/frankenphp/$domain/access.log {
            roll_size 100MB
            roll_keep 5
            roll_keep_for 168h
        }
        format json
        level INFO
    }
}
EOF

    elif [ "$action" = "remove" ]; then
        # Remove site-specific configuration file
        print_info "Removing Caddy configuration for $domain..."
        rm -f "$site_config"
    fi
}

# Reload FrankenPHP configuration
reload_frankenphp() {
    print_info "Reloading FrankenPHP configuration..."
    docker exec wpfleet_frankenphp caddy reload --config /etc/caddy/Caddyfile || {
        print_error "Failed to reload Caddy configuration"
        return 1
    }
}

# Common infrastructure setup for all site types
setup_site_infrastructure() {
    local domain=$1
    local db_name="wp_$(sanitize_domain_for_db $domain)"
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    
    # Check if site already exists
    if [ -d "$site_dir" ]; then
        print_error "Site directory already exists: $site_dir"
        exit 1
    fi
    
    # Create site directory
    mkdir -p "$site_dir"
    mkdir -p "$PROJECT_ROOT/data/logs/$domain"
    
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
    
    # Update Caddyfile
    update_caddyfile "$domain" "add"
    
    # Reload FrankenPHP
    reload_frankenphp || {
        print_error "Failed to reload FrankenPHP. Site directory created but not active."
        exit 1
    }
    
    echo "$db_name"  # Return db_name for other functions to use
}

# Skip WordPress installation - just show info
skip_wordpress_installation() {
    local domain=$1
    local db_name=$2
    
    print_success "Site infrastructure created for: $domain"
    echo ""
    print_info "Database Information:"
    echo "  Database Name: $db_name"
    echo "  Database User: ${MYSQL_USER}"
    echo "  Database Password: ${MYSQL_PASSWORD}"
    echo "  Database Host: mariadb (or localhost:3306 from host)"
    echo ""
    print_info "Site Information:"
    echo "  Files Directory: $PROJECT_ROOT/data/wordpress/$domain"
    echo "  Container Path: /var/www/html/$domain"
    echo "  Site URL: https://$domain"
    echo "  Logs Directory: $PROJECT_ROOT/data/logs/$domain"
    echo ""
    print_info "Next Steps:"
    echo "  1. Upload your WordPress files to: $PROJECT_ROOT/data/wordpress/$domain"
    echo "  2. Configure wp-config.php with the database information above"
    echo "  3. Your site will be accessible at: https://$domain"
}

# Import existing WordPress site
import_existing_wordpress() {
    local domain=$1
    local db_name=$2
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    
    print_info "Importing existing WordPress site for: $domain"
    echo ""
    
    # Prompt for database file
    read -p "Path to database backup file (*.sql or *.sql.gz): " db_file
    if [ ! -f "$db_file" ]; then
        print_error "Database file not found: $db_file"
        exit 1
    fi
    
    # Prompt for files archive
    read -p "Path to files archive (*.tar.gz or *.zip): " files_archive
    if [ ! -f "$files_archive" ]; then
        print_error "Files archive not found: $files_archive"
        exit 1
    fi
    
    # Import database
    print_info "Importing database..."
    if [[ "$db_file" == *.gz ]]; then
        zcat "$db_file" | docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} "$db_name"
    else
        docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} "$db_name" < "$db_file"
    fi
    
    # Extract files
    print_info "Extracting files..."
    if [[ "$files_archive" == *.tar.gz ]]; then
        tar -xzf "$files_archive" -C "$site_dir" --strip-components=1
    elif [[ "$files_archive" == *.zip ]]; then
        unzip -q "$files_archive" -d "$site_dir"
    else
        print_error "Unsupported archive format. Use *.tar.gz or *.zip"
        exit 1
    fi
    
    # Update wp-config.php if it exists
    local wp_config="$site_dir/wp-config.php"
    if [ -f "$wp_config" ]; then
        print_info "Updating wp-config.php database settings..."
        
        # Create backup of original wp-config.php
        cp "$wp_config" "$wp_config.backup"
        
        # Update database settings
        sed -i "s/define( *'DB_NAME'.*/define('DB_NAME', '$db_name');/" "$wp_config"
        sed -i "s/define( *'DB_USER'.*/define('DB_USER', '${MYSQL_USER}');/" "$wp_config"
        sed -i "s/define( *'DB_PASSWORD'.*/define('DB_PASSWORD', '${MYSQL_PASSWORD}');/" "$wp_config"
        sed -i "s/define( *'DB_HOST'.*/define('DB_HOST', 'mariadb');/" "$wp_config"
        
        # Add Redis configuration if not present
        if ! grep -q "WP_REDIS_HOST" "$wp_config"; then
            cat >> "$wp_config" << EOF

// Redis Object Cache
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PASSWORD', '${REDIS_PASSWORD}' );
define( 'WP_REDIS_PREFIX', '${db_name}' );
define( 'WP_REDIS_DATABASE', 0 );
EOF
        fi
    fi
    
    # Fix permissions
    docker exec wpfleet_frankenphp chown -R www-data:www-data "/var/www/html/$domain"
    
    print_success "Site imported successfully!"
    print_info "Original wp-config.php backed up to: wp-config.php.backup"
    print_info "Site accessible at: https://$domain"
}

# Install clean WordPress (existing functionality)
install_clean_wordpress() {
    local domain=$1
    local db_name=$2
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    
    print_info "Installing clean WordPress..."
    
    # Create wp-config.php
    docker exec wpfleet_frankenphp bash -c "
        cd /var/www/html/$domain && 
        wp core download --allow-root &&
        wp config create \\
            --dbname='$db_name' \\
            --dbuser='${MYSQL_USER}' \\
            --dbpass='${MYSQL_PASSWORD}' \\
            --dbhost='mariadb' \\
            --dbcharset='utf8mb4' \\
            --dbcollate='utf8mb4_unicode_ci' \\
            --extra-php <<'PHP'
// Redis Object Cache
define( 'WP_REDIS_HOST', 'redis' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PASSWORD', '${REDIS_PASSWORD}' );
define( 'WP_REDIS_PREFIX', '$db_name' );
define( 'WP_REDIS_DATABASE', 0 );

// Security
define( 'DISALLOW_FILE_EDIT', true );
define( 'WP_AUTO_UPDATE_CORE', false );

// Performance
define( 'WP_CACHE', true );

// URLs
define( 'WP_HOME', 'https://$domain' );
define( 'WP_SITEURL', 'https://$domain' );

// Force SSL
define( 'FORCE_SSL_ADMIN', true );
\\\$_SERVER['HTTPS'] = 'on';

// Memory
define( 'WP_MEMORY_LIMIT', '256M' );

// Debug (disable in production)
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', false );
define( 'WP_DEBUG_DISPLAY', false );
PHP
            --allow-root
    " || {
        print_error "Failed to create WordPress configuration"
        exit 1
    }
    
    # Install WordPress
    local wp_admin_password="${WP_ADMIN_PASSWORD:-$(openssl rand -base64 12)}"
    docker exec wpfleet_frankenphp bash -c "
        cd /var/www/html/$domain && 
        wp core install \\
            --url='https://$domain' \\
            --title='$domain' \\
            --admin_user='${WP_ADMIN_USER:-admin}' \\
            --admin_password='$wp_admin_password' \\
            --admin_email='${WP_ADMIN_EMAIL:-admin@$domain}' \\
            --skip-email \\
            --allow-root
    " || {
        print_error "Failed to install WordPress"
        exit 1
    }
    
    # Install Redis cache plugin
    docker exec wpfleet_frankenphp bash -c "
        cd /var/www/html/$domain && 
        wp plugin install redis-cache --activate --allow-root &&
        wp redis enable --allow-root
    " || print_info "Redis cache plugin installation failed (non-critical)"
    
    # Fix permissions
    docker exec wpfleet_frankenphp chown -R www-data:www-data "/var/www/html/$domain"
    
    print_success "Clean WordPress installation completed!"
    print_info "Admin password: $wp_admin_password"
    print_info "Access your site at: https://$domain"
}

# Main add site function
add_site() {
    local domain=$1
    local mode=$2  # "clean", "skip", or "import"
    
    # Validate domain
    if ! validate_domain "$domain"; then
        exit 1
    fi
    
    print_info "Adding site: $domain (mode: $mode)"
    
    # Setup common infrastructure
    local db_name=$(setup_site_infrastructure "$domain")
    
    # Handle different modes
    case "$mode" in
        "skip")
            skip_wordpress_installation "$domain" "$db_name"
            ;;
        "import")
            import_existing_wordpress "$domain" "$db_name"
            ;;
        "clean"|*)
            install_clean_wordpress "$domain" "$db_name"
            ;;
    esac
}

remove_site() {
    local domain=$1
    
    # Validate domain
    if ! validate_domain "$domain"; then
        exit 1
    fi
    
    local db_name="wp_$(sanitize_domain_for_db $domain)"
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    
    print_info "Removing site: $domain"
    
    # Check if site exists
    if [ ! -d "$site_dir" ]; then
        print_error "Site does not exist: $domain"
        exit 1
    fi
    
    # Confirm removal
    read -p "Are you sure you want to remove $domain? This will delete all data! (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removal cancelled"
        exit 0
    fi
    
    # Create backup with secure permissions
    local backup_name="backup_${domain}_$(date +%Y%m%d_%H%M%S).tar.gz"
    print_info "Creating backup: $backup_name"
    # Set umask to create file with restricted permissions
    (umask 077 && tar -czf "$PROJECT_ROOT/$backup_name" -C "$PROJECT_ROOT/data/wordpress" "$domain" 2>/dev/null) || true
    
    # Drop database
    print_info "Dropping database..."
    docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "
        DROP DATABASE IF EXISTS \`$db_name\`;
    " || print_error "Failed to drop database"
    
    # Update Caddyfile
    update_caddyfile "$domain" "remove"
    
    # Reload FrankenPHP
    reload_frankenphp
    
    # Remove directories
    rm -rf "$site_dir"
    rm -rf "$PROJECT_ROOT/data/logs/$domain"
    
    print_success "Site $domain has been removed!"
    print_info "Backup saved as: $backup_name"
}

list_sites() {
    print_info "WordPress sites:"
    
    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        local count=0
        for site_dir in "$PROJECT_ROOT/data/wordpress"/*; do
            if [ -d "$site_dir" ]; then
                local domain=$(basename "$site_dir")
                local db_name="wp_$(sanitize_domain_for_db $domain)"
                
                # Check if database exists
                local db_exists=$(docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | wc -l)
                
                if [ "$db_exists" -gt 1 ]; then
                    echo "  ✓ $domain (active)"
                else
                    echo "  ⚠ $domain (no database)"
                fi
                count=$((count + 1))
            fi
        done
        
        if [ $count -eq 0 ]; then
            echo "  No sites found"
        fi
    else
        echo "  No sites directory found"
    fi
}

restart_frankenphp() {
    print_info "Restarting FrankenPHP container..."
    docker-compose restart frankenphp || docker restart wpfleet_frankenphp
    print_success "FrankenPHP restarted!"
}

# Main script logic
check_docker

case "$1" in
    add)
        if [ -z "$2" ]; then
            print_error "Usage: $0 add <domain> [--skip-install|--import-from]"
            exit 1
        fi
        
        domain="$2"
        mode="clean"  # default
        
        if [ "$3" = "--skip-install" ]; then
            mode="skip"
        elif [ "$3" = "--import-from" ]; then
            mode="import"
        fi
        
        add_site "$domain" "$mode"
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
        restart_frankenphp
        ;;
    *)
        echo "WPFleet Site Manager"
        echo ""
        echo "Usage: $0 {add|remove|list|restart} [options]"
        echo ""
        echo "Commands:"
        echo "  add <domain>                    - Add new WordPress site (clean install)"
        echo "  add <domain> --skip-install     - Create infrastructure only (no WordPress)"
        echo "  add <domain> --import-from      - Import existing WordPress site"
        echo "  remove <domain>                 - Remove a WordPress site"
        echo "  list                           - List all sites"
        echo "  restart                        - Restart FrankenPHP container"
        echo ""
        echo "Examples:"
        echo "  $0 add example.com                    # Clean WordPress install"
        echo "  $0 add example.com --skip-install     # Just create DB & folders"
        echo "  $0 add example.com --import-from      # Import existing site"
        echo "  $0 remove example.com"
        echo "  $0 list"
        echo "  $0 restart"
        exit 1
        ;;
esac