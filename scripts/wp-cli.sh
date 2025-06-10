#!/bin/bash

# WPFleet WP-CLI Wrapper
# Execute WP-CLI commands for specific sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Check if domain is provided
if [ -z "$1" ]; then
    echo "WPFleet WP-CLI Wrapper"
    echo ""
    echo "Usage: $0 <domain> [wp-cli-command]"
    echo ""
    echo "Examples:"
    echo "  $0 example.com user list"
    echo "  $0 example.com plugin list"
    echo "  $0 example.com theme status"
    echo "  $0 example.com db export"
    echo "  $0 example.com search-replace 'http://old.com' 'https://new.com'"
    echo ""
    echo "Interactive shell:"
    echo "  $0 example.com shell"
    echo ""
    echo "Available sites:"
    docker ps --filter "label=wpfleet.site" --format "  - {{.Labels}}" | sed 's/.*wpfleet.site=//' | sort
    exit 1
fi

DOMAIN=$1
CONTAINER="wpfleet_$DOMAIN"
shift

# Check if container exists and is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    print_error "Container $CONTAINER not found or not running!"
    print_info "Available sites:"
    docker ps --filter "label=wpfleet.site" --format "  - {{.Labels}}" | sed 's/.*wpfleet.site=//' | sort
    exit 1
fi

# Special handling for shell command
if [ "$1" = "shell" ]; then
    print_info "Opening shell in $CONTAINER..."
    docker exec -it -u www-data "$CONTAINER" bash
    exit 0
fi

# Execute WP-CLI command
if [ $# -eq 0 ]; then
    # Interactive WP-CLI shell
    print_info "Opening WP-CLI shell for $DOMAIN..."
    docker exec -it -u www-data "$CONTAINER" wp shell
else
    # Execute specific WP-CLI command
    docker exec -u www-data "$CONTAINER" wp "$@"
fi