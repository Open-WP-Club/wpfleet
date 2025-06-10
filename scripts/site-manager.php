#!/bin/bash

# WPFleet Site Manager
# Manage WordPress sites in the WPFleet environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

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

sanitize_domain_for_container() {
    echo "$1" | tr '.' '_' | tr '-' '_'
}

add_site() {
    local domain=$1
    local php_version=${2:-8.3}
    
    # Validate domain
    if ! validate_domain "$domain"; then
        exit 1
    fi
    
    local container_name="site_$(sanitize_domain_for_container $domain)"
    local db_name="wp_$(sanitize_domain_for_container $domain)"
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    local config_dir="$PROJECT_ROOT/config/sites/$domain"
    
    print_info "Adding site: $domain"
    
    # Check if site already exists
    if docker-compose ps | grep -q "$container_name"; then
        print_error "Site $domain already exists!"
        exit 1
    fi
    
    # Create directories
    mkdir -p "$site_dir"
    mkdir -p "$config_dir"
    mkdir -p "$PROJECT_ROOT/data/logs/$domain"
    
    # Create site-specific Caddyfile
    cp "$PROJECT_ROOT/docker/frankenphp/Caddyfile.template" "$config_dir/Caddyfile"
    
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
    
    # Add service to docker-compose.yml
    print_info "Adding service to docker-compose.yml"
    
    # Create a temporary file with the new service
    cat >> "$COMPOSE_FILE" << EOF

  $container_name:
    build:
      context: ./docker/frankenphp
      args:
        PHP_VERSION: $php_version
    container_name: wpfleet_$domain
    restart: unless-stopped
    environment:
      SERVER_NAME: $domain
      DB_NAME: $db_name
      DB_USER: \${MYSQL_USER}
      DB_PASSWORD: \${MYSQL_PASSWORD}
      DB_HOST: mariadb
      REDIS_HOST: redis
      ACME_EMAIL: \${ACME_EMAIL:-admin@$domain}
      AUTO_CONFIGURE_WP: true
    volumes:
      - ./data/wordpress/$domain:/var/www/html
      - ./config/sites/$domain/Caddyfile:/etc/caddy/Caddyfile.template:ro
      - ./data/logs/$domain:/var/log
    networks:
      wpfleet:
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_healthy
    labels:
      - "wpfleet.site=$domain"
      - "traefik.enable=false"
    ports:
      - "80"
      - "443"
    mem_limit: \${SITE_MEM_LIMIT:-512m}
    cpus: \${SITE_CPU_LIMIT:-0.5}
EOF
    
    # Start the new site
    print_info "Starting site container..."
    docker-compose up -d --build "$container_name"
    
    # Wait for container to be ready
    print_info "Waiting for container to be ready..."
    sleep 10
    
    # Install WordPress if needed
    if [ ! -f "$site_dir/wp-config.php" ]; then
        print_info "Installing WordPress..."
        docker exec -u www-data wpfleet_$domain wp core install \
            --url="https://$domain" \
            --title="$domain" \
            --admin_user="${WP_ADMIN_USER:-admin}" \
            --admin_password="${WP_ADMIN_PASSWORD:-$(openssl rand -base64 12)}" \
            --admin_email="${WP_ADMIN_EMAIL:-admin@$domain}" \
            --skip-email
        
        # Install and activate Redis object cache plugin
        docker exec -u www-data wpfleet_$domain wp plugin install redis-cache --activate
        docker exec -u www-data wpfleet_$domain wp redis enable
    fi
    
    print_success "Site $domain has been added successfully!"
    print_info "Container: wpfleet_$domain"
    print_info "Database: $db_name"
    print_info "Files: $site_dir"
    
    # Get the container port mapping
    local port_80=$(docker port wpfleet_$domain 80 | cut -d: -f2)
    local port_443=$(docker port wpfleet_$domain 443 | cut -d: -f2)
    
    print_info "Ports: HTTP=$port_80, HTTPS=$port_443"
    print_info "Access your site at: https://$domain"
}

remove_site() {
    local domain=$1
    
    # Validate domain
    if ! validate_domain "$domain"; then
        exit 1
    fi
    
    local container_name="site_$(sanitize_domain_for_container $domain)"
    local db_name="wp_$(sanitize_domain_for_container $domain)"
    
    print_info "Removing site: $domain"
    
    # Confirm removal
    read -p "Are you sure you want to remove $domain? This will delete all data! (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removal cancelled"
        exit 0
    fi
    
    # Stop and remove container
    print_info "Stopping container..."
    docker-compose stop "$container_name" 2>/dev/null || true
    docker-compose rm -f "$container_name" 2>/dev/null || true
    
    # Remove from docker-compose.yml
    print_info "Removing from docker-compose.yml..."
    # This is a bit tricky - we need to remove the service definition
    # For now, we'll mark it as removed and suggest manual cleanup
    sed -i.bak "/^  $container_name:/,/^  [^ ]/{s/^/#REMOVED#/}" "$COMPOSE_FILE"
    
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
    rm -rf "$PROJECT_ROOT/data/wordpress/$domain"
    rm -rf "$PROJECT_ROOT/config/sites/$domain"
    rm -rf "$PROJECT_ROOT/data/logs/$domain"
    
    print_success "Site $domain has been removed!"
    print_info "Backup saved as: $backup_name"
    print_info "Note: Clean up docker-compose.yml manually to remove lines marked with #REMOVED#"
}

list_sites() {
    print_info "Active WordPress sites:"
    docker ps --filter "label=wpfleet.site" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed 's/wpfleet_//'
}

restart_site() {
    local domain=$1
    local container_name="wpfleet_$domain"
    
    print_info "Restarting site: $domain"
    docker-compose restart "site_$(sanitize_domain_for_container $domain)"
    print_success "Site restarted!"
}

# Main script logic
case "$1" in
    add)
        if [ -z "$2" ]; then
            print_error "Usage: $0 add <domain> [php_version]"
            exit 1
        fi
        add_site "$2" "$3"
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
    *)
        echo "WPFleet Site Manager"
        echo ""
        echo "Usage: $0 {add|remove|list|restart} [domain] [options]"
        echo ""
        echo "Commands:"
        echo "  add <domain> [php_version]  - Add a new WordPress site"
        echo "  remove <domain>             - Remove a WordPress site"
        echo "  list                        - List all sites"
        echo "  restart <domain>            - Restart a site"
        echo ""
        echo "Examples:"
        echo "  $0 add example.com"
        echo "  $0 add example.com 8.2"
        echo "  $0 remove example.com"
        echo "  $0 list"
        exit 1
        ;;
esac