#!/bin/bash

# WPFleet Health Check Script
# Monitor the health of all WPFleet services

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/utils.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env" || exit 1

# Track issues for notifications
HEALTH_ISSUES=()

# Track health issue for notification
track_issue() {
    local service="$1"
    local issue="$2"
    local severity="${3:-warning}"
    HEALTH_ISSUES+=("$service|$issue|$severity")
}

# Send notifications for health issues
send_health_notifications() {
    if [ ${#HEALTH_ISSUES[@]} -eq 0 ]; then
        return 0
    fi

    # Send notification for each issue
    for issue_data in "${HEALTH_ISSUES[@]}"; do
        IFS='|' read -r service issue severity <<< "$issue_data"
        send_health_notification "$service" "$issue" "$severity"
    done
}

# Check if service is healthy
check_service() {
    local service=$1
    local container=$2
    
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
        local running=$(docker inspect --format='{{.State.Running}}' "$container")
        
        if [ "$running" = "true" ]; then
            if [ "$status" = "healthy" ] || [ "$status" = "none" ]; then
                print_ok "$service is running"
                return 0
            else
                print_warning "$service is running but unhealthy (status: $status)"
                track_issue "$service" "Service unhealthy (status: $status)" "warning"
                return 1
            fi
        else
            print_error "$service is not running"
            track_issue "$service" "Service not running" "error"
            return 1
        fi
    else
        print_error "$service container not found"
        track_issue "$service" "Container not found" "error"
        return 1
    fi
}

# Function to get all sites
get_all_sites() {
    find "$PROJECT_ROOT/config/caddy/sites" -name "*.caddy" 2>/dev/null | while read f; do
        basename "$f" .caddy
    done | sort
}

# Main health check
echo "WPFleet Health Check Report"
echo "=========================="
echo "Date: $(date)"
echo ""

# Check core services
print_header "Core Services"
check_service "MariaDB" "wpfleet_mariadb"
check_service "Valkey" "wpfleet_valkey"
check_service "FrankenPHP" "wpfleet_frankenphp"

# Check MariaDB connectivity
print_header "Database Connectivity"
if docker exec wpfleet_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; then
    print_ok "MariaDB is accepting connections"

    # Count databases
    db_count=$(docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES LIKE 'wp_%';" 2>/dev/null | tail -n +2 | wc -l)
    print_ok "WordPress databases: $db_count"
else
    print_error "MariaDB is not accepting connections"
    track_issue "MariaDB" "Not accepting connections" "error"
fi

# Check Valkey connectivity
print_header "Cache Connectivity"
if docker exec wpfleet_valkey valkey-cli ping 2>/dev/null | grep -q PONG; then
    print_ok "Valkey is responding to ping"

    # Get memory usage
    valkey_memory=$(docker exec wpfleet_valkey valkey-cli info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    print_ok "Valkey memory usage: $valkey_memory"
else
    print_error "Valkey is not responding"
    track_issue "Valkey" "Not responding to ping" "error"
fi

# Check FrankenPHP/Caddy
print_header "Web Server Status"
if docker exec wpfleet_frankenphp curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    print_ok "FrankenPHP health check passed"
else
    print_error "FrankenPHP health check failed"
fi

# Check Caddy configuration
if docker exec wpfleet_frankenphp caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    print_ok "Caddy configuration is valid"
else
    print_error "Caddy configuration is invalid"
fi

# Check WordPress sites
print_header "WordPress Sites"
sites=$(get_all_sites)
if [ -z "$sites" ]; then
    print_warning "No WordPress sites found"
else
    for domain in $sites; do
        if [ -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
            # Check if WordPress is installed
            if [ -f "$PROJECT_ROOT/data/wordpress/$domain/wp-config.php" ]; then
                # Get site size
                site_size=$(du -sh "$PROJECT_ROOT/data/wordpress/$domain" 2>/dev/null | cut -f1)
                
                # Check if site responds
                if docker exec wpfleet_frankenphp curl -sf -H "Host: $domain" http://localhost >/dev/null 2>&1; then
                    print_ok "$domain - Active (Size: $site_size)"
                else
                    print_warning "$domain - Not responding (Size: $site_size)"
                fi
            else
                print_warning "$domain - WordPress not installed"
            fi
        else
            print_error "$domain - Directory missing"
        fi
    done
fi

# Check disk usage
print_header "Disk Usage"
disk_info=$(df -h "$PROJECT_ROOT" | tail -1)
disk_usage_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
disk_available=$(echo "$disk_info" | awk '{print $4}')
echo "$disk_info" | awk '{print "  Filesystem: " $1 "\n  Total: " $2 "\n  Used: " $3 " (" $5 ")\n  Available: " $4}'

# Check if disk usage is high
if [ "$disk_usage_percent" -ge 90 ]; then
    print_error "Disk usage is critically high: ${disk_usage_percent}%"
    track_issue "Disk Space" "Usage at ${disk_usage_percent}% (Critical)" "error"
    if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
        "$SCRIPT_DIR/notify.sh" disk "$disk_usage_percent" "$disk_available" "$PROJECT_ROOT" 2>/dev/null || true
    fi
elif [ "$disk_usage_percent" -ge 80 ]; then
    print_warning "Disk usage is high: ${disk_usage_percent}%"
    track_issue "Disk Space" "Usage at ${disk_usage_percent}% (Warning)" "warning"
    if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
        "$SCRIPT_DIR/notify.sh" disk "$disk_usage_percent" "$disk_available" "$PROJECT_ROOT" 2>/dev/null || true
    fi
fi

# Check Docker resources
print_header "Docker Resources"
container_count=$(docker ps -q | wc -l)
print_ok "Running containers: $container_count"

# Container stats
print_header "Container Resources"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep wpfleet || true

# Check for errors in logs
print_header "Recent Errors (last 24h)"
for container in wpfleet_mariadb wpfleet_valkey wpfleet_frankenphp; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        error_count=$(docker logs --since 24h "$container" 2>&1 | grep -iE "(error|fatal|critical)" | wc -l)
        if [ "$error_count" -gt 0 ]; then
            print_warning "$container: $error_count errors in logs"
        else
            print_ok "$container: No errors in logs"
        fi
    fi
done

# Summary
echo ""
print_header "Summary"
if check_service "MariaDB" "wpfleet_mariadb" >/dev/null 2>&1 && \
   check_service "Valkey" "wpfleet_valkey" >/dev/null 2>&1 && \
   check_service "FrankenPHP" "wpfleet_frankenphp" >/dev/null 2>&1; then
    print_ok "All core services are healthy"
    echo ""
    site_count=$(echo "$sites" | wc -w)
    print_ok "Total sites configured: $site_count"
else
    print_error "Some core services are unhealthy"
fi

# PHP Info
echo ""
print_header "PHP Configuration"
php_version=$(docker exec wpfleet_frankenphp php -v | head -1)
print_ok "PHP Version: $php_version"
memory_limit=$(docker exec wpfleet_frankenphp php -r "echo ini_get('memory_limit');" 2>/dev/null)
print_ok "Default Memory Limit: $memory_limit"

# Send notifications for any health issues
echo ""
send_health_notifications