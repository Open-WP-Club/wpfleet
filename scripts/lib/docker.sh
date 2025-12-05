#!/bin/bash

# WPFleet Docker Library Functions
# Wrapper functions for Docker operations

# Source common library for print functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Default container names
export FRANKENPHP_CONTAINER="${FRANKENPHP_CONTAINER:-wpfleet_frankenphp}"
export MARIADB_CONTAINER="${MARIADB_CONTAINER:-wpfleet_mariadb}"
export VALKEY_CONTAINER="${VALKEY_CONTAINER:-wpfleet_valkey}"

# Check if Docker is available and running
docker_available() {
    if ! docker ps >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Check if a specific container is running
container_running() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker ps --format '{{.Names}}' | grep -q "^${container}$"
}

# Get container health status
container_health_status() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none"
}

# Get container status (running, stopped, etc.)
container_status() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not found"
}

# Get container stats (CPU, Memory)
container_stats() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "$container" 2>/dev/null
}

# Execute MySQL/MariaDB command
docker_mysql() {
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        print_error "MYSQL_ROOT_PASSWORD not set"
        return 1
    fi
    docker exec -i "$MARIADB_CONTAINER" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "$@"
}

# Execute MySQL command with query input from stdin
docker_mysql_stdin() {
    if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
        print_error "MYSQL_ROOT_PASSWORD not set"
        return 1
    fi
    docker exec -i "$MARIADB_CONTAINER" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" "$@"
}

# Execute MySQL command in specific database
docker_mysql_db() {
    local database=$1
    shift
    if [[ -z "$database" ]]; then
        print_error "Database name required"
        return 1
    fi
    docker_mysql "$database" "$@"
}

# Execute WP-CLI command
docker_wp_cli() {
    local domain=$1
    shift
    if [[ -z "$domain" ]]; then
        print_error "Domain required for WP-CLI command"
        return 1
    fi
    docker exec -u www-data "$FRANKENPHP_CONTAINER" wp --path="/var/www/html/$domain" "$@"
}

# Execute WP-CLI command with working directory
docker_wp_cli_workdir() {
    local workdir=$1
    shift
    if [[ -z "$workdir" ]]; then
        print_error "Working directory required"
        return 1
    fi
    docker exec -u www-data -w "$workdir" "$FRANKENPHP_CONTAINER" wp "$@"
}

# Execute Valkey/Redis CLI command
docker_valkey_cli() {
    local redis_cli="${VALKEY_CLI:-valkey-cli}"
    docker exec "$VALKEY_CONTAINER" $redis_cli "$@"
}

# Execute command in FrankenPHP container
docker_frankenphp_exec() {
    docker exec "$FRANKENPHP_CONTAINER" "$@"
}

# Execute command in FrankenPHP container as www-data
docker_frankenphp_exec_www() {
    docker exec -u www-data "$FRANKENPHP_CONTAINER" "$@"
}

# Execute command in MariaDB container
docker_mariadb_exec() {
    docker exec "$MARIADB_CONTAINER" "$@"
}

# Execute command in Valkey container
docker_valkey_exec() {
    docker exec "$VALKEY_CONTAINER" "$@"
}

# Get list of all running containers
docker_list_containers() {
    docker ps --format '{{.Names}}'
}

# Get list of all containers (including stopped)
docker_list_all_containers() {
    docker ps -a --format '{{.Names}}'
}

# Check container logs
docker_container_logs() {
    local container=$1
    local lines=${2:-50}
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker logs --tail "$lines" "$container"
}

# Follow container logs
docker_container_logs_follow() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker logs -f "$container"
}

# Restart container
docker_restart_container() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    print_info "Restarting container: $container"
    docker restart "$container"
}

# Stop container
docker_stop_container() {
    local container=$1
    local timeout=${2:-10}
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    print_info "Stopping container: $container"
    docker stop -t "$timeout" "$container"
}

# Start container
docker_start_container() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    print_info "Starting container: $container"
    docker start "$container"
}

# Get container IP address
docker_container_ip() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container"
}

# Check if container has specific volume mounted
docker_has_volume() {
    local container=$1
    local volume_path=$2
    if [[ -z "$container" ]] || [[ -z "$volume_path" ]]; then
        print_error "Container name and volume path required"
        return 1
    fi
    docker inspect -f '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' "$container" | grep -q "^${volume_path}$"
}

# Get disk usage of container
docker_container_size() {
    local container=$1
    if [[ -z "$container" ]]; then
        print_error "Container name required"
        return 1
    fi
    docker ps -s --filter "name=${container}" --format "{{.Size}}"
}

# Export all functions
export -f docker_available container_running container_health_status container_status
export -f container_stats docker_mysql docker_mysql_stdin docker_mysql_db
export -f docker_wp_cli docker_wp_cli_workdir docker_valkey_cli
export -f docker_frankenphp_exec docker_frankenphp_exec_www docker_mariadb_exec docker_valkey_exec
export -f docker_list_containers docker_list_all_containers
export -f docker_container_logs docker_container_logs_follow
export -f docker_restart_container docker_stop_container docker_start_container
export -f docker_container_ip docker_has_volume docker_container_size
