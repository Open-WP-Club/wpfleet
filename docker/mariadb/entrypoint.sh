#!/bin/bash
set -eo pipefail

# WPFleet MariaDB Custom Entrypoint
# Optimizations for WordPress hosting

# Source the original entrypoint functions
source /usr/local/bin/docker-entrypoint.sh

# Custom initialization function
wpfleet_init() {
    echo "WPFleet MariaDB initialization starting..."
    
    # Auto-detect available RAM and adjust InnoDB buffer pool
    TOTAL_RAM_MB=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    
    # Set InnoDB buffer pool to 60% of available RAM (minimum 512MB, maximum 70% for safety)
    if [ $TOTAL_RAM_MB -lt 1024 ]; then
        # Less than 1GB RAM - use 512MB
        INNODB_BUFFER_POOL="512M"
        INNODB_INSTANCES=1
    elif [ $TOTAL_RAM_MB -lt 2048 ]; then
        # 1-2GB RAM - use 60%
        BUFFER_SIZE=$((TOTAL_RAM_MB * 60 / 100))
        INNODB_BUFFER_POOL="${BUFFER_SIZE}M"
        INNODB_INSTANCES=2
    elif [ $TOTAL_RAM_MB -lt 4096 ]; then
        # 2-4GB RAM - use 60%
        BUFFER_SIZE=$((TOTAL_RAM_MB * 60 / 100))
        INNODB_BUFFER_POOL="${BUFFER_SIZE}M"
        INNODB_INSTANCES=4
    else
        # 4GB+ RAM - use 60% but cap instances at 8
        BUFFER_SIZE=$((TOTAL_RAM_MB * 60 / 100))
        INNODB_BUFFER_POOL="${BUFFER_SIZE}M"
        INNODB_INSTANCES=8
    fi
    
    echo "Detected ${TOTAL_RAM_MB}MB RAM, setting InnoDB buffer pool to $INNODB_BUFFER_POOL with $INNODB_INSTANCES instances"
    
    # Update configuration file with detected values
    if [ -f /etc/mysql/conf.d/mariadb-wpfleet.cnf ]; then
        sed -i "s/innodb_buffer_pool_size = 2G/innodb_buffer_pool_size = $INNODB_BUFFER_POOL/" /etc/mysql/conf.d/mariadb-wpfleet.cnf
        sed -i "s/innodb_buffer_pool_instances = 4/innodb_buffer_pool_instances = $INNODB_INSTANCES/" /etc/mysql/conf.d/mariadb-wpfleet.cnf
    fi
    
    # Auto-detect storage type and optimize accordingly
    if [ -f /sys/block/sda/queue/rotational ]; then
        ROTATIONAL=$(cat /sys/block/sda/queue/rotational)
        if [ "$ROTATIONAL" = "0" ]; then
            echo "SSD storage detected, using optimized settings"
            # Settings already optimized for SSD in config file
        else
            echo "HDD storage detected, adjusting settings"
            # Adjust for HDD
            if [ -f /etc/mysql/conf.d/mariadb-wpfleet.cnf ]; then
                sed -i "s/innodb_io_capacity = 2000/innodb_io_capacity = 200/" /etc/mysql/conf.d/mariadb-wpfleet.cnf
                sed -i "s/innodb_io_capacity_max = 4000/innodb_io_capacity_max = 400/" /etc/mysql/conf.d/mariadb-wpfleet.cnf
            fi
        fi
    fi
    
    # Ensure log directories exist with correct permissions
    mkdir -p /var/log/mysql
    chown mysql:mysql /var/log/mysql
    chmod 755 /var/log/mysql
    
    echo "WPFleet MariaDB initialization completed"
}

# Custom pre-init function
wpfleet_pre_init() {
    echo "WPFleet pre-initialization..."
    
    # Set timezone to UTC
    export TZ=UTC
    
    echo "Pre-initialization completed"
}

# Override the original mysql_setup_db function to add our customizations
original_mysql_setup_db=$(declare -f mysql_setup_db)
eval "mysql_setup_db() {
    wpfleet_pre_init
    $original_mysql_setup_db
    wpfleet_init
}"

# If this is the first run, execute our custom setup
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "First run detected, will execute WPFleet optimizations after MySQL setup"
fi

# Execute the original entrypoint
exec docker-entrypoint.sh "$@"