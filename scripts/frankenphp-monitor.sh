#!/bin/bash

# WPFleet FrankenPHP Performance Monitor
# Monitor and analyze FrankenPHP performance and health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
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

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# Function to check if container is running
check_container() {
    local container=$1
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Function to analyze FrankenPHP performance
analyze_performance() {
    print_header "FrankenPHP Performance Analysis"
    
    local container="wpfleet_frankenphp"
    
    if ! check_container "$container"; then
        print_error "FrankenPHP container not running"
        return 1
    fi
    
    # Container stats
    print_info "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" "$container" 2>/dev/null || print_warning "Could not get container stats"
    
    # Thread configuration
    print_info "FrankenPHP Configuration:"
    docker exec "$container" env 2>/dev/null | grep -E "^FRANKENPHP_" | while read line; do
        echo "    $line"
    done || print_warning "Could not get FrankenPHP environment variables"
    
    # PHP configuration
    print_info "PHP Configuration:"
    docker exec "$container" php -r "
        echo 'PHP Version: ' . PHP_VERSION . \"\n\";
        echo 'Memory limit: ' . ini_get('memory_limit') . \"\n\";
        echo 'Max execution time: ' . ini_get('max_execution_time') . 's' . \"\n\";
        echo 'Upload max filesize: ' . ini_get('upload_max_filesize') . \"\n\";
        echo 'Thread safe: ' . (ZEND_THREAD_SAFE ? 'Yes' : 'No') . \"\n\";
    " 2>/dev/null || print_warning "Could not get PHP information"
    
    # Memory usage analysis
    print_info "Memory Analysis:"
    docker exec "$container" php -r "
        echo 'Current usage: ' . round(memory_get_usage(true) / 1024 / 1024, 2) . 'MB' . \"\n\";
        echo 'Peak usage: ' . round(memory_get_peak_usage(true) / 1024 / 1024, 2) . 'MB' . \"\n\";
    " 2>/dev/null || print_warning "Could not get memory information"
    
    # OPcache statistics
    print_info "OPcache Status:"
    docker exec "$container" php -r "
        if (function_exists('opcache_get_status')) {
            \$status = opcache_get_status();
            if (\$status) {
                echo 'Enabled: Yes' . \"\n\";
                echo 'Memory usage: ' . round(\$status['memory_usage']['used_memory'] / 1024 / 1024, 2) . 'MB / ' . 
                     round((\$status['memory_usage']['used_memory'] + \$status['memory_usage']['free_memory']) / 1024 / 1024, 2) . 'MB' . \"\n\";
                echo 'Hit rate: ' . round(\$status['opcache_statistics']['opcache_hit_rate'], 2) . '%' . \"\n\";
                echo 'Cached scripts: ' . \$status['opcache_statistics']['num_cached_scripts'] . \"\n\";
                echo 'Max cached scripts: ' . \$status['opcache_statistics']['max_cached_keys'] . \"\n\";
            } else {
                echo 'OPcache enabled but no status available' . \"\n\";
            }
        } else {
            echo 'OPcache not available' . \"\n\";
        }
    " 2>/dev/null || print_warning "Could not get OPcache information"
    
    # APCu statistics
    print_info "APCu Status:"
    docker exec "$container" php -r "
        if (function_exists('apcu_cache_info')) {
            \$info = apcu_cache_info();
            if (\$info) {
                echo 'Enabled: Yes' . \"\n\";
                echo 'Memory size: ' . round(\$info['mem_size'] / 1024 / 1024, 2) . 'MB' . \"\n\";
                if (isset(\$info['num_hits']) && isset(\$info['num_misses'])) {
                    \$total = \$info['num_hits'] + \$info['num_misses'];
                    if (\$total > 0) {
                        echo 'Hit rate: ' . round(\$info['num_hits'] / \$total * 100, 2) . '%' . \"\n\";
                    }
                }
                echo 'Cached entries: ' . (\$info['num_entries'] ?? 'Unknown') . \"\n\";
            } else {
                echo 'APCu enabled but no info available' . \"\n\";
            }
        } else {
            echo 'APCu not available' . \"\n\";
        }
    " 2>/dev/null || print_warning "Could not get APCu information"
}

# Function to check worker status
check_worker_status() {
    print_header "Worker Status"
    
    local container="wpfleet_frankenphp"
    
    if ! check_container "$container"; then
        print_error "FrankenPHP container not running"
        return 1
    fi
    
    # Check if worker script exists
    if docker exec "$container" test -f /var/www/html/worker.php 2>/dev/null; then
        print_ok "Worker script found"
        
        # Check worker configuration
        print_info "Worker Environment Variables:"
        docker exec "$container" env 2>/dev/null | grep -E "^FRANKENPHP_WORKER" | while read line; do
            echo "    $line"
        done || print_warning "No worker environment variables found"
        
        # Check for worker processes (this might not show much in FrankenPHP)
        print_info "Process Information:"
        docker exec "$container" ps aux 2>/dev/null | grep -E "(frankenphp|caddy|php)" | head -5 || print_warning "Could not get process information"
    else
        print_warning "Worker script not found at /var/www/html/worker.php"
        print_info "Creating worker script..."
        
        # Create basic worker script if missing
        docker exec "$container" bash -c 'cat > /var/www/html/worker.php << "EOF"
<?php
// Basic FrankenPHP worker script
ignore_user_abort(true);
$requestCount = 0;
$maxRequests = 1000;

while (true) {
    $requestCount++;
    if ($requestCount >= $maxRequests) {
        error_log("Worker restarting after {$requestCount} requests");
        break;
    }
    
    // Process request automatically handled by FrankenPHP
    
    if ($requestCount % 100 === 0) {
        error_log("Worker processed {$requestCount} requests, memory: " . round(memory_get_usage(true)/1024/1024, 2) . "MB");
    }
}
EOF' 2>/dev/null && print_ok "Worker script created" || print_warning "Could not create worker script"
    fi
}

# Function to perform health checks
perform_health_checks() {
    print_header "Health Checks"
    
    local container="wpfleet_frankenphp"
    
    if ! check_container "$container"; then
        print_error "FrankenPHP container not running"
        return 1
    fi
    
    # Container health
    local health_status
    if health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null); then
        if [ "$health_status" = "healthy" ]; then
            print_ok "Container health: $health_status"
        else
            print_warning "Container health: $health_status"
        fi
    else
        print_warning "No health check configured"
    fi
    
    # HTTP health check
    if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
        print_ok "HTTP health check passed"
    else
        print_error "HTTP health check failed"
    fi
    
    # Caddy configuration validation
    if docker exec "$container" caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        print_ok "Caddy configuration valid"
    else
        print_error "Caddy configuration invalid"
    fi
    
    # Database connectivity
    if check_container "wpfleet_mariadb" && docker exec wpfleet_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; then
        print_ok "Database connectivity: OK"
    else
        print_warning "Database connectivity: FAILED or not running"
    fi
    
    # Valkey connectivity
    if check_container "wpfleet_valkey" && docker exec wpfleet_valkey valkey-cli ping 2>/dev/null | grep -q PONG; then
        print_ok "Valkey connectivity: OK"
    else
        print_warning "Valkey connectivity: FAILED or not running"
    fi
    
    # Check port bindings
    if ss -tlnp | grep -q ":80 "; then
        print_ok "Port 80 bound"
    else
        print_warning "Port 80 not bound"
    fi
    
    if ss -tlnp | grep -q ":443 "; then
        print_ok "Port 443 bound"
    else
        print_warning "Port 443 not bound"
    fi
}

# Function to analyze logs for errors
analyze_logs() {
    print_header "Log Analysis (Last 1 Hour)"
    
    local container="wpfleet_frankenphp"
    local since="1h"
    
    if ! check_container "$container"; then
        print_error "FrankenPHP container not running"
        return 1
    fi
    
    # PHP errors
    print_info "PHP Error Analysis:"
    if docker exec "$container" test -f /var/log/php/error.log 2>/dev/null; then
        local php_errors
        php_errors=$(docker exec "$container" grep -c "FATAL\|ERROR" /var/log/php/error.log 2>/dev/null || echo "0")
        if [ "${php_errors}" -gt 0 ]; then
            print_warning "PHP errors found: $php_errors"
            print_info "Recent PHP errors:"
            docker exec "$container" tail -5 /var/log/php/error.log 2>/dev/null | sed 's/^/    /' || echo "    Could not read error log"
        else
            print_ok "No PHP errors in log file"
        fi
    else
        print_warning "PHP error log not found"
    fi
    
    # Container logs
    print_info "Container Log Analysis:"
    local container_errors
    if container_errors=$(docker logs --since="$since" "$container" 2>&1 | grep -ic "error\|fatal\|critical" || echo "0"); then
        if [ "$container_errors" -gt 0 ]; then
            print_warning "Container errors found: $container_errors"
            print_info "Recent critical errors:"
            docker logs --since="$since" "$container" 2>&1 | grep -i "fatal\|critical" | tail -3 | sed 's/^/    /' || echo "    No critical errors"
        else
            print_ok "No container errors found"
        fi
    fi
    
    # Worker log analysis
    print_info "Worker Log Analysis:"
    docker logs --since="$since" "$container" 2>&1 | grep -i "worker" | tail -3 | sed 's/^/    /' || echo "    No worker logs found"
}

# Function to get performance recommendations
get_recommendations() {
    print_header "Performance Recommendations"
    
    local container="wpfleet_frankenphp"
    
    if ! check_container "$container"; then
        print_error "FrankenPHP container not running"
        return 1
    fi
    
    # Check CPU usage
    local cpu_usage
    if cpu_usage=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container" 2>/dev/null | tr -d '%'); then
        if [ -n "$cpu_usage" ] && (( $(echo "$cpu_usage > 80" | awk '{print ($1 > $2)}') )); then
            print_warning "High CPU usage (${cpu_usage}%) - Consider optimizing code or increasing resources"
        elif [ -n "$cpu_usage" ]; then
            print_ok "CPU usage acceptable (${cpu_usage}%)"
        fi
    fi
    
    # Check memory usage
    local mem_usage_raw
    if mem_usage_raw=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null); then
        local mem_used=$(echo "$mem_usage_raw" | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        if [ -n "$mem_used" ] && (( $(echo "$mem_used > 1500" | awk '{print ($1 > $2)}') )); then
            print_warning "High memory usage (${mem_usage_raw}) - Consider optimizing or increasing limits"
        elif [ -n "$mem_used" ]; then
            print_ok "Memory usage acceptable (${mem_usage_raw})"
        fi
    fi
    
    # Check OPcache hit rate
    local hit_rate
    if hit_rate=$(docker exec "$container" php -r "
        \$status = opcache_get_status();
        if (\$status && isset(\$status['opcache_statistics']['opcache_hit_rate'])) {
            echo \$status['opcache_statistics']['opcache_hit_rate'];
        }
    " 2>/dev/null); then
        if [ -n "$hit_rate" ] && (( $(echo "$hit_rate < 95" | awk '{print ($1 < $2)}') )); then
            print_warning "Low OPcache hit rate (${hit_rate}%) - Consider increasing opcache.memory_consumption"
        elif [ -n "$hit_rate" ]; then
            print_ok "OPcache hit rate good (${hit_rate}%)"
        fi
    fi
    
    print_info "General Recommendations:"
    echo "  • Monitor memory usage and set appropriate limits"
    echo "  • Enable OPcache with validation_timestamps=0 in production"
    echo "  • Use Valkey object caching for WordPress (Redis-compatible)"
    echo "  • Monitor error logs regularly"
    echo "  • Consider enabling FrankenPHP worker mode if supported"
    echo "  • Use HTTP/2 and compression for better performance"
}

# Function to run simple benchmark
run_benchmark() {
    print_header "Performance Benchmark"
    
    local test_url="http://localhost:8080/health"
    local requests=50
    local concurrency=5
    
    print_info "Running benchmark: $requests requests with $concurrency concurrent connections"
    print_info "Target URL: $test_url"
    
    if command -v ab >/dev/null 2>&1; then
        print_info "Using Apache Bench (ab):"
        ab -n "$requests" -c "$concurrency" "$test_url" 2>/dev/null | grep -E "(Requests per second|Time per request|Transfer rate)" | sed 's/^/  /'
    elif command -v curl >/dev/null 2>&1; then
        print_info "Using curl for simple test..."
        local start_time=$(date +%s.%N)
        local success_count=0
        
        for i in $(seq 1 10); do
            if curl -s --max-time 5 "$test_url" >/dev/null 2>&1; then
                success_count=$((success_count + 1))
            fi
        done
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "5")
        local rps=$(echo "scale=2; $success_count / $duration" | bc 2>/dev/null || echo "2")
        
        echo "  Simple test results:"
        echo "    Successful requests: $success_count/10"
        echo "    Approximate RPS: $rps"
        echo "    Total time: ${duration}s"
    else
        print_warning "No benchmarking tools available (install apache2-utils for 'ab' command)"
    fi
}

# Function to show real-time monitoring
watch_performance() {
    echo "Watching FrankenPHP performance (press Ctrl+C to stop)..."
    echo ""
    
    while true; do
        clear
        echo "FrankenPHP Performance Monitor - $(date)"
        echo "======================================="
        
        # Quick stats
        if check_container "wpfleet_frankenphp"; then
            echo ""
            docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" wpfleet_frankenphp 2>/dev/null || echo "Could not get stats"
            
            # Memory info
            echo ""
            echo "Memory Details:"
            docker exec wpfleet_frankenphp php -r "
                echo '  Current: ' . round(memory_get_usage(true) / 1024 / 1024, 2) . 'MB' . \"\n\";
                echo '  Peak: ' . round(memory_get_peak_usage(true) / 1024 / 1024, 2) . 'MB' . \"\n\";
            " 2>/dev/null || echo "  Could not get memory info"
            
            # OPcache hit rate
            echo ""
            echo "OPcache:"
            docker exec wpfleet_frankenphp php -r "
                \$status = opcache_get_status();
                if (\$status) {
                    echo '  Hit rate: ' . round(\$status['opcache_statistics']['opcache_hit_rate'], 2) . '%' . \"\n\";
                    echo '  Memory: ' . round(\$status['memory_usage']['used_memory'] / 1024 / 1024, 2) . 'MB used' . \"\n\";
                } else {
                    echo '  Not available' . \"\n\";
                }
            " 2>/dev/null || echo "  Could not get OPcache info"
        else
            echo "FrankenPHP container not running!"
        fi
        
        sleep 5
    done
}

# Main execution
case "${1:-status}" in
    status)
        echo "FrankenPHP Performance Monitor"
        echo "============================="
        echo "Date: $(date)"
        echo ""
        
        perform_health_checks
        analyze_performance
        check_worker_status
        analyze_logs
        get_recommendations
        ;;
        
    benchmark)
        run_benchmark
        ;;
        
    logs)
        shift
        if check_container "wpfleet_frankenphp"; then
            docker logs "${@}" wpfleet_frankenphp
        else
            echo "FrankenPHP container not running"
            exit 1
        fi
        ;;
        
    watch)
        watch_performance
        ;;
        
    health)
        perform_health_checks
        ;;
        
    *)
        echo "FrankenPHP Performance Monitor"
        echo ""
        echo "Usage: $0 {status|benchmark|logs|watch|health}"
        echo ""
        echo "Commands:"
        echo "  status     - Show complete status report (default)"
        echo "  benchmark  - Run performance benchmark"
        echo "  logs       - Show container logs"
        echo "  watch      - Watch performance in real-time"
        echo "  health     - Show health checks only"
        echo ""
        echo "Examples:"
        echo "  $0 status"
        echo "  $0 benchmark"
        echo "  $0 logs --tail 100"
        echo "  $0 watch"
        echo "  $0 health"
        exit 1
        ;;
esac