#!/bin/bash

# WPFleet Validation Library
# Extended validation functions for sites, paths, and configurations

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get project root
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

# Check if a site directory exists
site_exists() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        print_error "Domain required"
        return 1
    fi

    if [ -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
        return 0
    fi
    return 1
}

# Check if WordPress is installed in a site directory
wordpress_installed() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        print_error "Domain required"
        return 1
    fi

    if [ -f "$PROJECT_ROOT/data/wordpress/$domain/wp-config.php" ]; then
        return 0
    fi
    return 1
}

# Check if site is accessible (wp-config exists and readable)
site_accessible() {
    local domain=$1
    if ! site_exists "$domain"; then
        return 1
    fi

    if ! wordpress_installed "$domain"; then
        return 1
    fi

    # Check if wp-config.php is readable
    if [ -r "$PROJECT_ROOT/data/wordpress/$domain/wp-config.php" ]; then
        return 0
    fi

    return 1
}

# Get list of all sites
get_all_sites() {
    local sites_dir="$PROJECT_ROOT/data/wordpress"

    if [ ! -d "$sites_dir" ]; then
        return 0
    fi

    find "$sites_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
}

# Get list of all sites with WordPress installed
get_wordpress_sites() {
    local sites_dir="$PROJECT_ROOT/data/wordpress"

    if [ ! -d "$sites_dir" ]; then
        return 0
    fi

    for domain in $(get_all_sites); do
        if wordpress_installed "$domain"; then
            echo "$domain"
        fi
    done
}

# Count total number of sites
count_sites() {
    get_all_sites | wc -l
}

# Count WordPress installed sites
count_wordpress_sites() {
    get_wordpress_sites | wc -l
}

# Validate path exists and is directory
validate_directory() {
    local path=$1
    if [[ -z "$path" ]]; then
        print_error "Path required"
        return 1
    fi

    if [ ! -d "$path" ]; then
        print_error "Directory does not exist: $path"
        return 1
    fi

    return 0
}

# Validate path exists and is file
validate_file() {
    local path=$1
    if [[ -z "$path" ]]; then
        print_error "Path required"
        return 1
    fi

    if [ ! -f "$path" ]; then
        print_error "File does not exist: $path"
        return 1
    fi

    return 0
}

# Validate path is writable
validate_writable() {
    local path=$1
    if [[ -z "$path" ]]; then
        print_error "Path required"
        return 1
    fi

    if [ ! -w "$path" ]; then
        print_error "Path is not writable: $path"
        return 1
    fi

    return 0
}

# Validate path is readable
validate_readable() {
    local path=$1
    if [[ -z "$path" ]]; then
        print_error "Path required"
        return 1
    fi

    if [ ! -r "$path" ]; then
        print_error "Path is not readable: $path"
        return 1
    fi

    return 0
}

# Check if path has enough free space
validate_free_space() {
    local path=${1:-/}
    local required_mb=${2:-100}

    local available=$(df "$path" | tail -1 | awk '{print $4}')
    local available_mb=$((available / 1024))

    if [ $available_mb -lt $required_mb ]; then
        print_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        return 1
    fi

    return 0
}

# Validate URL format
validate_url() {
    local url=$1
    if [[ -z "$url" ]]; then
        print_error "URL required"
        return 1
    fi

    if [[ ! "$url" =~ ^https?:// ]]; then
        print_error "Invalid URL format (must start with http:// or https://): $url"
        return 1
    fi

    return 0
}

# Validate port number
validate_port() {
    local port=$1
    if [[ -z "$port" ]]; then
        print_error "Port number required"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "Port must be a number: $port"
        return 1
    fi

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_error "Port must be between 1 and 65535: $port"
        return 1
    fi

    return 0
}

# Validate IP address (basic IPv4)
validate_ip() {
    local ip=$1
    if [[ -z "$ip" ]]; then
        print_error "IP address required"
        return 1
    fi

    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP address format: $ip"
        return 1
    fi

    # Validate each octet
    local IFS='.'
    local octets=($ip)
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            print_error "Invalid IP address (octet > 255): $ip"
            return 1
        fi
    done

    return 0
}

# Validate username (alphanumeric, underscore, dash)
validate_username() {
    local username=$1
    if [[ -z "$username" ]]; then
        print_error "Username required"
        return 1
    fi

    if [[ ! "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid username format (use only letters, numbers, underscore, dash): $username"
        return 1
    fi

    if [ ${#username} -lt 3 ]; then
        print_error "Username too short (minimum 3 characters): $username"
        return 1
    fi

    if [ ${#username} -gt 32 ]; then
        print_error "Username too long (maximum 32 characters): $username"
        return 1
    fi

    return 0
}

# Validate password strength (basic)
validate_password() {
    local password=$1
    local min_length=${2:-8}

    if [[ -z "$password" ]]; then
        print_error "Password required"
        return 1
    fi

    if [ ${#password} -lt $min_length ]; then
        print_error "Password too short (minimum $min_length characters)"
        return 1
    fi

    return 0
}

# Validate number (integer)
validate_integer() {
    local value=$1
    if [[ -z "$value" ]]; then
        print_error "Value required"
        return 1
    fi

    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        print_error "Value must be an integer: $value"
        return 1
    fi

    return 0
}

# Validate positive number
validate_positive_integer() {
    local value=$1
    if ! validate_integer "$value"; then
        return 1
    fi

    if [ "$value" -lt 0 ]; then
        print_error "Value must be positive: $value"
        return 1
    fi

    return 0
}

# Validate value is in range
validate_range() {
    local value=$1
    local min=$2
    local max=$3

    if ! validate_integer "$value"; then
        return 1
    fi

    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        print_error "Value out of range (must be between $min and $max): $value"
        return 1
    fi

    return 0
}

# Validate boolean value
validate_boolean() {
    local value=$1
    if [[ -z "$value" ]]; then
        print_error "Boolean value required"
        return 1
    fi

    case "${value,,}" in
        true|false|yes|no|1|0|on|off)
            return 0
            ;;
        *)
            print_error "Invalid boolean value (use true/false, yes/no, 1/0, on/off): $value"
            return 1
            ;;
    esac
}

# Convert string to boolean
to_boolean() {
    local value=$1
    case "${value,,}" in
        true|yes|1|on)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Validate required environment variable is set
validate_env_var() {
    local var_name=$1
    local var_value="${!var_name}"

    if [[ -z "$var_value" ]]; then
        print_error "Required environment variable not set: $var_name"
        return 1
    fi

    return 0
}

# Validate multiple required environment variables
validate_env_vars() {
    local all_valid=true

    for var_name in "$@"; do
        if ! validate_env_var "$var_name"; then
            all_valid=false
        fi
    done

    if [ "$all_valid" = false ]; then
        return 1
    fi

    return 0
}

# Export all functions
export -f site_exists wordpress_installed site_accessible
export -f get_all_sites get_wordpress_sites count_sites count_wordpress_sites
export -f validate_directory validate_file validate_writable validate_readable
export -f validate_free_space validate_url validate_port validate_ip
export -f validate_username validate_password
export -f validate_integer validate_positive_integer validate_range
export -f validate_boolean to_boolean
export -f validate_env_var validate_env_vars
