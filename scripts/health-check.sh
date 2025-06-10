#!/bin/bash

# WPFleet Health Check Script 
# Monitor the health of all WPFleet services

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
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
                return 1
            fi
        else
            print_error "$service is not running"
            return 1
        fi
    else
        print_error "$service container not found"
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
check_service "Redis" "wpfleet_redis"
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
fi

# Check Redis connectivity
print_header "Cache Connectivity"
if docker exec wpfleet_redis redis-cli ping 2>/dev/null | grep -q PONG; then
    print_ok "Redis is responding to ping"
    
    # Get memory usage
    redis_memory=$(docker exec wpfleet_redis redis-cli info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    print_ok "Redis memory usage: $redis_memory"
else
    print_error "Redis is not responding"
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
df -h "$PROJECT_ROOT" | tail -1 | awk '{print "  Filesystem: " $1 "\n  Total: " $2 "\n  Used: " $3 " (" $5 ")\n  Available: " $4}'

# Check Docker resources
print_header "Docker Resources"
container_count=$(docker ps -q | wc -l)
print_ok "Running containers: $container_count"

# Container stats
print_header "Container Resources"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep wpfleet || true

# Check for errors in logs
print_header "Recent Errors (last 24h)"
for container in wpfleet_mariadb wpfleet_redis wpfleet_frankenphp; do
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
   check_service "Redis" "wpfleet_redis" >/dev/null 2>&1 && \
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