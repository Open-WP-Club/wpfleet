#!/bin/bash

# WPFleet Monitoring Dashboard
# Real-time monitoring of all services and sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common library
source "$SCRIPT_DIR/lib/common.sh"

# Load environment
load_env "$PROJECT_ROOT/.env" || exit 1

# Configuration
REFRESH_INTERVAL=${1:-5}  # Default 5 seconds

# Function to get container stats
get_container_stats() {
    local container=$1
    docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}" "$container" 2>/dev/null
}

# Function to get MariaDB stats
get_mariadb_stats() {
    docker exec wpfleet_mariadb mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" -sN -e "
        SELECT CONCAT(
            'Queries:', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='QUERIES'), '|',
            'QPS:', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='QUERIES') / (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='UPTIME'), '|',
            'Threads:', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='THREADS_CONNECTED'), '|',
            'Slow:', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='SLOW_QUERIES')
        );
    " 2>/dev/null || echo "N/A"
}

# Function to get Valkey stats
get_valkey_stats() {
    docker exec wpfleet_valkey valkey-cli -a "${REDIS_PASSWORD}" --no-auth-warning info stats 2>/dev/null | grep -E "^(total_commands_processed|instantaneous_ops_per_sec|keyspace_hits|keyspace_misses):" | tr '\n' '|' || echo "N/A"
}

# Function to get OPcache stats
get_opcache_stats() {
    docker exec wpfleet_frankenphp php -r "
        \$status = opcache_get_status();
        if (\$status) {
            echo 'Hit Rate:' . round(\$status['opcache_statistics']['opcache_hit_rate'], 2) . '%|';
            echo 'Memory:' . round(\$status['memory_usage']['used_memory'] / 1024 / 1024, 1) . 'MB/' . round(\$status['memory_usage']['free_memory'] / 1024 / 1024, 1) . 'MB|';
            echo 'Keys:' . \$status['opcache_statistics']['num_cached_keys'] . '/' . \$status['opcache_statistics']['max_cached_keys'];
        } else {
            echo 'OPcache disabled';
        }
    " 2>/dev/null || echo "N/A"
}

# Function to get site count and status
get_sites_status() {
    local total=0
    local active=0

    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        for site_dir in "$PROJECT_ROOT/data/wordpress"/*/; do
            if [ -d "$site_dir" ]; then
                total=$((total + 1))
                if [ -f "${site_dir}wp-config.php" ]; then
                    active=$((active + 1))
                fi
            fi
        done
    fi

    echo "$active/$total"
}

# Function to display dashboard
display_dashboard() {
    clear

    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                         WPFleet Monitoring Dashboard                         ║"
    echo "║                         $(date '+%Y-%m-%d %H:%M:%S')                              ║"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Container Status
    print_header "Container Status"
    for container in wpfleet_mariadb wpfleet_valkey wpfleet_frankenphp; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            stats=$(get_container_stats "$container")
            IFS='|' read -r cpu mem mem_pct net block <<< "$stats"
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

            if [ "$status" = "healthy" ] || [ "$status" = "none" ]; then
                echo -e "  ${GREEN}●${NC} $container"
            else
                echo -e "  ${YELLOW}●${NC} $container (status: $status)"
            fi
            echo "      CPU: $cpu | Memory: $mem ($mem_pct) | Network: $net"
        else
            echo -e "  ${RED}●${NC} $container (not running)"
        fi
    done

    echo ""

    # MariaDB Stats
    print_header "MariaDB Statistics"
    mariadb_stats=$(get_mariadb_stats)
    IFS='|' read -r queries qps threads slow <<< "$mariadb_stats"
    echo "  $queries | $qps | $threads | $slow"

    echo ""

    # Valkey Stats
    print_header "Valkey Statistics"
    valkey_stats=$(get_valkey_stats)
    if [ "$valkey_stats" != "N/A" ]; then
        echo "  $valkey_stats" | tr '|' '\n' | sed 's/^/  /'
    else
        echo "  Unable to fetch Valkey stats"
    fi

    echo ""

    # OPcache Stats
    print_header "OPcache Statistics"
    opcache_stats=$(get_opcache_stats)
    echo "  $opcache_stats" | tr '|' '\n' | sed 's/^/  /'

    echo ""

    # Sites Status
    print_header "WordPress Sites"
    sites_status=$(get_sites_status)
    echo "  Active Sites: $sites_status"

    # Recent sites
    if [ -d "$PROJECT_ROOT/data/wordpress" ]; then
        echo ""
        echo "  Recent sites:"
        ls -lt "$PROJECT_ROOT/data/wordpress" | grep '^d' | head -5 | awk '{printf "    %s %s %s - %s\n", $6, $7, $8, $9}'
    fi

    echo ""

    # Disk Usage
    print_header "Disk Usage"
    df -h "$PROJECT_ROOT" | tail -1 | awk '{printf "  Total: %s | Used: %s (%s) | Available: %s\n", $2, $3, $5, $4}'

    echo ""

    # Recent Errors
    print_header "Recent Errors (last hour)"
    error_count=0
    for container in wpfleet_mariadb wpfleet_valkey wpfleet_frankenphp; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            errors=$(docker logs --since 1h "$container" 2>&1 | grep -iE "(error|fatal|critical)" | wc -l)
            if [ "$errors" -gt 0 ]; then
                echo "  $container: $errors errors"
                error_count=$((error_count + errors))
            fi
        fi
    done

    if [ $error_count -eq 0 ]; then
        echo -e "  ${GREEN}No errors found${NC}"
    fi

    echo ""
    echo "Press Ctrl+C to exit | Refresh: ${REFRESH_INTERVAL}s"
}

# Main loop
trap 'echo -e "\n\nExiting..."; exit 0' SIGINT SIGTERM

while true; do
    display_dashboard
    sleep "$REFRESH_INTERVAL"
done
