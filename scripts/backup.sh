#!/bin/bash

# WPFleet Backup Script 
# Automated backup for all WordPress sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(cat "$PROJECT_ROOT/.env" | grep -v '^#' | xargs)
fi

# Configuration
BACKUP_ROOT="${BACKUP_ROOT:-$PROJECT_ROOT/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Create backup directories
mkdir -p "$BACKUP_ROOT/databases"
mkdir -p "$BACKUP_ROOT/files"
mkdir -p "$BACKUP_ROOT/configs"

# Function to backup a single site
backup_site() {
    local domain=$1
    local db_name="wp_$(echo "$domain" | tr '.' '_' | tr '-' '_')"
    
    print_info "Backing up site: $domain"
    
    # Check if site exists
    if [ ! -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
        print_error "Site $domain not found!"
        return 1
    fi
    
    # Create site backup directory
    local site_backup_dir="$BACKUP_ROOT/$TIMESTAMP/$domain"
    mkdir -p "$site_backup_dir"
    
    # Backup database
    print_info "  - Backing up database..."
    docker exec wpfleet_mariadb mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
        --single-transaction --quick --lock-tables=false \
        "$db_name" | gzip > "$site_backup_dir/database.sql.gz"
    
    # Backup WordPress files
    print_info "  - Backing up files..."
    tar -czf "$site_backup_dir/files.tar.gz" \
        -C "$PROJECT_ROOT/data/wordpress" \
        "$domain" 2>/dev/null || true
    
    # Backup configuration
    print_info "  - Backing up configuration..."
    if [ -f "$PROJECT_ROOT/config/caddy/sites/${domain}.caddy" ]; then
        cp "$PROJECT_ROOT/config/caddy/sites/${domain}.caddy" "$site_backup_dir/"
    fi
    
    # Get WordPress version
    local wp_version=$(docker exec -u www-data -w "/var/www/html/$domain" wpfleet_frankenphp wp core version 2>/dev/null || echo 'unknown')
    
    # Create backup manifest
    cat > "$site_backup_dir/manifest.json" << EOF
{
    "domain": "$domain",
    "timestamp": "$TIMESTAMP",
    "database": "$db_name",
    "wordpress_version": "$wp_version",
    "php_version": "$(docker exec wpfleet_frankenphp php -v | head -1 | cut -d' ' -f2)",
    "backup_size": "$(du -sh $site_backup_dir | cut -f1)"
}
EOF
}

# Function to cleanup old backups
cleanup_old_backups() {
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
}

# Function to get all sites
get_all_sites() {
    find "$PROJECT_ROOT/config/caddy/sites" -name "*.caddy" 2>/dev/null | while read f; do
        basename "$f" .caddy
    done | sort
}

# Main backup logic
case "$1" in
    all)
        print_info "Starting backup of all sites..."
        
        # Get all active sites
        SITES=$(get_all_sites)
        
        if [ -z "$SITES" ]; then
            print_error "No active sites found!"
            exit 1
        fi
        
        # Backup each site
        for site in $SITES; do
            backup_site "$site" || print_error "Failed to backup $site"
        done
        
        # Create summary
        cat > "$BACKUP_ROOT/$TIMESTAMP/summary.txt" << EOF
WPFleet Backup Summary
=====================
Date: $(date)
Sites backed up: $(echo "$SITES" | wc -l)
Total size: $(du -sh "$BACKUP_ROOT/$TIMESTAMP" | cut -f1)

Sites:
$(echo "$SITES" | sed 's/^/  - /')
EOF
        
        print_success "All sites backed up to: $BACKUP_ROOT/$TIMESTAMP"
        
        # Cleanup old backups
        cleanup_old_backups
        ;;
        
    site)
        if [ -z "$2" ]; then
            print_error "Usage: $0 site <domain>"
            exit 1
        fi
        
        backup_site "$2"
        print_success "Site backed up to: $BACKUP_ROOT/$TIMESTAMP/$2"
        ;;
        
    cleanup)
        cleanup_old_backups
        print_success "Old backups cleaned up!"
        ;;
        
    list)
        print_info "Available backups:"
        find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -exec basename {} \; | sort -r | head -20
        
        if [ -n "$2" ]; then
            print_info "\nBackups for site $2:"
            find "$BACKUP_ROOT" -name "$2" -type d | sort -r | head -20
        fi
        ;;
        
    restore)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 restore <domain> <backup_timestamp>"
            echo "  Example: $0 restore example.com 20240115_030000"
            echo ""
            echo "Available backups:"
            find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -exec basename {} \; | sort -r | head -10
            exit 1
        fi
        
        DOMAIN=$2
        BACKUP_TS=$3
        BACKUP_DIR="$BACKUP_ROOT/$BACKUP_TS/$DOMAIN"
        
        if [ ! -d "$BACKUP_DIR" ]; then
            print_error "Backup not found: $BACKUP_DIR"
            exit 1
        fi
        
        print_info "Restoring $DOMAIN from backup $BACKUP_TS..."
        
        # Confirm restore
        read -p "This will overwrite existing data. Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Restore cancelled"
            exit 0
        fi
        
        # Restore database
        print_info "Restoring database..."
        zcat "$BACKUP_DIR/database.sql.gz" | "$SCRIPT_DIR/db-manager.sh" import "$DOMAIN" -
        
        # Restore files
        print_info "Restoring files..."
        rm -rf "$PROJECT_ROOT/data/wordpress/$DOMAIN"
        tar -xzf "$BACKUP_DIR/files.tar.gz" -C "$PROJECT_ROOT/data/wordpress"
        
        # Restore configuration
        if [ -f "$BACKUP_DIR/${DOMAIN}.caddy" ]; then
            print_info "Restoring configuration..."
            cp "$BACKUP_DIR/${DOMAIN}.caddy" "$PROJECT_ROOT/config/caddy/sites/"
            "$SCRIPT_DIR/site-manager.sh" reload
        fi
        
        print_success "Site restored successfully!"
        ;;
        
    *)
        echo "WPFleet Backup Manager"
        echo ""
        echo "Usage: $0 {all|site|cleanup|list|restore} [options]"
        echo ""
        echo "Commands:"
        echo "  all                     - Backup all active sites"
        echo "  site <domain>           - Backup a specific site"
        echo "  cleanup                 - Remove old backups"
        echo "  list [domain]           - List available backups"
        echo "  restore <domain> <timestamp> - Restore a site from backup"
        echo ""
        echo "Examples:"
        echo "  $0 all"
        echo "  $0 site example.com"
        echo "  $0 list"
        echo "  $0 list example.com"
        echo "  $0 restore example.com 20240115_030000"
        echo ""
        echo "Configuration:"
        echo "  Backup location: ${BACKUP_ROOT}"
        echo "  Retention: ${RETENTION_DAYS} days"
        exit 1
        ;;
esac