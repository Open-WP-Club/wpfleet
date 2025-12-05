#!/bin/bash

# WPFleet Cache Manager
# Full-page caching management using Redis Object Cache Pro approach
# Integrates with existing Valkey instance for both object and page caching

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/utils.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env" || exit 1

# Constants
VALKEY_CONTAINER="wpfleet_valkey"
FRANKENPHP_CONTAINER="wpfleet_frankenphp"
VALKEY_CLI="valkey-cli -a ${REDIS_PASSWORD}"

# Helper: Execute Valkey command
exec_valkey() {
    docker exec "$VALKEY_CONTAINER" $VALKEY_CLI "$@" 2>/dev/null
}

# Helper: Execute WP-CLI command for a site
exec_wp_cli() {
    local domain=$1
    shift
    docker exec -u www-data "$FRANKENPHP_CONTAINER" wp --path="/var/www/html/$domain" "$@" 2>/dev/null
}

# Helper: Check if site exists
site_exists() {
    local domain=$1
    if [ ! -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
        print_error "Site does not exist: $domain"
        return 1
    fi
    return 0
}

# Helper: Get cache prefix for a site
get_cache_prefix() {
    local domain=$1
    local db_name="wp_$(sanitize_domain_for_db $domain)"
    echo "${db_name}"
}

###########################################
# Plugin Installation Functions
###########################################

install_redis_cache_plugin() {
    local domain=$1

    print_header "Installing Redis Object Cache Plugin for $domain"

    if ! site_exists "$domain"; then
        return 1
    fi

    # Check if plugin is already installed
    if exec_wp_cli "$domain" plugin is-installed redis-cache; then
        print_warning "Redis Object Cache plugin already installed"

        # Check if active
        if exec_wp_cli "$domain" plugin is-active redis-cache; then
            print_ok "Plugin is active"
        else
            print_info "Activating plugin..."
            exec_wp_cli "$domain" plugin activate redis-cache
            print_ok "Plugin activated"
        fi
    else
        print_info "Installing Redis Object Cache plugin..."
        exec_wp_cli "$domain" plugin install redis-cache --activate
        print_ok "Plugin installed and activated"
    fi

    # Enable object cache
    print_info "Enabling object cache..."
    if exec_wp_cli "$domain" redis enable 2>/dev/null; then
        print_ok "Object cache enabled"
    else
        print_warning "Object cache may already be enabled"
    fi

    # Verify connection
    print_info "Verifying Redis connection..."
    local status=$(exec_wp_cli "$domain" redis status 2>&1 || echo "error")

    if echo "$status" | grep -q "Connected"; then
        print_ok "Connected to Valkey successfully"
    else
        print_warning "Could not verify connection (may still work)"
    fi

    print_success "Redis Object Cache configured for $domain"
}

install_cache_enabler_plugin() {
    local domain=$1

    print_header "Installing Cache Enabler Plugin for $domain"

    if ! site_exists "$domain"; then
        return 1
    fi

    # Check if plugin is already installed
    if exec_wp_cli "$domain" plugin is-installed cache-enabler; then
        print_warning "Cache Enabler plugin already installed"

        # Check if active
        if exec_wp_cli "$domain" plugin is-active cache-enabler; then
            print_ok "Plugin is active"
        else
            print_info "Activating plugin..."
            exec_wp_cli "$domain" plugin activate cache-enabler
            print_ok "Plugin activated"
        fi
    else
        print_info "Installing Cache Enabler plugin..."
        exec_wp_cli "$domain" plugin install cache-enabler --activate
        print_ok "Plugin installed and activated"
    fi

    print_success "Cache Enabler configured for $domain"
}

setup_full_page_cache() {
    local domain=$1

    print_header "Setting Up Full-Page Cache for $domain"

    if ! site_exists "$domain"; then
        return 1
    fi

    # Install Redis Object Cache for object caching
    install_redis_cache_plugin "$domain"

    echo ""

    # Install Cache Enabler for page caching
    install_cache_enabler_plugin "$domain"

    echo ""
    print_success "Full-page caching setup complete for $domain"
    print_info "Both object cache (Redis) and page cache (Cache Enabler) are now active"
}

###########################################
# Cache Purge Functions
###########################################

purge_all_cache() {
    print_header "Purging All Cache"

    print_info "Flushing all Valkey cache..."

    # Since dangerous commands are disabled, we need to purge by pattern
    # Get all keys and delete them
    local keys_deleted=0

    # For each WordPress site, purge its cache
    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        for site_dir in "$PROJECT_ROOT/data/wordpress"/*; do
            if [ -d "$site_dir" ]; then
                local domain=$(basename "$site_dir")
                local prefix=$(get_cache_prefix "$domain")

                print_info "Purging cache for $domain (prefix: $prefix:*)"

                # Use SCAN to find and delete keys with this prefix
                # Note: This is a workaround since KEYS command is disabled
                local count=$(exec_valkey --scan --pattern "${prefix}:*" | wc -l)

                if [ "$count" -gt 0 ]; then
                    exec_valkey --scan --pattern "${prefix}:*" | while read key; do
                        exec_valkey DEL "$key" >/dev/null 2>&1
                    done
                    keys_deleted=$((keys_deleted + count))
                    print_ok "Deleted $count keys"
                fi
            fi
        done
    fi

    # Also purge any page cache via Cache Enabler
    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        for site_dir in "$PROJECT_ROOT/data/wordpress"/*; do
            if [ -d "$site_dir" ]; then
                local domain=$(basename "$site_dir")

                # Clear Cache Enabler cache if plugin is active
                if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
                    exec_wp_cli "$domain" cache-enabler clear 2>/dev/null || true
                    print_ok "Cleared page cache for $domain"
                fi
            fi
        done
    fi

    print_success "All cache purged (${keys_deleted} object cache keys deleted)"
}

purge_site_cache() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Domain is required"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    print_header "Purging Cache for $domain"

    local prefix=$(get_cache_prefix "$domain")

    # Purge object cache from Valkey
    print_info "Purging object cache (prefix: $prefix:*)"
    local count=$(exec_valkey --scan --pattern "${prefix}:*" | wc -l)

    if [ "$count" -gt 0 ]; then
        exec_valkey --scan --pattern "${prefix}:*" | while read key; do
            exec_valkey DEL "$key" >/dev/null 2>&1
        done
        print_ok "Deleted $count object cache keys"
    else
        print_info "No object cache keys found"
    fi

    # Purge page cache via WP-CLI
    print_info "Purging page cache..."

    # Try Cache Enabler
    if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
        exec_wp_cli "$domain" cache-enabler clear 2>/dev/null || true
        print_ok "Cache Enabler cache cleared"
    fi

    # Try generic WordPress cache flush
    exec_wp_cli "$domain" cache flush 2>/dev/null || true
    print_ok "WordPress cache flushed"

    # Try Redis cache flush
    if exec_wp_cli "$domain" plugin is-active redis-cache 2>/dev/null; then
        exec_wp_cli "$domain" redis clear 2>/dev/null || true
        print_ok "Redis object cache cleared"
    fi

    print_success "Cache purged for $domain"
}

purge_url_cache() {
    local domain=$1
    local url=$2

    if [ -z "$domain" ] || [ -z "$url" ]; then
        print_error "Domain and URL are required"
        print_info "Usage: $0 purge-url <domain> <url>"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    print_header "Purging Cache for URL: $url"

    # Normalize URL
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="https://$domain$url"
    fi

    print_info "Purging cache for: $url"

    # Try Cache Enabler URL-specific purge
    if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
        # Cache Enabler stores cache as files, need to clear specific URL
        local path=$(echo "$url" | sed "s|https://$domain||" | sed "s|https://||" | sed "s|http://||")

        # Clear the cache directory for this URL
        local cache_dir="/var/www/html/$domain/wp-content/cache/cache-enabler"
        if docker exec "$FRANKENPHP_CONTAINER" test -d "$cache_dir"; then
            docker exec "$FRANKENPHP_CONTAINER" find "$cache_dir" -name "*$(echo $path | sed 's/\//-/g')*" -delete 2>/dev/null || true
            print_ok "Cleared page cache for URL"
        fi
    fi

    print_success "Cache purged for $url"
}

###########################################
# Cache Statistics Functions
###########################################

show_cache_stats() {
    print_header "Cache Statistics"

    # Valkey server info
    print_info "Valkey Server Information:"
    local info=$(exec_valkey INFO server | grep -E "redis_version|uptime_in_days|process_id")
    echo "$info" | while read line; do
        echo "  $line"
    done

    echo ""

    # Memory statistics
    print_info "Memory Usage:"
    local mem_info=$(exec_valkey INFO memory | grep -E "used_memory_human|used_memory_peak_human|maxmemory_human|mem_fragmentation_ratio")
    echo "$mem_info" | while read line; do
        echo "  $line"
    done

    echo ""

    # Cache statistics
    print_info "Cache Statistics:"
    local stats=$(exec_valkey INFO stats | grep -E "total_connections_received|total_commands_processed|keyspace_hits|keyspace_misses|evicted_keys")
    echo "$stats" | while read line; do
        echo "  $line"
    done

    # Calculate hit rate
    local hits=$(exec_valkey INFO stats | grep "keyspace_hits" | cut -d: -f2 | tr -d '\r')
    local misses=$(exec_valkey INFO stats | grep "keyspace_misses" | cut -d: -f2 | tr -d '\r')

    if [ ! -z "$hits" ] && [ ! -z "$misses" ] && [ "$hits" -gt 0 ] && [ "$misses" -gt 0 ]; then
        local total=$((hits + misses))
        local hit_rate=$(awk "BEGIN {printf \"%.2f\", ($hits / $total) * 100}")
        echo "  hit_rate: ${hit_rate}%"
    fi

    echo ""

    # Per-site statistics
    print_info "Per-Site Cache Keys:"
    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        for site_dir in "$PROJECT_ROOT/data/wordpress"/*; do
            if [ -d "$site_dir" ]; then
                local domain=$(basename "$site_dir")
                local prefix=$(get_cache_prefix "$domain")
                local count=$(exec_valkey --scan --pattern "${prefix}:*" 2>/dev/null | wc -l)

                if [ "$count" -gt 0 ]; then
                    echo "  $domain: $count keys"
                fi
            fi
        done
    fi
}

show_site_cache_stats() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Domain is required"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    print_header "Cache Statistics for $domain"

    local prefix=$(get_cache_prefix "$domain")

    # Count keys for this site
    print_info "Object Cache Keys:"
    local count=$(exec_valkey --scan --pattern "${prefix}:*" 2>/dev/null | wc -l)
    echo "  Total keys: $count"

    # Show sample keys
    if [ "$count" -gt 0 ]; then
        echo ""
        print_info "Sample Cache Keys (first 10):"
        exec_valkey --scan --pattern "${prefix}:*" 2>/dev/null | head -10 | while read key; do
            echo "  - $key"
        done
    fi

    echo ""

    # Redis cache plugin status
    print_info "Redis Object Cache Status:"
    if exec_wp_cli "$domain" plugin is-installed redis-cache 2>/dev/null; then
        if exec_wp_cli "$domain" plugin is-active redis-cache 2>/dev/null; then
            print_ok "Plugin: Active"

            # Try to get detailed status
            local redis_status=$(exec_wp_cli "$domain" redis status 2>&1 || echo "")
            if [ ! -z "$redis_status" ]; then
                echo "$redis_status" | while read line; do
                    echo "  $line"
                done
            fi
        else
            print_warning "Plugin: Installed but not active"
        fi
    else
        print_warning "Plugin: Not installed"
    fi

    echo ""

    # Cache Enabler status
    print_info "Page Cache Status:"
    if exec_wp_cli "$domain" plugin is-installed cache-enabler 2>/dev/null; then
        if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
            print_ok "Cache Enabler: Active"

            # Check cache directory size
            local cache_dir="/var/www/html/$domain/wp-content/cache/cache-enabler"
            if docker exec "$FRANKENPHP_CONTAINER" test -d "$cache_dir" 2>/dev/null; then
                local cache_size=$(docker exec "$FRANKENPHP_CONTAINER" du -sh "$cache_dir" 2>/dev/null | cut -f1)
                echo "  Cache size: $cache_size"

                local file_count=$(docker exec "$FRANKENPHP_CONTAINER" find "$cache_dir" -type f 2>/dev/null | wc -l)
                echo "  Cached pages: $file_count"
            fi
        else
            print_warning "Cache Enabler: Installed but not active"
        fi
    else
        print_warning "Cache Enabler: Not installed"
    fi
}

###########################################
# Cache Management Functions
###########################################

enable_site_cache() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Domain is required"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    setup_full_page_cache "$domain"
}

disable_site_cache() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Domain is required"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    print_header "Disabling Cache for $domain"

    # Disable Redis Object Cache
    if exec_wp_cli "$domain" plugin is-active redis-cache 2>/dev/null; then
        print_info "Disabling Redis Object Cache..."
        exec_wp_cli "$domain" redis disable 2>/dev/null || true
        exec_wp_cli "$domain" plugin deactivate redis-cache 2>/dev/null || true
        print_ok "Redis Object Cache disabled"
    fi

    # Disable Cache Enabler
    if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
        print_info "Disabling Cache Enabler..."
        exec_wp_cli "$domain" plugin deactivate cache-enabler 2>/dev/null || true
        print_ok "Cache Enabler disabled"
    fi

    # Purge site cache
    purge_site_cache "$domain"

    print_success "Cache disabled for $domain"
}

warm_site_cache() {
    local domain=$1

    if [ -z "$domain" ]; then
        print_error "Domain is required"
        return 1
    fi

    if ! site_exists "$domain"; then
        return 1
    fi

    print_header "Warming Cache for $domain"

    # First, make sure cache is enabled
    if ! exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
        print_warning "Cache Enabler is not active. Enabling it first..."
        setup_full_page_cache "$domain"
    fi

    print_info "Fetching sitemap to warm cache..."

    # Try to get URLs from sitemap
    local sitemap_url="https://$domain/sitemap.xml"
    local urls=()

    # Use curl to fetch sitemap and extract URLs
    local sitemap_content=$(docker exec "$FRANKENPHP_CONTAINER" curl -sk "$sitemap_url" 2>/dev/null || echo "")

    if [ ! -z "$sitemap_content" ]; then
        # Extract URLs from sitemap
        urls=$(echo "$sitemap_content" | grep -o '<loc>[^<]*</loc>' | sed 's/<loc>//g' | sed 's/<\/loc>//g')

        if [ ! -z "$urls" ]; then
            local count=$(echo "$urls" | wc -l)
            print_info "Found $count URLs in sitemap"

            # Warm cache by visiting each URL
            echo "$urls" | head -50 | while read url; do
                docker exec "$FRANKENPHP_CONTAINER" curl -sk "$url" > /dev/null 2>&1
                echo -n "."
            done
            echo ""
            print_ok "Cache warmed for up to 50 URLs"
        else
            print_warning "No URLs found in sitemap"
        fi
    else
        print_warning "Could not fetch sitemap from $sitemap_url"
    fi

    # Fallback: at least warm the homepage
    print_info "Warming homepage..."
    docker exec "$FRANKENPHP_CONTAINER" curl -sk "https://$domain/" > /dev/null 2>&1
    print_ok "Homepage cached"

    print_success "Cache warming complete for $domain"
}

###########################################
# List Functions
###########################################

list_cached_sites() {
    print_header "Cached Sites"

    if [ ! -d "$PROJECT_ROOT/data/wordpress" ]; then
        print_warning "No sites directory found"
        return
    fi

    for site_dir in "$PROJECT_ROOT/data/wordpress"/*; do
        if [ -d "$site_dir" ]; then
            local domain=$(basename "$site_dir")

            # Check if any cache plugin is active
            local redis_active=false
            local page_cache_active=false

            if exec_wp_cli "$domain" plugin is-active redis-cache 2>/dev/null; then
                redis_active=true
            fi

            if exec_wp_cli "$domain" plugin is-active cache-enabler 2>/dev/null; then
                page_cache_active=true
            fi

            if [ "$redis_active" = true ] || [ "$page_cache_active" = true ]; then
                echo -n "  ✓ $domain"

                local features=()
                [ "$redis_active" = true ] && features+=("object")
                [ "$page_cache_active" = true ] && features+=("page")

                if [ ${#features[@]} -gt 0 ]; then
                    echo " ($(IFS=,; echo "${features[*]}"))"
                else
                    echo ""
                fi
            else
                echo "  ✗ $domain (no cache)"
            fi
        fi
    done
}

###########################################
# Main Script
###########################################

show_usage() {
    cat << EOF
WPFleet Cache Manager

Usage: $0 <command> [options]

Setup Commands:
  setup <domain>              - Setup full-page cache (Redis + Cache Enabler)
  install-object <domain>     - Install only Redis Object Cache plugin
  install-page <domain>       - Install only Cache Enabler plugin

Purge Commands:
  purge-all                   - Purge all cache (all sites)
  purge <domain>              - Purge cache for a specific site
  purge-url <domain> <url>    - Purge cache for a specific URL

Management Commands:
  enable <domain>             - Enable caching for a site
  disable <domain>            - Disable caching for a site
  warm <domain>               - Warm cache by pre-loading pages

Statistics Commands:
  stats                       - Show global cache statistics
  stats <domain>              - Show cache statistics for a site
  list                        - List all cached sites

Examples:
  $0 setup example.com
  $0 purge example.com
  $0 purge-url example.com /blog/my-post/
  $0 stats example.com
  $0 warm example.com
  $0 list

EOF
}

# Check Docker is running
check_docker || exit 1

# Check containers
check_container "$VALKEY_CONTAINER" || exit 1
check_container "$FRANKENPHP_CONTAINER" || exit 1

# Parse commands
case "${1:-}" in
    setup)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        setup_full_page_cache "$2"
        ;;
    install-object)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        install_redis_cache_plugin "$2"
        ;;
    install-page)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        install_cache_enabler_plugin "$2"
        ;;
    purge-all)
        purge_all_cache
        ;;
    purge)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        purge_site_cache "$2"
        ;;
    purge-url)
        [ -z "$2" ] || [ -z "$3" ] && print_error "Domain and URL required" && exit 1
        purge_url_cache "$2" "$3"
        ;;
    enable)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        enable_site_cache "$2"
        ;;
    disable)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        disable_site_cache "$2"
        ;;
    warm)
        [ -z "$2" ] && print_error "Domain required" && exit 1
        warm_site_cache "$2"
        ;;
    stats)
        if [ -z "$2" ]; then
            show_cache_stats
        else
            show_site_cache_stats "$2"
        fi
        ;;
    list)
        list_cached_sites
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

exit 0
