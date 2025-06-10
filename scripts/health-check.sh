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

# Main health check
echo "WPFleet Health Check Report"
echo "=========================="
echo "Date: $(date)"
echo ""

# Check core services
print_header "Core Services"
check_service "MariaDB" "wpfleet_mariadb"
check_service "Redis" "wpfleet_redis"

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

# Check WordPress sites
print_header "WordPress Sites"
sites=$(docker ps --filter "label=wpfleet.site" --format "{{.Names}}" | sort)
if [ -z "$sites" ]; then
    print_warning "No WordPress sites found"
else
    for container in $sites; do
        domain=$(echo "$container" | sed 's/wpfleet_//')
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            # Check if container is running
            if [ "$(docker inspect --format='{{.State.Running}}' "$container")" = "true" ]; then
                # Check WordPress health
                if docker exec "$container" curl -sf http://localhost/health >/dev/null 2>&1; then
                    print_ok "$domain - Container running, health check passed"
                else
                    print_warning "$domain - Container running, health check failed"
                fi
            else
                print_error "$domain - Container not running"
            fi
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

# Memory usage
total_memory=$(docker stats --no-stream --format "{{.MemUsage}}" | awk '{sum += $1} END {print sum}')
print_ok "Total memory usage: Check 'docker stats' for details"

# Check for stopped containers
stopped_count=$(docker ps -a -q -f status=exited -f label=wpfleet.site | wc -l)
if [ "$stopped_count" -gt 0 ]; then
    print_warning "Stopped WPFleet containers: $stopped_count"
fi

# Check for errors in logs
print_header "Recent Errors (last 24h)"
for container in wpfleet_mariadb wpfleet_redis $sites; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        error_count=$(docker logs --since 24h "$container" 2>&1 | grep -iE "(error|fatal|critical)" | wc -l)
        if [ "$error_count" -gt 0 ]; then
            print_warning "$container: $error_count errors in logs"
        fi
    fi
done

# Summary
echo ""
print_header "Summary"
if check_service "MariaDB" "wpfleet_mariadb" >/dev/null 2>&1 && \
   check_service "Redis" "wpfleet_redis" >/dev/null 2>&1; then
    print_ok "Core services are healthy"
else
    print_error "Some core services are unhealthy"
fi

# Recommendations
if [ "$stopped_count" -gt 0 ]; then
    echo ""
    print_header "Recommendations"
    print_warning "Remove stopped containers: docker container prune -f"
fi