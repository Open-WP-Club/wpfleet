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
    local temp_file
    temp_file=$(mktemp)
    register_cleanup "file" "$temp_file"

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

# Cleanup registry for graceful shutdown
CLEANUP_ITEMS=()

# Register an item for cleanup on exit/signal
# Usage: register_cleanup "file" "/tmp/myfile.tmp"
#        register_cleanup "dir" "/tmp/mydir"
#        register_cleanup "lock" "/tmp/mylock"
#        register_cleanup "cmd" "some_cleanup_command arg1 arg2"
register_cleanup() {
    local type=$1
    local target=$2
    CLEANUP_ITEMS+=("${type}:${target}")
}

# Graceful shutdown handler
setup_shutdown_handler() {
    trap 'cleanup_on_shutdown' EXIT SIGTERM SIGINT SIGHUP
}

cleanup_on_shutdown() {
    local exit_code=$?

    # Prevent re-entrancy
    trap '' EXIT SIGTERM SIGINT SIGHUP

    if [ ${#CLEANUP_ITEMS[@]} -gt 0 ]; then
        print_info "Cleaning up ${#CLEANUP_ITEMS[@]} registered item(s)..."

        # Iterate in reverse order (LIFO)
        for (( i=${#CLEANUP_ITEMS[@]}-1; i>=0; i-- )); do
            local entry="${CLEANUP_ITEMS[$i]}"
            local type="${entry%%:*}"
            local target="${entry#*:}"

            case "$type" in
                file)
                    [ -f "$target" ] && rm -f "$target" 2>/dev/null
                    ;;
                dir)
                    [ -d "$target" ] && rm -rf "$target" 2>/dev/null
                    ;;
                lock)
                    [ -d "$target" ] && rm -rf "$target" 2>/dev/null
                    ;;
                cmd)
                    eval "$target" 2>/dev/null
                    ;;
            esac
        done
    fi

    # Call custom cleanup if defined by sourcing script
    if declare -f custom_cleanup >/dev/null 2>&1; then
        custom_cleanup
    fi

    exit "$exit_code"
}

# Get script directory and project root
# Returns: "script_dir|project_root"
get_script_paths() {
    local caller_script="${BASH_SOURCE[1]}"
    local script_dir="$(cd "$(dirname "$caller_script")" && pwd)"
    local project_root="$(dirname "$(dirname "$script_dir")")"
    echo "$script_dir|$project_root"
}

# Format bytes to human readable format
format_bytes() {
    local bytes=$1
    local precision=${2:-2}

    if [ -z "$bytes" ] || [ "$bytes" -eq 0 ]; then
        echo "0B"
        return
    fi

    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local size=$bytes

    while [ $(echo "$size >= 1024" | bc) -eq 1 ] && [ $unit_index -lt 5 ]; do
        size=$(echo "scale=$precision; $size / 1024" | bc)
        unit_index=$((unit_index + 1))
    done

    printf "%.${precision}f%s" "$size" "${units[$unit_index]}"
}

# Format KB to human readable format (common in df output)
format_kb() {
    local kb=$1
    local bytes=$((kb * 1024))
    format_bytes "$bytes"
}

# Format seconds to human readable duration
format_duration() {
    local seconds=$1

    if [ -z "$seconds" ]; then
        echo "0s"
        return
    fi

    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    local result=""
    [ $days -gt 0 ] && result="${days}d "
    [ $hours -gt 0 ] && result="${result}${hours}h "
    [ $minutes -gt 0 ] && result="${result}${minutes}m "
    [ $secs -gt 0 ] || [ -z "$result" ] && result="${result}${secs}s"

    echo "$result" | xargs
}

# Get timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get timestamp for filenames (no special characters)
get_timestamp_filename() {
    date +"%Y%m%d_%H%M%S"
}

# Log message to file with timestamp
log_to_file() {
    local log_file=$1
    local message=$2
    local log_dir=$(dirname "$log_file")

    # Create log directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi

    echo "[$(get_timestamp)] $message" >> "$log_file"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Get current user
get_current_user() {
    whoami
}

# Confirm action (ask yes/no)
confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-n}"

    local yn
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" yn
    yn=${yn:-$default}

    case "${yn,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

# Wait for condition with timeout
wait_for() {
    local timeout=$1
    local interval=${2:-1}
    shift 2
    local command=("$@")

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if "${command[@]}"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Export functions so they're available to sourcing scripts
export -f print_header print_ok print_warning print_error print_info print_success
export -f validate_domain sanitize_domain_for_db safe_sed_replace
export -f acquire_lock release_lock load_env check_docker check_container
export -f validate_email generate_password retry_with_backoff check_disk_space
export -f register_cleanup setup_shutdown_handler cleanup_on_shutdown
export -f get_script_paths format_bytes format_kb format_duration
export -f get_timestamp get_timestamp_filename log_to_file
export -f command_exists is_root get_current_user confirm wait_for
