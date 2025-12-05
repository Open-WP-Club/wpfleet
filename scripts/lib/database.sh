#!/bin/bash

# WPFleet Database Library Functions
# Wrapper functions for database operations

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/docker.sh"

# Get database name for a domain
get_db_name() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        print_error "Domain required to get database name"
        return 1
    fi
    # Use the common sanitize function
    sanitize_domain_for_db "$domain"
}

# Check if database exists
db_exists() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    local result=$(docker_mysql -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null | grep -c "$db_name")
    [ "$result" -gt 0 ]
}

# Create database
db_create() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    if db_exists "$db_name"; then
        print_warning "Database $db_name already exists"
        return 0
    fi

    print_info "Creating database: $db_name"
    docker_mysql -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
}

# Drop database
db_drop() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    if ! db_exists "$db_name"; then
        print_warning "Database $db_name does not exist"
        return 0
    fi

    print_info "Dropping database: $db_name"
    docker_mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null
}

# Get database size in MB
db_size() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    docker_mysql -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as size_mb
                     FROM information_schema.tables
                     WHERE table_schema='$db_name';" 2>/dev/null | tail -n 1
}

# Get list of all WordPress databases
db_list_wordpress() {
    docker_mysql -e "SHOW DATABASES LIKE 'wp_%';" 2>/dev/null | tail -n +2
}

# Get list of all databases
db_list_all() {
    docker_mysql -e "SHOW DATABASES;" 2>/dev/null | tail -n +2 | grep -v -E "^(information_schema|performance_schema|mysql|sys)$"
}

# Get table count in database
db_table_count() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    docker_mysql -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db_name';" 2>/dev/null | tail -n 1
}

# Export database to file
db_export() {
    local db_name=$1
    local output_file=$2

    if [[ -z "$db_name" ]] || [[ -z "$output_file" ]]; then
        print_error "Database name and output file required"
        return 1
    fi

    if ! db_exists "$db_name"; then
        print_error "Database $db_name does not exist"
        return 1
    fi

    print_info "Exporting database $db_name to $output_file"
    docker exec "$MARIADB_CONTAINER" mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD}" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        "$db_name" > "$output_file" 2>/dev/null

    if [ $? -eq 0 ] && [ -s "$output_file" ]; then
        print_success "Database exported successfully"
        return 0
    else
        print_error "Failed to export database"
        return 1
    fi
}

# Import database from file
db_import() {
    local db_name=$1
    local input_file=$2

    if [[ -z "$db_name" ]] || [[ -z "$input_file" ]]; then
        print_error "Database name and input file required"
        return 1
    fi

    if [ ! -f "$input_file" ]; then
        print_error "Input file not found: $input_file"
        return 1
    fi

    # Create database if it doesn't exist
    if ! db_exists "$db_name"; then
        db_create "$db_name" || return 1
    fi

    print_info "Importing database from $input_file to $db_name"
    docker_mysql_stdin "$db_name" < "$input_file" 2>/dev/null

    if [ $? -eq 0 ]; then
        print_success "Database imported successfully"
        return 0
    else
        print_error "Failed to import database"
        return 1
    fi
}

# Optimize database tables
db_optimize() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    if ! db_exists "$db_name"; then
        print_error "Database $db_name does not exist"
        return 1
    fi

    print_info "Optimizing database: $db_name"

    # Get all tables in the database
    local tables=$(docker_mysql -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='$db_name';" 2>/dev/null)

    if [[ -z "$tables" ]]; then
        print_warning "No tables found in database $db_name"
        return 0
    fi

    # Optimize each table
    while IFS= read -r table; do
        docker_mysql -e "OPTIMIZE TABLE \`$db_name\`.\`$table\`;" 2>/dev/null >/dev/null
    done <<< "$tables"

    print_success "Database optimized"
    return 0
}

# Repair database tables
db_repair() {
    local db_name=$1
    if [[ -z "$db_name" ]]; then
        print_error "Database name required"
        return 1
    fi

    if ! db_exists "$db_name"; then
        print_error "Database $db_name does not exist"
        return 1
    fi

    print_info "Repairing database: $db_name"

    # Get all tables in the database
    local tables=$(docker_mysql -N -e "SELECT table_name FROM information_schema.tables WHERE table_schema='$db_name';" 2>/dev/null)

    if [[ -z "$tables" ]]; then
        print_warning "No tables found in database $db_name"
        return 0
    fi

    # Repair each table
    while IFS= read -r table; do
        docker_mysql -e "REPAIR TABLE \`$db_name\`.\`$table\`;" 2>/dev/null >/dev/null
    done <<< "$tables"

    print_success "Database repaired"
    return 0
}

# Search and replace in database
db_search_replace() {
    local db_name=$1
    local search=$2
    local replace=$3

    if [[ -z "$db_name" ]] || [[ -z "$search" ]] || [[ -z "$replace" ]]; then
        print_error "Database name, search string, and replace string required"
        return 1
    fi

    if ! db_exists "$db_name"; then
        print_error "Database $db_name does not exist"
        return 1
    fi

    print_info "Performing search-replace in database $db_name"
    print_info "Searching for: $search"
    print_info "Replacing with: $replace"

    # This requires WP-CLI, so we'll just provide the SQL approach
    # For WordPress sites, WP-CLI search-replace is preferred
    print_warning "For WordPress sites, use WP-CLI search-replace command instead"

    return 0
}

# Get database user grants
db_show_grants() {
    local username=${1:-root}
    docker_mysql -e "SHOW GRANTS FOR '$username'@'%';" 2>/dev/null
}

# Create database user
db_create_user() {
    local username=$1
    local password=$2
    local db_name=$3

    if [[ -z "$username" ]] || [[ -z "$password" ]]; then
        print_error "Username and password required"
        return 1
    fi

    print_info "Creating database user: $username"

    # Create user
    docker_mysql -e "CREATE USER IF NOT EXISTS '$username'@'%' IDENTIFIED BY '$password';" 2>/dev/null

    # Grant privileges if database specified
    if [[ -n "$db_name" ]]; then
        docker_mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$username'@'%';" 2>/dev/null
        docker_mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
        print_success "User created and granted access to $db_name"
    else
        print_success "User created"
    fi

    return 0
}

# Drop database user
db_drop_user() {
    local username=$1

    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    print_info "Dropping database user: $username"
    docker_mysql -e "DROP USER IF EXISTS '$username'@'%';" 2>/dev/null
    docker_mysql -e "FLUSH PRIVILEGES;" 2>/dev/null

    print_success "User dropped"
    return 0
}

# Check database connection
db_check_connection() {
    if docker_available && container_running "$MARIADB_CONTAINER"; then
        if docker_mysql -e "SELECT 1;" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Get database version
db_version() {
    docker_mysql -e "SELECT VERSION();" 2>/dev/null | tail -n 1
}

# Export all functions
export -f get_db_name db_exists db_create db_drop db_size
export -f db_list_wordpress db_list_all db_table_count
export -f db_export db_import db_optimize db_repair db_search_replace
export -f db_show_grants db_create_user db_drop_user
export -f db_check_connection db_version
