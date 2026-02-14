#!/bin/bash

# WPFleet Utilities - Single Import File
# Source this file to get access to all WPFleet library functions

# Get the library directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all library files in order
source "$LIB_DIR/common.sh"
source "$LIB_DIR/system.sh"
source "$LIB_DIR/docker.sh"
source "$LIB_DIR/database.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/notifications.sh"
source "$LIB_DIR/install.sh"
source "$LIB_DIR/logger.sh"

# Enable graceful shutdown handlers for all scripts
setup_shutdown_handler

# Set PROJECT_ROOT if not already set
if [[ -z "$PROJECT_ROOT" ]]; then
    export PROJECT_ROOT="$(dirname "$(dirname "$LIB_DIR")")"
fi

# Set SCRIPT_DIR if not already set (for the calling script)
if [[ -z "$SCRIPT_DIR" ]]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
fi
