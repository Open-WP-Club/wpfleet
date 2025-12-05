#!/bin/bash

# WPFleet Docker Installation Script
# Installs Docker Engine, Docker Compose, and required dependencies

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# Check if running as root
check_root() {
    if ! is_root; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        
        case $ID in
            ubuntu)
                OS_TYPE="ubuntu"
                ;;
            debian)
                OS_TYPE="debian"
                ;;
            centos|rhel|rocky|almalinux)
                OS_TYPE="rhel"
                ;;
            fedora)
                OS_TYPE="fedora"
                ;;
            *)
                print_error "Unsupported operating system: $ID"
                exit 1
                ;;
        esac
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    print_info "Detected OS: $OS ($VER)"
}

# Check system requirements
check_requirements() {
    print_header "Checking System Requirements"
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
        print_error "Unsupported architecture: $ARCH"
        exit 1
    fi
    print_success "Architecture: $ARCH"
    
    # Check memory (minimum 2GB recommended)
    MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEMORY_GB=$((MEMORY_KB / 1024 / 1024))
    
    if [ $MEMORY_GB -lt 2 ]; then
        print_warning "Low memory detected: ${MEMORY_GB}GB (2GB+ recommended for WPFleet)"
    else
        print_success "Memory: ${MEMORY_GB}GB"
    fi
    
    # Check disk space (minimum 20GB recommended)
    DISK_SPACE=$(df / | tail -1 | awk '{print $4}')
    DISK_SPACE_GB=$((DISK_SPACE / 1024 / 1024))
    
    if [ $DISK_SPACE_GB -lt 20 ]; then
        print_warning "Low disk space: ${DISK_SPACE_GB}GB available (20GB+ recommended)"
    else
        print_success "Disk space: ${DISK_SPACE_GB}GB available"
    fi
    
    # Check if ports 80 and 443 are available
    if ss -tulpn | grep -q ":80 "; then
        print_warning "Port 80 is already in use"
    fi
    
    if ss -tulpn | grep -q ":443 "; then
        print_warning "Port 443 is already in use"
    fi
}

# Install dependencies based on OS
install_dependencies() {
    print_header "Installing Dependencies"
    
    case $OS_TYPE in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg \
                lsb-release \
                software-properties-common \
                unzip \
                wget \
                htop
            ;;
        rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y \
                    curl \
                    ca-certificates \
                    gnupg \
                    lsb-release \
                    unzip \
                    wget \
                    htop
            else
                yum install -y \
                    curl \
                    ca-certificates \
                    gnupg \
                    unzip \
                    wget \
                    htop 
            fi
            ;;
    esac
    
    print_success "Dependencies installed"
}

# Remove old Docker versions
remove_old_docker() {
    print_header "Removing Old Docker Versions"
    
    case $OS_TYPE in
        ubuntu|debian)
            apt-get remove -y \
                docker \
                docker-engine \
                docker.io \
                containerd \
                runc \
                docker-compose \
                docker-compose-plugin \
                docker-ce-cli \
                docker-ce \
                containerd.io 2>/dev/null || true
            ;;
        rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y \
                    docker \
                    docker-client \
                    docker-client-latest \
                    docker-common \
                    docker-latest \
                    docker-latest-logrotate \
                    docker-logrotate \
                    docker-engine \
                    podman \
                    runc 2>/dev/null || true
            else
                yum remove -y \
                    docker \
                    docker-client \
                    docker-client-latest \
                    docker-common \
                    docker-latest \
                    docker-latest-logrotate \
                    docker-logrotate \
                    docker-engine \
                    podman \
                    runc 2>/dev/null || true
            fi
            ;;
    esac
    
    print_success "Old Docker versions removed"
}

# Install Docker Engine
install_docker() {
    print_header "Installing Docker Engine"
    
    case $OS_TYPE in
        ubuntu|debian)
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Add Docker repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel|fedora)
            # Add Docker repository
            dnf config-manager --add-repo https://download.docker.com/linux/$ID/docker-ce.repo || \
            yum-config-manager --add-repo https://download.docker.com/linux/$ID/docker-ce.repo
            
            # Install Docker Engine
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            else
                yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            fi
            ;;
    esac
    
    print_success "Docker Engine installed"
}

# Configure Docker
configure_docker() {
    print_header "Configuring Docker"
    
    # Create docker directory
    mkdir -p /etc/docker
    
    # Create daemon.json with optimized settings for WPFleet
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
    "userland-proxy": false,
    "live-restore": true,
    "no-new-privileges": true
}
EOF
    
    # Start and enable Docker
    systemctl enable docker
    systemctl start docker
    
    # Add current user to docker group if not root
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker $SUDO_USER
        print_info "Added $SUDO_USER to docker group"
        print_warning "Please log out and back in for group changes to take effect"
    fi
    
    print_success "Docker configured and started"
}

# Install Docker Compose (standalone)
install_docker_compose() {
    print_header "Installing Docker Compose"
    
    # Get latest version
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    # Download and install
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for compatibility
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "Docker Compose $COMPOSE_VERSION installed"
}

# Configure firewall
configure_firewall() {
    print_header "Configuring Firewall"
    
    case $OS_TYPE in
        ubuntu|debian)
            # Configure UFW
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            
            # Allow SSH (detect current SSH port)
            SSH_PORT=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -1)
            if [ -n "$SSH_PORT" ]; then
                ufw allow $SSH_PORT/tcp comment 'SSH'
            else
                ufw allow 22/tcp comment 'SSH'
            fi
            
            # Allow HTTP and HTTPS
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            
            # Enable UFW
            ufw --force enable
            ;;
        rhel|fedora)
            # Configure firewalld
            systemctl enable firewalld
            systemctl start firewalld
            
            # Add HTTP and HTTPS services
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --reload
            ;;
    esac
    
    print_success "Firewall configured"
}

# Optimize system for containers
optimize_system() {
    print_header "Optimizing System for Containers"
    
    # Increase file limits
    cat > /etc/security/limits.d/docker.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    # Optimize kernel parameters
    cat > /etc/sysctl.d/99-docker.conf << EOF
# Network optimizations
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_tw_buckets = 400000
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr

# Memory and swap
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.vfs_cache_pressure = 50

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
EOF
    
    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-docker.conf
    
    print_success "System optimized for containers"
}

# Configure log rotation
configure_logging() {
    print_header "Configuring Log Rotation"
    
    # Docker log rotation (already configured in daemon.json)
    
    # System log rotation for WPFleet
    cat > /etc/logrotate.d/wpfleet << EOF
/var/log/wpfleet/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        /bin/systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
    
    print_success "Log rotation configured"
}

# Verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    # Check Docker version
    if docker --version >/dev/null 2>&1; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker $DOCKER_VERSION is working"
    else
        print_error "Docker installation failed"
        exit 1
    fi
    
    # Check Docker Compose version
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_VERSION=$(docker compose version --short)
        print_success "Docker Compose $COMPOSE_VERSION is working"
    elif docker-compose --version >/dev/null 2>&1; then
        COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | tr -d ',')
        print_success "Docker Compose $COMPOSE_VERSION is working"
    else
        print_error "Docker Compose installation failed"
        exit 1
    fi
    
    # Test Docker functionality
    if docker run --rm hello-world >/dev/null 2>&1; then
        print_success "Docker is functioning correctly"
    else
        print_error "Docker test failed"
        exit 1
    fi
    
    # Check if user needs to log out
    if [ -n "$SUDO_USER" ] && ! groups $SUDO_USER | grep -q docker; then
        print_warning "User $SUDO_USER needs to log out and back in for Docker group membership to take effect"
    fi
}

# Main installation process
main() {
    cat << "EOF"
 __      __________  _____ _           _   
 \ \    / /  ____\ \/ ____| |         | |  
  \ \  / /| |__   | |  ___| | ___  ___| |_ 
   \ \/ / |  __|  | | |_  | |/ _ \/ _ \ __|
    \  /  | |     | |  _| | |  __/  __/ |_ 
     \/   |_|     |_|_|   |_|\___|\___|\__|
                                            
  Docker Installation for WPFleet
EOF
    
    echo ""
    print_info "This script will install Docker Engine and Docker Compose"
    print_info "Optimized for running WPFleet WordPress hosting platform"
    echo ""
    
    # Confirm installation
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    check_root
    detect_os
    check_requirements
    install_dependencies
    remove_old_docker
    install_docker
    configure_docker
    install_docker_compose
    configure_firewall
    optimize_system
    configure_logging
    verify_installation
    
    print_header "Installation Complete!"
    echo ""
    print_success "Docker and Docker Compose have been successfully installed!"
    echo ""
    print_info "Next steps:"
    echo "1. Clone WPFleet: git clone https://github.com/Open-WP-Club/wpfleet"
    echo "2. Configure WPFleet: cd wpfleet && cp .env.example .env"
    echo "3. Edit .env with your settings"
    echo "4. Run WPFleet: ./install.sh"
    echo ""
    
    if [ -n "$SUDO_USER" ]; then
        print_warning "Please log out and back in for Docker group membership to take effect"
        print_info "Or run: newgrp docker"
    fi
    
    print_info "System will reboot in 30 seconds to apply all changes..."
    print_info "Press Ctrl+C to cancel reboot"
    sleep 30
    reboot
}

# Run main function
main "$@"