#!/bin/bash

# WPFleet Backup Script
# Automated backup for all WordPress sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
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

# Check if Docker is running
check_docker() {
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible!"
        print_info "Please start Docker and ensure you have proper permissions"
        exit 1
    fi
}

# Secure backup function
secure_backup() {
    local backup_dir=$1
    
    if [ ! -d "$backup_dir" ]; then
        print_error "Backup directory does not exist: $backup_dir"
        return 1
    fi
    
    # Secure the backup directory and files
    chmod 700 "$backup_dir" 2>/dev/null || true
    
    # Secure all backup files
    find "$backup_dir" -name "*.sql.gz" -exec chmod 600 {} \; 2>/dev/null || true
    find "$backup_dir" -name "*.tar.gz" -exec chmod 600 {} \; 2>/dev/null || true
    find "$backup_dir" -name "*.json" -exec chmod 600 {} \; 2>/dev/null || true
    find "$backup_dir" -name "*.txt" -exec chmod 600 {} \; 2>/dev/null || true
    
    # Set ownership to current user if running as root
    if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$backup_dir" 2>/dev/null || true
    fi
    
    print_info "  - Secured backup permissions"
}

# Verify backup integrity
verify_backup() {
    local backup_file=$1
    local file_type=$2
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    case "$file_type" in
        "gzip"|"sql")
            if gzip -t "$backup_file" 2>/dev/null; then
                print_info "  - Backup verified: $(basename "$backup_file")"
                return 0
            else
                print_error "  - Backup corrupted: $(basename "$backup_file")"
                return 1
            fi
            ;;
        "tar")
            if tar -tzf "$backup_file" >/dev/null 2>&1; then
                print_info "  - Backup verified: $(basename "$backup_file")"
                return 0
            else
                print_error "  - Backup corrupted: $(basename "$backup_file")"
                return 1
            fi
            ;;
        *)
            # Just check if file exists and has size > 0
            if [ -s "$backup_file" ]; then
                print_info "  - Backup created: $(basename "$backup_file")"
                return 0
            else
                print_error "  - Backup is empty: $(basename "$backup_file")"
                return 1
            fi
            ;;
    esac
}

# Create backup directories
mkdir -p "$BACKUP_ROOT/databases"
mkdir -p "$BACKUP_ROOT/files"
mkdir -p "$BACKUP_ROOT/configs"

# Function to backup a single site
backup_site() {
    local domain=$1
    local container_name="wpfleet_$domain"
    local db_name="wp_$(echo "$domain" | tr '.' '_' | tr '-' '_')"
    
    print_info "Backing up site: $domain"
    
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
        print_error "Container $container_name not found!"
        return 1
    fi
    
    # Create site backup directory with secure permissions
    local site_backup_dir="$BACKUP_ROOT/$TIMESTAMP/$domain"
    mkdir -p "$site_backup_dir"
    chmod 700 "$site_backup_dir"

    # Backup database
    print_info "  - Backing up database..."
    if docker exec wpfleet_mariadb mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
        --single-transaction --quick --lock-tables=false \
        "$db_name" 2>/dev/null | gzip > "$site_backup_dir/database.sql.gz"; then
        verify_backup "$site_backup_dir/database.sql.gz" "gzip"
    else
        print_error "  - Database backup failed for $domain"
        return 1
    fi
    
    # Backup WordPress files
    print_info "  - Backing up files..."
    if [ -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
        if tar -czf "$site_backup_dir/files.tar.gz" \
            -C "$PROJECT_ROOT/data/wordpress" \
            "$domain" 2>/dev/null; then
            verify_backup "$site_backup_dir/files.tar.gz" "tar"
        else
            print_error "  - Files backup failed for $domain"
            return 1
        fi
    else
        print_info "  - No files directory found, skipping files backup"
    fi
    
    # Backup configuration
    print_info "  - Backing up configuration..."
    if [ -d "$PROJECT_ROOT/config/sites/$domain" ]; then
        if tar -czf "$site_backup_dir/config.tar.gz" \
            -C "$PROJECT_ROOT/config/sites" \
            "$domain" 2>/dev/null; then
            verify_backup "$site_backup_dir/config.tar.gz" "tar"
        else
            print_error "  - Config backup failed for $domain"
        fi
    else
        print_info "  - No config directory found, skipping config backup"
    fi
    
    # Get WordPress version and other metadata
    local wp_version="unknown"
    local php_version="unknown"
    if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
        wp_version=$(docker exec -u www-data $container_name wp core version 2>/dev/null || echo 'unknown')
        php_version=$(docker exec $container_name php -v 2>/dev/null | head -1 | cut -d' ' -f2 || echo 'unknown')
    fi
    
    # Create backup manifest
    cat > "$site_backup_dir/manifest.json" << EOF
{
    "domain": "$domain",
    "timestamp": "$TIMESTAMP",
    "backup_date": "$(date -Iseconds)",
    "container": "$container_name",
    "database": "$db_name",
    "wordpress_version": "$wp_version",
    "php_version": "$php_version",
    "backup_size": "$(du -sh $site_backup_dir 2>/dev/null | cut -f1 || echo 'unknown')",
    "files": {
        "database": "$([ -f "$site_backup_dir/database.sql.gz" ] && echo 'yes' || echo 'no')",
        "files": "$([ -f "$site_backup_dir/files.tar.gz" ] && echo 'yes' || echo 'no')",
        "config": "$([ -f "$site_backup_dir/config.tar.gz" ] && echo 'yes' || echo 'no')"
    }
}
EOF
    
    verify_backup "$site_backup_dir/manifest.json" "json"
    
    # Secure the backup
    secure_backup "$site_backup_dir"
    
    print_success "  - Site $domain backed up successfully"
    return 0
}

# Function to cleanup old backups
cleanup_old_backups() {
    print_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local deleted_count=0
    local total_size=0
    
    # Find and remove old backup directories
    while IFS= read -r -d '' backup_dir; do
        if [ -d "$backup_dir" ]; then
            local size=$(du -sb "$backup_dir" 2>/dev/null | cut -f1 || echo 0)
            total_size=$((total_size + size))
            rm -rf "$backup_dir"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -print0 2>/dev/null || true)
    
    if [ $deleted_count -gt 0 ]; then
        local size_mb=$((total_size / 1024 / 1024))
        print_success "Removed $deleted_count old backup(s), freed ${size_mb}MB"
    else
        print_info "No old backups found to clean up"
    fi
}

# Function to get backup statistics
backup_stats() {
    print_info "Backup Statistics:"
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "  No backup directory found"
        return
    fi
    
    local backup_count=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1 || echo "unknown")
    local latest_backup=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort | tail -1)
    
    echo "  Total backups: $backup_count"
    echo "  Total size: $total_size"
    
    if [ -n "$latest_backup" ]; then
        local latest_date=$(basename "$latest_backup")
        local latest_sites=$(find "$latest_backup" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
        echo "  Latest backup: $latest_date ($latest_sites sites)"
    else
        echo "  Latest backup: none"
    fi
    
    echo "  Retention: $RETENTION_DAYS days"
    echo "  Location: $BACKUP_ROOT"
}

# Main backup logic
check_docker

case "$1" in
    all)
        print_info "Starting backup of all sites..."
        
        # Get all active sites
        SITES=$(docker ps --filter "label=wpfleet.site" --format "{{.Labels}}" 2>/dev/null | sed 's/.*wpfleet.site=//' | sort)
        
        if [ -z "$SITES" ]; then
            print_error "No active sites found!"
            exit 1
        fi
        
        local success_count=0
        local total_count=0
        
        # Backup each site
        for site in $SITES; do
            total_count=$((total_count + 1))
            if backup_site "$site"; then
                success_count=$((success_count + 1))
            fi
        done
        
        # Create global backup summary
        cat > "$BACKUP_ROOT/$TIMESTAMP/summary.txt" << EOF
WPFleet Backup Summary
=====================
Date: $(date)
Sites processed: $total_count
Sites successful: $success_count
Sites failed: $((total_count - success_count))
Total size: $(du -sh "$BACKUP_ROOT/$TIMESTAMP" 2>/dev/null | cut -f1 || echo 'unknown')

Sites backed up:
$(echo "$SITES" | sed 's/^/  - /')

Backup location: $BACKUP_ROOT/$TIMESTAMP
EOF

        # Secure the summary
        chmod 600 "$BACKUP_ROOT/$TIMESTAMP/summary.txt" 2>/dev/null || true

        # Get total backup size for notification
        local backup_size=$(du -sh "$BACKUP_ROOT/$TIMESTAMP" 2>/dev/null | cut -f1 || echo 'unknown')

        if [ $success_count -eq $total_count ]; then
            print_success "All $total_count sites backed up successfully to: $BACKUP_ROOT/$TIMESTAMP"

            # Send success notification
            if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
                "$SCRIPT_DIR/notify.sh" backup success "$success_count" "$backup_size" 0 2>/dev/null || true
            fi
        else
            print_error "$((total_count - success_count)) out of $total_count backups failed!"

            # Send failure notification
            if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
                "$SCRIPT_DIR/notify.sh" backup error "$success_count" "$backup_size" "$((total_count - success_count))" 2>/dev/null || true
            fi
        fi
        
        # Cleanup old backups
        cleanup_old_backups
        ;;
        
    site)
        if [ -z "$2" ]; then
            print_error "Usage: $0 site <domain>"
            exit 1
        fi
        
        if backup_site "$2"; then
            print_success "Site backed up to: $BACKUP_ROOT/$TIMESTAMP/$2"
        else
            print_error "Backup failed for site: $2"
            exit 1
        fi
        ;;
        
    cleanup)
        cleanup_old_backups
        print_success "Cleanup completed!"
        ;;
        
    stats)
        backup_stats
        ;;
        
    list)
        print_info "Available backups:"
        if [ -d "$BACKUP_ROOT" ]; then
            find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -exec basename {} \; 2>/dev/null | sort -r | head -20
        else
            echo "  No backups found"
        fi
        
        if [ -n "$2" ]; then
            print_info "\nBackups for site $2:"
            if [ -d "$BACKUP_ROOT" ]; then
                find "$BACKUP_ROOT" -name "$2" -type d 2>/dev/null | sort -r | head -20
            else
                echo "  No backups found for $2"
            fi
        fi
        ;;
        
    restore)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 restore <domain> <backup_timestamp>"
            echo "  Example: $0 restore example.com 20240115_030000"
            echo ""
            echo "Available backups:"
            find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -exec basename {} \; 2>/dev/null | sort -r | head -10
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
        
        # Show backup information
        if [ -f "$BACKUP_DIR/manifest.json" ]; then
            print_info "Backup information:"
            cat "$BACKUP_DIR/manifest.json" | grep -E '"(backup_date|wordpress_version|backup_size)"' | sed 's/^/  /'
        fi
        
        # Confirm restore
        echo ""
        read -p "This will overwrite existing data. Continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Restore cancelled"
            exit 0
        fi
        
        # Check if files exist
        local db_file="$BACKUP_DIR/database.sql.gz"
        local files_archive="$BACKUP_DIR/files.tar.gz"
        local config_archive="$BACKUP_DIR/config.tar.gz"
        
        # Restore database
        if [ -f "$db_file" ]; then
            print_info "Restoring database..."
            if zcat "$db_file" | "$SCRIPT_DIR/db-manager.sh" import "$DOMAIN" - 2>/dev/null; then
                print_success "Database restored"
            else
                print_error "Database restore failed"
                exit 1
            fi
        else
            print_error "Database backup file not found: $db_file"
            exit 1
        fi
        
        # Restore files
        if [ -f "$files_archive" ]; then
            print_info "Restoring files..."
            rm -rf "$PROJECT_ROOT/data/wordpress/$DOMAIN"
            if tar -xzf "$files_archive" -C "$PROJECT_ROOT/data/wordpress"; then
                print_success "Files restored"
            else
                print_error "Files restore failed"
                exit 1
            fi
        else
            print_error "Files backup not found: $files_archive"
        fi
        
        # Restore configuration
        if [ -f "$config_archive" ]; then
            print_info "Restoring configuration..."
            if tar -xzf "$config_archive" -C "$PROJECT_ROOT/config/sites"; then
                print_success "Configuration restored"
            else
                print_error "Configuration restore failed"
            fi
        else
            print_info "No configuration backup found, skipping"
        fi
        
        # Restart container
        if command -v "$SCRIPT_DIR/site-manager.sh" >/dev/null 2>&1; then
            print_info "Restarting site container..."
            "$SCRIPT_DIR/site-manager.sh" restart "$DOMAIN" || print_error "Failed to restart container"
        fi
        
        print_success "Site restored successfully!"
        ;;
        
    *)
        echo "WPFleet Backup Manager"
        echo ""
        echo "Usage: $0 {all|site|cleanup|stats|list|restore} [options]"
        echo ""
        echo "Commands:"
        echo "  all                           - Backup all active sites"
        echo "  site <domain>                 - Backup a specific site"
        echo "  cleanup                       - Remove old backups (older than $RETENTION_DAYS days)"
        echo "  stats                         - Show backup statistics"
        echo "  list [domain]                 - List available backups"
        echo "  restore <domain> <timestamp>  - Restore a site from backup"
        echo ""
        echo "Examples:"
        echo "  $0 all"
        echo "  $0 site example.com"
        echo "  $0 list"
        echo "  $0 list example.com"
        echo "  $0 restore example.com 20240115_030000"
        echo "  $0 cleanup"
        echo "  $0 stats"
        echo ""
        echo "Configuration:"
        echo "  Backup location: ${BACKUP_ROOT}"
        echo "  Retention: ${RETENTION_DAYS} days"
        echo ""
        backup_stats
        exit 1
        ;;
esac