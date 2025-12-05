#!/bin/bash

# WPFleet Notifications Library
# Wrapper functions for sending notifications via notify.sh

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Get the notify.sh script path
NOTIFY_SCRIPT="$(dirname "$SCRIPT_DIR")/notify.sh"

# Check if notifications are configured
notifications_enabled() {
    if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]] || [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        return 0
    fi
    return 1
}

# Check if notify.sh exists and is executable
notify_script_available() {
    if [ -x "$NOTIFY_SCRIPT" ]; then
        return 0
    elif [ -f "$NOTIFY_SCRIPT" ]; then
        chmod +x "$NOTIFY_SCRIPT" 2>/dev/null
        return 0
    fi
    return 1
}

# Send notification (wrapper around notify.sh)
send_notification() {
    local type=$1
    shift

    if ! notifications_enabled; then
        return 0
    fi

    if ! notify_script_available; then
        print_warning "Notification script not available"
        return 1
    fi

    "$NOTIFY_SCRIPT" "$type" "$@" 2>/dev/null || true
}

# Send success notification
send_success() {
    local title=$1
    local message=$2
    send_notification "success" "$title" "$message"
}

# Send warning notification
send_warning() {
    local title=$1
    local message=$2
    send_notification "warning" "$title" "$message"
}

# Send error notification
send_error() {
    local title=$1
    local message=$2
    send_notification "error" "$title" "$message"
}

# Send info notification
send_info() {
    local title=$1
    local message=$2
    send_notification "info" "$title" "$message"
}

# Send backup notification
send_backup_notification() {
    local status=$1           # success or error
    local sites_count=$2      # number of sites backed up
    local backup_size=$3      # total backup size (e.g., "2.5GB")
    local failed_count=${4:-0}  # number of failed backups

    send_notification "backup" "$status" "$sites_count" "$backup_size" "$failed_count"
}

# Send health check notification
send_health_notification() {
    local service=$1        # service name (e.g., "MariaDB", "FrankenPHP")
    local issue=$2          # issue description
    local severity=${3:-warning}  # warning or error

    send_notification "health" "$service" "$issue" "$severity"
}

# Send disk space notification
send_disk_notification() {
    local usage_percent=$1  # disk usage percentage (e.g., 85)
    local available=$2      # available space (e.g., "50GB")
    local path=$3           # path being monitored

    send_notification "disk" "$usage_percent" "$available" "$path"
}

# Send SSL certificate expiry notification
send_ssl_notification() {
    local domain=$1         # domain name
    local days_remaining=$2 # days until expiry

    send_notification "ssl" "$domain" "$days_remaining"
}

# Send deployment notification
send_deployment_notification() {
    local status=$1    # success or error
    local domain=$2    # domain name
    local type=$3      # deployment type (e.g., "plugin", "theme")
    local name=$4      # name of plugin/theme/etc

    send_notification "deployment" "$status" "$domain" "$type" "$name"
}

# Send quota exceeded notification
send_quota_notification() {
    local domain=$1    # domain name
    local usage=$2     # current usage (e.g., "5.2GB")
    local limit=$3     # quota limit (e.g., "5GB")

    send_notification "quota" "$domain" "$usage" "$limit"
}

# Send test notification
send_test_notification() {
    send_notification "test"
}

# Notify on script completion (success)
notify_script_success() {
    local script_name=${1:-$(basename "$0")}
    local message=${2:-"Script completed successfully"}

    send_success "$script_name" "$message"
}

# Notify on script failure (error)
notify_script_failure() {
    local script_name=${1:-$(basename "$0")}
    local message=${2:-"Script failed"}
    local error_details=${3:-""}

    if [[ -n "$error_details" ]]; then
        message="$message: $error_details"
    fi

    send_error "$script_name" "$message"
}

# Notify on script start (info)
notify_script_start() {
    local script_name=${1:-$(basename "$0")}
    local message=${2:-"Script started"}

    send_info "$script_name" "$message"
}

# Export all functions
export -f notifications_enabled notify_script_available send_notification
export -f send_success send_warning send_error send_info
export -f send_backup_notification send_health_notification send_disk_notification
export -f send_ssl_notification send_deployment_notification send_quota_notification
export -f send_test_notification
export -f notify_script_success notify_script_failure notify_script_start
