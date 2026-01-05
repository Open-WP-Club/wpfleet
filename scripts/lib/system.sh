#!/bin/bash

# WPFleet System Library Functions
# System-level utilities for OS detection, requirements checking, etc.

# Detect operating system
# Sets: OS_TYPE, OS, VER variables
# Returns: 0 on success, 1 on unsupported OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        export OS=$NAME
        export VER=$VERSION_ID

        case $ID in
            ubuntu)
                export OS_TYPE="ubuntu"
                ;;
            debian)
                export OS_TYPE="debian"
                ;;
            centos|rhel|rocky|almalinux)
                export OS_TYPE="rhel"
                ;;
            fedora)
                export OS_TYPE="fedora"
                ;;
            *)
                print_error "Unsupported operating system: $ID"
                return 1
                ;;
        esac
    else
        print_error "Cannot detect operating system"
        return 1
    fi

    print_info "Detected OS: $OS ($VER)"
    return 0
}

# Check system requirements for Docker hosting
# Validates: architecture, memory, disk space, port availability
check_system_requirements() {
    print_header "Checking System Requirements"

    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" && "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
        print_error "Unsupported architecture: $arch"
        return 1
    fi
    print_success "Architecture: $arch"

    # Check memory (minimum 2GB recommended)
    local memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local memory_gb=$((memory_kb / 1024 / 1024))

    if [ $memory_gb -lt 2 ]; then
        print_warning "Low memory detected: ${memory_gb}GB (2GB+ recommended for WPFleet)"
    else
        print_success "Memory: ${memory_gb}GB"
    fi

    # Check disk space (minimum 20GB recommended)
    local disk_space=$(df / | tail -1 | awk '{print $4}')
    local disk_space_gb=$((disk_space / 1024 / 1024))

    if [ $disk_space_gb -lt 20 ]; then
        print_warning "Low disk space: ${disk_space_gb}GB available (20GB+ recommended)"
    else
        print_success "Disk space: ${disk_space_gb}GB available"
    fi

    # Check if ports 80 and 443 are available
    if command_exists ss; then
        if ss -tulpn | grep -q ":80 "; then
            print_warning "Port 80 is already in use"
        fi

        if ss -tulpn | grep -q ":443 "; then
            print_warning "Port 443 is already in use"
        fi
    fi

    return 0
}

# Get package manager command for current OS
# Returns: apt-get, dnf, or yum
get_package_manager() {
    if command_exists apt-get; then
        echo "apt-get"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists yum; then
        echo "yum"
    else
        print_error "No supported package manager found"
        return 1
    fi
}

# Check if running in a container
is_container() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Get system uptime in seconds
get_uptime_seconds() {
    if [ -f /proc/uptime ]; then
        awk '{print int($1)}' /proc/uptime
    else
        echo "0"
    fi
}

# Get load average
get_load_average() {
    if [ -f /proc/loadavg ]; then
        awk '{print $1, $2, $3}' /proc/loadavg
    else
        echo "0 0 0"
    fi
}

# Export functions
export -f detect_os check_system_requirements get_package_manager
export -f is_container get_uptime_seconds get_load_average
