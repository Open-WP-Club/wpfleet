#!/bin/bash

# WPFleet Common Library Functions
# Shared utilities for all WPFleet scripts

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Logging functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1" >&2
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Enhanced input validation
validate_domain() {
    local domain=$1

    if [[ -z "$domain" ]]; then
        print_error "Domain cannot be empty"
        return 1
    fi

    # RFC 1123 hostname validation
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid domain format: $domain"
        return 1
    fi

    # Check length
    if [ ${#domain} -gt 253 ]; then
        print_error "Domain too long (max 253 characters): $domain"
        return 1
    fi

    return 0
}

# Sanitize domain for database name
sanitize_domain_for_db() {
    local domain=$1
    # Replace dots and dashes with underscores, ensure starts with letter
    echo "wp_$(echo "$domain" | tr '.' '_' | tr '-' '_' | sed 's/^[0-9]/d&/')"
}

# Safe sed replacement with proper escaping
safe_sed_replace() {
    local file=$1
    local search=$2
    local replace=$3
    local temp_file=$(mktemp)

    # Escape special characters for sed
    search=$(printf '%s\n' "$search" | sed 's/[[\.*^$/]/\\&/g')
    replace=$(printf '%s\n' "$replace" | sed 's/[\/&]/\\&/g')

    sed "s/$search/$replace/g" "$file" > "$temp_file"
    mv "$temp_file" "$file"
}

# File locking for concurrent operation prevention
acquire_lock() {
    local lockfile=$1
    local timeout=${2:-30}
    local count=0

    while [ $count -lt $timeout ]; do
        if mkdir "$lockfile" 2>/dev/null; then
            # Store PID in lock directory
            echo $$ > "$lockfile/pid"
            return 0
        fi

        # Check if lock is stale (process no longer exists)
        if [ -f "$lockfile/pid" ]; then
            local lock_pid=$(cat "$lockfile/pid")
            if ! kill -0 $lock_pid 2>/dev/null; then
                print_warning "Removing stale lock (PID $lock_pid no longer exists)"
                rm -rf "$lockfile"
                continue
            fi
        fi

        sleep 1
        count=$((count + 1))
    done

    print_error "Could not acquire lock after ${timeout}s"
    return 1
}

# Release lock
release_lock() {
    local lockfile=$1
    rm -rf "$lockfile"
}

# Load environment variables safely
load_env() {
    local env_file=$1
    if [ -f "$env_file" ]; then
        set -a
        source "$env_file"
        set +a
    else
        print_error "Environment file not found: $env_file"
        return 1
    fi
}

# Check if Docker is running
check_docker() {
    if ! docker ps >/dev/null 2>&1; then
        print_error "Docker is not running or not accessible!"
        print_info "Ensure Docker is installed and your user has proper permissions"
        return 1
    fi
    return 0
}

# Check if container is running
check_container() {
    local container=$1
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        print_error "Container $container is not running"
        return 1
    fi
    return 0
}

# Validate email address
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Generate secure random password
generate_password() {
    local length=${1:-32}
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-$length
}

# Retry command with exponential backoff
retry_with_backoff() {
    local max_attempts=${1:-4}
    local delay=${2:-2}
    local attempt=1
    shift 2
    local command=("$@")

    while [ $attempt -le $max_attempts ]; do
        if "${command[@]}"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            print_warning "Command failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    print_error "Command failed after $max_attempts attempts"
    return 1
}

# Check disk space
check_disk_space() {
    local path=${1:-/var/www/html}
    local threshold=${2:-90}

    local usage=$(df "$path" | tail -1 | awk '{print $5}' | sed 's/%//')

    if [ "$usage" -gt "$threshold" ]; then
        print_error "Disk usage at ${usage}% (threshold: ${threshold}%)"
        return 1
    fi
    return 0
}

# Graceful shutdown handler
setup_shutdown_handler() {
    trap 'cleanup_on_shutdown' SIGTERM SIGINT
}

cleanup_on_shutdown() {
    print_info "Received shutdown signal, cleaning up..."
    # Override this function in your script
    exit 0
}

# Export functions so they're available to sourcing scripts
export -f print_header print_ok print_warning print_error print_info print_success
export -f validate_domain sanitize_domain_for_db safe_sed_replace
export -f acquire_lock release_lock load_env check_docker check_container
export -f validate_email generate_password retry_with_backoff check_disk_space
export -f setup_shutdown_handler cleanup_on_shutdown
