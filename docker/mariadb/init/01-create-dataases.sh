#!/bin/bash

# MariaDB initialization script
# This runs only on first container creation

echo "WPFleet MariaDB Initialization"
echo "=============================="

# Create wpfleet user if not exists
mysql -uroot -p${MYSQL_ROOT_PASSWORD} <<EOF
-- Create wpfleet user with necessary privileges
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';

-- Grant privileges to create and manage databases
GRANT CREATE, ALTER, DROP, INDEX, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, CREATE ROUTINE, ALTER ROUTINE ON *.* TO '${MYSQL_USER}'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES ON *.* TO '${MYSQL_USER}'@'%';

-- Apply changes
FLUSH PRIVILEGES;

-- Optimize for WordPress
SET GLOBAL max_connections = 500;
SET GLOBAL innodb_buffer_pool_size = 268435456;  -- 256MB
SET GLOBAL innodb_log_file_size = 67108864;      -- 64MB
SET GLOBAL innodb_flush_log_at_trx_commit = 2;
SET GLOBAL innodb_flush_method = O_DIRECT;

-- Create initial admin database
CREATE DATABASE IF NOT EXISTS wpfleet_admin CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

EOF

echo "MariaDB initialization complete!"