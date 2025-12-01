#!/bin/bash
set -euo pipefail

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to detect optimal thread configuration
detect_optimal_config() {
    local cpu_cores=$(nproc)
    local memory_mb=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    
    log "Detected system resources: ${cpu_cores} CPU cores, ${memory_mb}MB RAM"
    
    # Calculate optimal thread count (conservative approach)
    local num_threads=$cpu_cores
    local max_threads=$(( cpu_cores * 2 ))
    
    # Adjust based on available memory
    local memory_per_thread=512  # MB
    local max_threads_by_memory=$(( (memory_mb * 70 / 100) / memory_per_thread ))
    
    if [ $max_threads_by_memory -lt $max_threads ]; then
        max_threads=$max_threads_by_memory
    fi
    
    # Ensure at least 2 threads
    [ $num_threads -lt 2 ] && num_threads=2
    [ $max_threads -lt 4 ] && max_threads=4
    
    log "Calculated thread configuration: num_threads=${num_threads}, max_threads=${max_threads}"
    
    # Set environment variables if not already set
    export FRANKENPHP_NUM_THREADS=${FRANKENPHP_NUM_THREADS:-$num_threads}
    export FRANKENPHP_MAX_THREADS=${FRANKENPHP_MAX_THREADS:-$max_threads}
}

# Function to wait for database
wait_for_db() {
    local host=${DB_HOST:-mariadb}
    local user=${DB_USER:-wpfleet}
    local password=${DB_PASSWORD}
    
    if [ -z "$password" ]; then
        log "No database password provided, skipping database check"
        return 0
    fi
    
    log "Waiting for database at ${host}..."
    local timeout=30
    local count=0
    
    while ! mysqladmin ping -h"${host}" -u"${user}" -p"${password}" --silent 2>/dev/null; do
        count=$((count + 1))
        if [ $count -gt $timeout ]; then
            log "WARNING: Database connection timeout after ${timeout} seconds, continuing anyway"
            return 0
        fi
        sleep 1
    done
    
    log "Database connection established"
}

# Function to setup logging directories
setup_logging() {
    local dirs=(
        "/var/log/frankenphp"
        "/var/log/php"
        "/var/cache/frankenphp"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown www-data:www-data "$dir" 2>/dev/null || true
        chmod 755 "$dir"
    done

    # Create site-specific log directories
    if [ -d "/var/www/html" ]; then
        for site_dir in /var/www/html/*/; do
            if [ -d "$site_dir" ]; then
                site_name=$(basename "$site_dir")
                mkdir -p "/var/log/frankenphp/${site_name}"
                chown www-data:www-data "/var/log/frankenphp/${site_name}" 2>/dev/null || true
                chmod 755 "/var/log/frankenphp/${site_name}"
            fi
        done
    fi

    # Create PHP error log
    touch /var/log/php/error.log
    chown www-data:www-data /var/log/php/error.log 2>/dev/null || true
    chmod 644 /var/log/php/error.log
}

# Function to create worker script
create_worker_script() {
    cat > /var/www/html/worker.php << 'EOF'
<?php
/**
 * FrankenPHP Worker Script for WordPress
 * Enhanced memory management and graceful restarts
 *
 * Note: FrankenPHP worker mode is handled by FrankenPHP itself.
 * This script just provides cleanup and monitoring hooks.
 */

// Prevent worker script termination when client connection is interrupted
ignore_user_abort(true);

// Set memory limit for worker
ini_set('memory_limit', '512M');

// Configuration
$requestCount = 0;
$maxRequests = (int) ($_ENV['FRANKENPHP_WORKER_MAX_REQUESTS'] ?? 1000);
$memoryThreshold = 400 * 1024 * 1024; // 400MB
$startTime = time();
$maxUptime = 3600; // 1 hour max uptime

// Helper function
function format_bytes($bytes, $precision = 2) {
    $units = array('B', 'KB', 'MB', 'GB');
    for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
        $bytes /= 1024;
    }
    return round($bytes, $precision) . ' ' . $units[$i];
}

// Check if we should restart
function should_restart(&$requestCount, $maxRequests, $memoryThreshold, $startTime, $maxUptime) {
    $requestCount++;
    $currentTime = time();
    $uptime = $currentTime - $startTime;
    $currentMemory = memory_get_usage(true);

    // Check restart conditions
    if ($requestCount >= $maxRequests) {
        error_log("Worker restart: max requests reached ({$requestCount}/{$maxRequests})");
        return true;
    }

    if ($currentMemory >= $memoryThreshold) {
        error_log("Worker restart: memory threshold exceeded (" . format_bytes($currentMemory) . ")");
        return true;
    }

    if ($uptime >= $maxUptime) {
        error_log("Worker restart: max uptime exceeded ({$uptime}s)");
        return true;
    }

    // Log status periodically
    if ($requestCount % 100 === 0) {
        error_log(sprintf(
            'Worker status: requests=%d, memory=%s, uptime=%ds',
            $requestCount,
            format_bytes($currentMemory),
            $uptime
        ));
    }

    return false;
}

// Main worker loop - FrankenPHP handles request processing
while (true) {
    // FrankenPHP automatically processes the request here

    // Check if we should restart
    if (should_restart($requestCount, $maxRequests, $memoryThreshold, $startTime, $maxUptime)) {
        error_log("Worker shutting down for restart");
        break; // Exit to trigger worker restart
    }

    // Clean up after each request
    if (function_exists('wp_cache_flush')) {
        wp_cache_flush();
    }

    // Force garbage collection periodically
    if ($requestCount % 50 === 0) {
        gc_collect_cycles();
    }
}

error_log("Worker shutting down gracefully");
EOF

    chown www-data:www-data /var/www/html/worker.php 2>/dev/null || true
    chmod 644 /var/www/html/worker.php
}

# Function to optimize OPcache based on available sites
optimize_opcache() {
    local site_count=0
    if [ -d "/var/www/html" ]; then
        # Count all directories in /var/www/html (excluding . and ..)
        site_count=$(find /var/www/html -maxdepth 1 -type d ! -name "." ! -name ".." ! -name "html" | wc -l)
    fi
    
    if [ $site_count -gt 0 ]; then
        log "Detected ${site_count} sites, optimizing OPcache..."
        
        # Adjust OPcache settings based on number of sites
        local max_files=$((site_count * 2000))
        local memory_consumption=$((site_count * 64))
        
        # Cap the values
        [ $max_files -gt 20000 ] && max_files=20000
        [ $memory_consumption -gt 512 ] && memory_consumption=512
        [ $memory_consumption -lt 256 ] && memory_consumption=256
        
        log "OPcache settings: max_files=${max_files}, memory=${memory_consumption}MB"
    fi
}

# Function to validate Caddyfile
validate_caddyfile() {
    local caddyfile="/etc/caddy/Caddyfile"
    
    if [ -f "$caddyfile" ]; then
        log "Validating Caddyfile configuration..."
        if caddy validate --config "$caddyfile" 2>/dev/null; then
            log "Caddyfile validation successful"
        else
            log "WARNING: Caddyfile validation failed, but continuing..."
        fi
    else
        log "WARNING: Caddyfile not found at $caddyfile"
    fi
}

# Main execution
main() {
    log "Starting FrankenPHP setup..."
    
    # Detect and set optimal configuration
    detect_optimal_config
    
    # Setup logging directories
    setup_logging
    
    # Wait for database if configured
    if [ -n "${DB_HOST:-}" ] && [ -n "${DB_PASSWORD:-}" ]; then
        wait_for_db
    fi
    
    # Optimize OPcache based on sites
    optimize_opcache
    
    # Create worker script
    create_worker_script
    
    # Validate Caddyfile
    validate_caddyfile
    
    log "FrankenPHP setup completed successfully"
    log "Thread config: FRANKENPHP_NUM_THREADS=${FRANKENPHP_NUM_THREADS}, FRANKENPHP_MAX_THREADS=${FRANKENPHP_MAX_THREADS}"
    
    # Execute the original command
    exec "$@"
}

# Run main function
main "$@"