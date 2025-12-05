#!/bin/bash

# WPFleet Quota Manager
# Manage per-site disk quotas and monitor usage

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/utils.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env" || exit 1

# Configuration
QUOTA_CONFIG_DIR="$PROJECT_ROOT/data/quotas"
WORDPRESS_DIR="$PROJECT_ROOT/data/wordpress"
DEFAULT_QUOTA_MB="${DEFAULT_SITE_QUOTA_MB:-5000}"  # 5GB default

# Create quota config directory
mkdir -p "$QUOTA_CONFIG_DIR"

# Convert bytes to human readable (wrapper for compatibility)
bytes_to_human() {
    format_bytes "$@"
}

# Legacy function wrapper
_original_bytes_to_human() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(($bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(($bytes / 1048576))MB"
    else
        echo "$(($bytes / 1073741824))GB"
    fi
}

# Convert MB to bytes
mb_to_bytes() {
    echo $(($1 * 1048576))
}

# Get quota for a site (in MB)
get_quota() {
    local domain=$1
    local quota_file="$QUOTA_CONFIG_DIR/$domain.quota"

    if [ -f "$quota_file" ]; then
        cat "$quota_file"
    else
        echo "$DEFAULT_QUOTA_MB"
    fi
}

# Set quota for a site
set_quota() {
    local domain=$1
    local quota_mb=$2
    local quota_file="$QUOTA_CONFIG_DIR/$domain.quota"

    if [ ! -d "$WORDPRESS_DIR/$domain" ]; then
        print_error "Site not found: $domain"
        return 1
    fi

    if ! [[ "$quota_mb" =~ ^[0-9]+$ ]]; then
        print_error "Invalid quota value. Must be a number (in MB)"
        return 1
    fi

    echo "$quota_mb" > "$quota_file"
    print_success "Quota set for $domain: ${quota_mb}MB ($(bytes_to_human $(mb_to_bytes $quota_mb)))"
}

# Get current disk usage for a site (in bytes)
get_usage() {
    local domain=$1

    if [ ! -d "$WORDPRESS_DIR/$domain" ]; then
        echo "0"
        return 1
    fi

    du -sb "$WORDPRESS_DIR/$domain" 2>/dev/null | cut -f1 || echo "0"
}

# Check if site exceeds quota
check_quota() {
    local domain=$1
    local quota_mb=$(get_quota "$domain")
    local quota_bytes=$(mb_to_bytes $quota_mb)
    local usage_bytes=$(get_usage "$domain")

    if [ $usage_bytes -gt $quota_bytes ]; then
        return 1  # Quota exceeded
    else
        return 0  # Within quota
    fi
}

# Get quota usage percentage
get_usage_percent() {
    local domain=$1
    local quota_mb=$(get_quota "$domain")
    local quota_bytes=$(mb_to_bytes $quota_mb)
    local usage_bytes=$(get_usage "$domain")

    if [ $quota_bytes -eq 0 ]; then
        echo "0"
    else
        echo $(( (usage_bytes * 100) / quota_bytes ))
    fi
}

# Monitor all sites and send notifications
monitor() {
    local notify_threshold="${1:-80}"  # Default 80% threshold for warnings

    print_info "Monitoring disk quotas (threshold: ${notify_threshold}%)..."
    echo ""

    if [ ! -d "$WORDPRESS_DIR" ]; then
        print_error "WordPress directory not found: $WORDPRESS_DIR"
        return 1
    fi

    local issues_found=0

    for site_dir in "$WORDPRESS_DIR"/*; do
        if [ ! -d "$site_dir" ]; then
            continue
        fi

        local domain=$(basename "$site_dir")
        local quota_mb=$(get_quota "$domain")
        local quota_bytes=$(mb_to_bytes $quota_mb)
        local usage_bytes=$(get_usage "$domain")
        local usage_percent=$(get_usage_percent "$domain")
        local usage_human=$(bytes_to_human $usage_bytes)
        local quota_human=$(bytes_to_human $quota_bytes)

        if [ $usage_percent -ge 100 ]; then
            print_error "$domain: QUOTA EXCEEDED - ${usage_human}/${quota_human} (${usage_percent}%)"
            issues_found=$((issues_found + 1))

            # Send notification
            if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
                "$SCRIPT_DIR/notify.sh" quota "$domain" "$usage_human" "$quota_human" 2>/dev/null || true
            fi
        elif [ $usage_percent -ge $notify_threshold ]; then
            print_warning "$domain: ${usage_human}/${quota_human} (${usage_percent}%)"
            issues_found=$((issues_found + 1))

            # Send notification
            if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
                "$SCRIPT_DIR/notify.sh" quota "$domain" "$usage_human" "$quota_human" 2>/dev/null || true
            fi
        else
            print_success "$domain: ${usage_human}/${quota_human} (${usage_percent}%)"
        fi
    done

    echo ""
    if [ $issues_found -eq 0 ]; then
        print_success "All sites within quota limits"
    else
        print_warning "Found $issues_found site(s) with quota issues"
    fi
}

# List all sites with their quotas and usage
list() {
    print_info "Site Disk Usage Report"
    echo ""

    if [ ! -d "$WORDPRESS_DIR" ]; then
        print_error "WordPress directory not found: $WORDPRESS_DIR"
        return 1
    fi

    printf "%-30s %-15s %-15s %-10s\n" "DOMAIN" "USAGE" "QUOTA" "PERCENT"
    printf "%-30s %-15s %-15s %-10s\n" "$(printf '%.0s-' {1..30})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..15})" "$(printf '%.0s-' {1..10})"

    local total_usage=0
    local total_quota=0

    for site_dir in "$WORDPRESS_DIR"/*; do
        if [ ! -d "$site_dir" ]; then
            continue
        fi

        local domain=$(basename "$site_dir")
        local quota_mb=$(get_quota "$domain")
        local quota_bytes=$(mb_to_bytes $quota_mb)
        local usage_bytes=$(get_usage "$domain")
        local usage_percent=$(get_usage_percent "$domain")
        local usage_human=$(bytes_to_human $usage_bytes)
        local quota_human=$(bytes_to_human $quota_bytes)

        total_usage=$((total_usage + usage_bytes))
        total_quota=$((total_quota + quota_bytes))

        printf "%-30s %-15s %-15s %-10s\n" "$domain" "$usage_human" "$quota_human" "${usage_percent}%"
    done

    echo ""
    printf "%-30s %-15s %-15s\n" "TOTAL" "$(bytes_to_human $total_usage)" "$(bytes_to_human $total_quota)"
}

# Show detailed stats for a specific site
stats() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Usage: $0 stats <domain>"
        return 1
    fi

    if [ ! -d "$WORDPRESS_DIR/$domain" ]; then
        print_error "Site not found: $domain"
        return 1
    fi

    local quota_mb=$(get_quota "$domain")
    local quota_bytes=$(mb_to_bytes $quota_mb)
    local usage_bytes=$(get_usage "$domain")
    local usage_percent=$(get_usage_percent "$domain")
    local usage_human=$(bytes_to_human $usage_bytes)
    local quota_human=$(bytes_to_human $quota_bytes)
    local remaining_bytes=$((quota_bytes - usage_bytes))
    local remaining_human=$(bytes_to_human $remaining_bytes)

    print_info "Disk Usage Statistics for: $domain"
    echo ""
    echo "  Quota:     $quota_human ($quota_mb MB)"
    echo "  Usage:     $usage_human"
    echo "  Remaining: $remaining_human"
    echo "  Percent:   ${usage_percent}%"
    echo ""

    # Show breakdown by directory
    print_info "Top directories by size:"
    du -h --max-depth=1 "$WORDPRESS_DIR/$domain" 2>/dev/null | sort -hr | head -10

    # Check if quota is exceeded
    if [ $usage_percent -ge 100 ]; then
        echo ""
        print_error "QUOTA EXCEEDED! Please free up space or increase quota."
    elif [ $usage_percent -ge 80 ]; then
        echo ""
        print_warning "Usage is above 80%. Consider cleaning up or increasing quota."
    fi
}

# Remove quota configuration for a site
remove_quota() {
    local domain=$1
    local quota_file="$QUOTA_CONFIG_DIR/$domain.quota"

    if [ -f "$quota_file" ]; then
        rm "$quota_file"
        print_success "Quota configuration removed for $domain (will use default: ${DEFAULT_QUOTA_MB}MB)"
    else
        print_info "No custom quota configured for $domain"
    fi
}

# Main command handler
case "${1:-}" in
    set)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 set <domain> <quota_mb>"
            exit 1
        fi
        set_quota "$2" "$3"
        ;;

    get)
        if [ -z "$2" ]; then
            print_error "Usage: $0 get <domain>"
            exit 1
        fi
        quota_mb=$(get_quota "$2")
        echo "${quota_mb}MB ($(bytes_to_human $(mb_to_bytes $quota_mb)))"
        ;;

    check)
        if [ -z "$2" ]; then
            print_error "Usage: $0 check <domain>"
            exit 1
        fi
        domain=$2
        if check_quota "$domain"; then
            usage=$(bytes_to_human $(get_usage "$domain"))
            quota=$(bytes_to_human $(mb_to_bytes $(get_quota "$domain")))
            percent=$(get_usage_percent "$domain")
            print_success "$domain is within quota: ${usage}/${quota} (${percent}%)"
        else
            usage=$(bytes_to_human $(get_usage "$domain"))
            quota=$(bytes_to_human $(mb_to_bytes $(get_quota "$domain")))
            percent=$(get_usage_percent "$domain")
            print_error "$domain has exceeded quota: ${usage}/${quota} (${percent}%)"
            exit 1
        fi
        ;;

    monitor)
        threshold="${2:-80}"
        monitor "$threshold"
        ;;

    list)
        list
        ;;

    stats)
        stats "$2"
        ;;

    remove)
        if [ -z "$2" ]; then
            print_error "Usage: $0 remove <domain>"
            exit 1
        fi
        remove_quota "$2"
        ;;

    *)
        echo "WPFleet Quota Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  set <domain> <quota_mb>     - Set disk quota for a site (in MB)"
        echo "  get <domain>                - Get current quota for a site"
        echo "  check <domain>              - Check if site is within quota"
        echo "  monitor [threshold]         - Monitor all sites (default threshold: 80%)"
        echo "  list                        - List all sites with usage and quotas"
        echo "  stats <domain>              - Show detailed statistics for a site"
        echo "  remove <domain>             - Remove custom quota (use default)"
        echo ""
        echo "Examples:"
        echo "  $0 set example.com 10000    # Set 10GB quota"
        echo "  $0 get example.com          # Show current quota"
        echo "  $0 check example.com        # Check if within quota"
        echo "  $0 monitor 80               # Monitor all sites (warn at 80%)"
        echo "  $0 list                     # Show all sites"
        echo "  $0 stats example.com        # Detailed stats"
        echo ""
        echo "Configuration:"
        echo "  Default quota: ${DEFAULT_QUOTA_MB}MB ($(bytes_to_human $(mb_to_bytes $DEFAULT_QUOTA_MB)))"
        echo "  Set DEFAULT_SITE_QUOTA_MB in .env to change default"
        exit 1
        ;;
esac
