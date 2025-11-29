#!/bin/sh
set -e

# Comprehensive health check for FrankenPHP container

# Check if HTTP endpoint responds
if ! curl -sf http://localhost:8080/health >/dev/null 2>&1; then
    echo "ERROR: Health endpoint not responding"
    exit 1
fi

# Check if PHP-FPM is responsive (if using FPM mode)
if command -v php-fpm >/dev/null 2>&1; then
    if ! pgrep -x php-fpm >/dev/null; then
        echo "ERROR: PHP-FPM not running"
        exit 1
    fi
fi

# Check OPcache status
if ! php -r "if (!opcache_get_status()) exit(1);" 2>/dev/null; then
    echo "WARNING: OPcache not active"
fi

# Check disk space (warn if < 10% free)
disk_usage=$(df /var/www/html | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$disk_usage" -gt 90 ]; then
    echo "WARNING: Disk usage at ${disk_usage}%"
fi

echo "Health check passed"
exit 0
