#!/bin/bash

# WPFleet Notification Script
# Send notifications to Discord and Slack webhooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Notification configuration
DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
HOSTNAME="${HOSTNAME:-$(hostname)}"

# Colors for message types
COLOR_SUCCESS=3066993   # Green
COLOR_WARNING=16776960  # Yellow
COLOR_ERROR=15158332    # Red
COLOR_INFO=3447003      # Blue

# Check if notifications are enabled
is_enabled() {
    if [ -n "$DISCORD_WEBHOOK_URL" ] || [ -n "$SLACK_WEBHOOK_URL" ]; then
        return 0
    else
        return 1
    fi
}

# Send Discord notification
send_discord() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"
    local fields="$4"

    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        return 0
    fi

    # Determine color based on type
    local color=$COLOR_INFO
    case "$type" in
        success) color=$COLOR_SUCCESS ;;
        warning) color=$COLOR_WARNING ;;
        error) color=$COLOR_ERROR ;;
    esac

    # Build fields JSON
    local fields_json="[]"
    if [ -n "$fields" ]; then
        fields_json="$fields"
    fi

    # Build Discord embed payload
    local payload=$(cat <<EOF
{
  "embeds": [{
    "title": "$title",
    "description": "$message",
    "color": $color,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "footer": {
      "text": "WPFleet on $HOSTNAME"
    },
    "fields": $fields_json
  }]
}
EOF
)

    # Send to Discord
    curl -H "Content-Type: application/json" \
         -d "$payload" \
         "$DISCORD_WEBHOOK_URL" \
         --silent --output /dev/null \
         --max-time 10 || true
}

# Send Slack notification
send_slack() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"
    local fields="$4"

    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi

    # Determine color based on type
    local color="good"
    local icon=":information_source:"
    case "$type" in
        success)
            color="good"
            icon=":white_check_mark:"
            ;;
        warning)
            color="warning"
            icon=":warning:"
            ;;
        error)
            color="danger"
            icon=":x:"
            ;;
    esac

    # Build fields for Slack
    local slack_fields="[]"
    if [ -n "$fields" ]; then
        # Convert Discord fields format to Slack format
        slack_fields=$(echo "$fields" | jq '[.[] | {title: .name, value: .value, short: (.inline // false)}]' 2>/dev/null || echo "[]")
    fi

    # Build Slack payload
    local payload=$(cat <<EOF
{
  "attachments": [{
    "color": "$color",
    "title": "$icon $title",
    "text": "$message",
    "footer": "WPFleet on $HOSTNAME",
    "ts": $(date +%s),
    "fields": $slack_fields
  }]
}
EOF
)

    # Send to Slack
    curl -H "Content-Type: application/json" \
         -d "$payload" \
         "$SLACK_WEBHOOK_URL" \
         --silent --output /dev/null \
         --max-time 10 || true
}

# Main notification function
notify() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"
    local fields="${4:-[]}"

    if ! is_enabled; then
        return 0
    fi

    # Send to both platforms
    send_discord "$title" "$message" "$type" "$fields" &
    send_slack "$title" "$message" "$type" "$fields" &

    # Wait for both to complete
    wait
}

# Convenience functions for different message types
notify_success() {
    notify "$1" "$2" "success" "$3"
}

notify_warning() {
    notify "$1" "$2" "warning" "$3"
}

notify_error() {
    notify "$1" "$2" "error" "$3"
}

notify_info() {
    notify "$1" "$2" "info" "$3"
}

# Backup notification
notify_backup() {
    local status="$1"
    local sites_count="$2"
    local backup_size="$3"
    local failed_count="${4:-0}"

    local fields='[
        {"name": "Sites Backed Up", "value": "'$sites_count'", "inline": true},
        {"name": "Total Size", "value": "'$backup_size'", "inline": true},
        {"name": "Failed", "value": "'$failed_count'", "inline": true}
    ]'

    if [ "$status" = "success" ]; then
        notify_success "Backup Completed" \
            "Successfully backed up $sites_count site(s)" \
            "$fields"
    else
        notify_error "Backup Failed" \
            "Backup completed with $failed_count failure(s)" \
            "$fields"
    fi
}

# Health check notification
notify_health_issue() {
    local service="$1"
    local issue="$2"
    local severity="${3:-warning}"

    local fields='[
        {"name": "Service", "value": "'$service'", "inline": true},
        {"name": "Status", "value": "'$issue'", "inline": true}
    ]'

    if [ "$severity" = "error" ]; then
        notify_error "Service Health Issue" \
            "$service is experiencing issues: $issue" \
            "$fields"
    else
        notify_warning "Service Health Warning" \
            "$service: $issue" \
            "$fields"
    fi
}

# Disk space notification
notify_disk_space() {
    local usage_percent="$1"
    local available="$2"
    local path="$3"

    local fields='[
        {"name": "Usage", "value": "'$usage_percent'%", "inline": true},
        {"name": "Available", "value": "'$available'", "inline": true},
        {"name": "Path", "value": "'$path'", "inline": false}
    ]'

    if [ "$usage_percent" -ge 90 ]; then
        notify_error "Critical: Disk Space Low" \
            "Disk usage is critically high at $usage_percent%" \
            "$fields"
    else
        notify_warning "Warning: Disk Space" \
            "Disk usage is at $usage_percent%" \
            "$fields"
    fi
}

# SSL certificate notification
notify_ssl_expiry() {
    local domain="$1"
    local days_remaining="$2"

    local fields='[
        {"name": "Domain", "value": "'$domain'", "inline": true},
        {"name": "Days Remaining", "value": "'$days_remaining'", "inline": true}
    ]'

    if [ "$days_remaining" -le 7 ]; then
        notify_error "SSL Certificate Expiring Soon" \
            "Certificate for $domain expires in $days_remaining days" \
            "$fields"
    elif [ "$days_remaining" -le 30 ]; then
        notify_warning "SSL Certificate Expiring" \
            "Certificate for $domain expires in $days_remaining days" \
            "$fields"
    fi
}

# Site deployment notification
notify_deployment() {
    local status="$1"
    local domain="$2"
    local type="$3"
    local name="$4"

    local fields='[
        {"name": "Domain", "value": "'$domain'", "inline": true},
        {"name": "Type", "value": "'$type'", "inline": true},
        {"name": "Name", "value": "'$name'", "inline": true}
    ]'

    if [ "$status" = "success" ]; then
        notify_success "Deployment Successful" \
            "Successfully deployed $type '$name' to $domain" \
            "$fields"
    else
        notify_error "Deployment Failed" \
            "Failed to deploy $type '$name' to $domain" \
            "$fields"
    fi
}

# Site quota notification
notify_quota_exceeded() {
    local domain="$1"
    local usage="$2"
    local limit="$3"

    local fields='[
        {"name": "Domain", "value": "'$domain'", "inline": true},
        {"name": "Usage", "value": "'$usage'", "inline": true},
        {"name": "Limit", "value": "'$limit'", "inline": true}
    ]'

    notify_warning "Site Quota Exceeded" \
        "Site $domain has exceeded its disk quota" \
        "$fields"
}

# Command-line interface
case "${1:-}" in
    success)
        notify_success "${2:-Test}" "${3:-This is a test success message}"
        ;;
    warning)
        notify_warning "${2:-Test}" "${3:-This is a test warning message}"
        ;;
    error)
        notify_error "${2:-Test}" "${3:-This is a test error message}"
        ;;
    info)
        notify_info "${2:-Test}" "${3:-This is a test info message}"
        ;;
    test)
        if ! is_enabled; then
            echo "Notifications are not configured!"
            echo "Please set DISCORD_WEBHOOK_URL and/or SLACK_WEBHOOK_URL in .env"
            exit 1
        fi

        echo "Sending test notifications..."
        notify_success "Test Notification" "This is a test success message from WPFleet"
        echo "✓ Test notifications sent!"
        echo ""
        echo "Check your Discord/Slack channels for the test message."
        ;;
    backup)
        notify_backup "$2" "$3" "$4" "$5"
        ;;
    health)
        notify_health_issue "$2" "$3" "$4"
        ;;
    disk)
        notify_disk_space "$2" "$3" "$4"
        ;;
    ssl)
        notify_ssl_expiry "$2" "$3"
        ;;
    deployment)
        notify_deployment "$2" "$3" "$4" "$5"
        ;;
    quota)
        notify_quota_exceeded "$2" "$3" "$4"
        ;;
    *)
        echo "WPFleet Notification Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  test                              - Send test notification"
        echo "  success <title> <message>         - Send success notification"
        echo "  warning <title> <message>         - Send warning notification"
        echo "  error <title> <message>           - Send error notification"
        echo "  info <title> <message>            - Send info notification"
        echo "  backup <status> <count> <size> [failed] - Send backup notification"
        echo "  health <service> <issue> [severity] - Send health check notification"
        echo "  disk <usage%> <available> <path>  - Send disk space notification"
        echo "  ssl <domain> <days>               - Send SSL expiry notification"
        echo "  deployment <status> <domain> <type> <name> - Send deployment notification"
        echo "  quota <domain> <usage> <limit>    - Send quota exceeded notification"
        echo ""
        echo "Configuration (in .env):"
        echo "  DISCORD_WEBHOOK_URL - Discord webhook URL"
        echo "  SLACK_WEBHOOK_URL   - Slack webhook URL"
        echo ""
        echo "Examples:"
        echo "  $0 test"
        echo "  $0 success 'Deployment' 'Site deployed successfully'"
        echo "  $0 backup success 5 '2.5GB' 0"
        echo "  $0 disk 85 '50GB' '/var/www'"
        exit 1
        ;;
esac
