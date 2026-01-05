#!/bin/bash

# WPFleet Enhanced Logger Library
# Provides both human-readable and structured JSON logging

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Enable structured logging (set to "true" for JSON output)
STRUCTURED_LOGGING="${STRUCTURED_LOGGING:-false}"
LOG_FILE="${LOG_FILE:-}"

# Log levels
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Get numeric log level
get_log_level_num() {
    echo "${LOG_LEVELS[${1:-INFO}]}"
}

# Structured JSON logger
log_json() {
    local level=$1
    local message=$2
    shift 2
    local context="$@"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname=$(hostname)
    local script_name=$(basename "$0")
    local pid=$$

    # Build JSON context
    local json_context=""
    if [ -n "$context" ]; then
        # Parse context as key=value pairs
        json_context=","
        for item in $context; do
            if [[ "$item" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                json_context="${json_context}\"${key}\":\"${value}\","
            fi
        done
        json_context="${json_context%,}"  # Remove trailing comma
    fi

    # Build JSON log entry
    local json_log="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\",\"script\":\"$script_name\",\"hostname\":\"$hostname\",\"pid\":$pid${json_context}}"

    # Output to stdout and optionally to file
    echo "$json_log"
    if [ -n "$LOG_FILE" ]; then
        echo "$json_log" >> "$LOG_FILE"
    fi
}

# Human-readable logger
log_human() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    case "$level" in
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC}  [$timestamp] $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC}  [$timestamp] $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message" >&2
            ;;
    esac

    if [ -n "$LOG_FILE" ]; then
        echo "[$level] [$timestamp] $message" >> "$LOG_FILE"
    fi
}

# Main logging function
wpfleet_log() {
    local level=$1
    local message=$2
    shift 2
    local context="$@"

    # Check if we should log at this level
    local current_level_num=$(get_log_level_num "$LOG_LEVEL")
    local message_level_num=$(get_log_level_num "$level")

    if [ "$message_level_num" -lt "$current_level_num" ]; then
        return 0
    fi

    if [ "$STRUCTURED_LOGGING" = "true" ]; then
        log_json "$level" "$message" $context
    else
        log_human "$level" "$message"
    fi
}

# Convenience functions
log_debug() {
    wpfleet_log "DEBUG" "$@"
}

log_info() {
    wpfleet_log "INFO" "$@"
}

log_warn() {
    wpfleet_log "WARN" "$@"
}

log_error() {
    wpfleet_log "ERROR" "$@"
}

# Log with operation timing
log_operation() {
    local operation=$1
    local start_time=$2
    local end_time=$3
    local status=$4
    shift 4
    local context="$@"

    local duration=$((end_time - start_time))

    if [ "$status" = "success" ]; then
        wpfleet_log "INFO" "Operation completed: $operation" \
            "operation=$operation" \
            "duration_seconds=$duration" \
            "status=$status" \
            $context
    else
        wpfleet_log "ERROR" "Operation failed: $operation" \
            "operation=$operation" \
            "duration_seconds=$duration" \
            "status=$status" \
            $context
    fi
}

# Execute command with logging
execute_with_logging() {
    local operation=$1
    shift
    local command="$@"

    log_info "Starting: $operation"
    local start_time=$(date +%s)

    if eval "$command"; then
        local end_time=$(date +%s)
        log_operation "$operation" "$start_time" "$end_time" "success"
        return 0
    else
        local exit_code=$?
        local end_time=$(date +%s)
        log_operation "$operation" "$start_time" "$end_time" "failed" "exit_code=$exit_code"
        return $exit_code
    fi
}

# Log Docker container metrics
log_container_metrics() {
    local container_name=$1

    if ! docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_warn "Container not running: $container_name"
        return 1
    fi

    # Get container stats
    local stats=$(docker stats "$container_name" --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.NetIO}}")
    IFS=',' read -r cpu_perc mem_usage net_io <<< "$stats"

    log_info "Container metrics" \
        "container=$container_name" \
        "cpu=$cpu_perc" \
        "memory=$mem_usage" \
        "network=$net_io"
}

# Log disk usage
log_disk_usage() {
    local path=$1

    if [ ! -d "$path" ]; then
        log_warn "Path does not exist: $path"
        return 1
    fi

    local usage=$(df -h "$path" | tail -1 | awk '{print $5}' | sed 's/%//')
    local available=$(df -h "$path" | tail -1 | awk '{print $4}')

    if [ "$usage" -gt 90 ]; then
        log_warn "Disk usage critical" "path=$path" "usage_percent=$usage" "available=$available"
    elif [ "$usage" -gt 80 ]; then
        log_warn "Disk usage high" "path=$path" "usage_percent=$usage" "available=$available"
    else
        log_info "Disk usage normal" "path=$path" "usage_percent=$usage" "available=$available"
    fi
}

# Log database metrics
log_database_metrics() {
    local db_name=$1

    if ! check_container "wpfleet_mariadb"; then
        log_error "Database container not running"
        return 1
    fi

    # Get database size
    local db_size=$(docker exec wpfleet_mariadb mysql -N -e \
        "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) \
         FROM information_schema.tables \
         WHERE table_schema='$db_name';" 2>/dev/null)

    if [ -n "$db_size" ]; then
        log_info "Database metrics" "database=$db_name" "size_mb=$db_size"
    else
        log_warn "Could not retrieve database metrics" "database=$db_name"
    fi
}

# Export functions
export -f wpfleet_log log_debug log_info log_warn log_error
export -f log_operation execute_with_logging
export -f log_container_metrics log_disk_usage log_database_metrics
export -f log_json log_human get_log_level_num
