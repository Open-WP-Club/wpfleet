#!/bin/bash

# Simple MariaDB Health Check for WPFleet
# Basic connectivity and functionality check

set -eo pipefail

# Check if MariaDB is responding to ping
if ! mysqladmin ping -h localhost --silent; then
    exit 1
fi

# Check if we can connect and execute basic queries
if ! mysql -e "SELECT 1;" >/dev/null 2>&1; then
    exit 1
fi

exit 0