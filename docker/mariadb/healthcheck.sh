#!/bin/bash

# Enhanced MariaDB Health Check for WPFleet
# Comprehensive connectivity and functionality check

set -eo pipefail

# Check if mysqld is running
if ! pgrep -x mysqld >/dev/null; then
    echo "ERROR: mysqld process not running"
    exit 1
fi

# Check if MariaDB is responding to ping
if ! mysqladmin ping -h localhost --silent 2>/dev/null; then
    echo "ERROR: MariaDB not responding to ping"
    exit 1
fi

# Check if we can connect and execute basic queries
if ! mysql -e "SELECT 1;" >/dev/null 2>&1; then
    echo "ERROR: Cannot execute queries"
    exit 1
fi

# Check if InnoDB is available
if ! mysql -sN -e "SELECT SUPPORT FROM information_schema.ENGINES WHERE ENGINE='InnoDB';" 2>/dev/null | grep -q -E "(YES|DEFAULT)"; then
    echo "ERROR: InnoDB not available"
    exit 1
fi

# Check for critical errors in error log (if exists)
if [ -f /var/log/mysql/error.log ]; then
    if tail -10 /var/log/mysql/error.log 2>/dev/null | grep -iE "(fatal|crash)" >/dev/null; then
        echo "WARNING: Critical errors in log"
    fi
fi

exit 0