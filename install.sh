#!/bin/bash

# WPFleet Installation Script
# Automated setup for WPFleet environment

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/utils.sh"

# ASCII Art Banner
cat << "EOF"
 __      __________  _____ _           _   
 \ \    / /  ____\ \/ ____| |         | |  
  \ \  / /| |__   | |  ___| | ___  ___| |_ 
   \ \/ / |  __|  | | |_  | |/ _ \/ _ \ __|
    \  /  | |     | |  _| | |  __/  __/ |_ 
     \/   |_|     |_|_|   |_|\___|\___|\__|
                                            
  Docker-based WordPress Multi-Site Hosting
EOF

echo ""
print_info "Starting WPFleet installation..."

# Check prerequisites
print_header "Checking Prerequisites"

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed!"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi
print_success "Docker found: $(docker --version)"

# Check Docker Compose
if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed!"
    echo "Please install Docker Compose first: https://docs.docker.com/compose/install/"
    exit 1
fi
print_success "Docker Compose found"

# Check if running as root
if is_root; then
    print_warning "Running as root. It's recommended to run as a regular user with docker permissions."
fi

# Create directory structure
print_header "Creating Directory Structure"
create_directory_structure

# Setup environment file
print_header "Setting Up Environment"
setup_env_file .env.example .env

# Generate secure passwords
if grep -q "your_secure_root_password_here" .env; then
    print_info "Generating secure passwords..."
    update_env_passwords .env
fi

# Get user email
read -p "Enter admin email address: " ADMIN_EMAIL
update_env_email .env "$ADMIN_EMAIL"

# Make scripts executable
print_header "Setting Up Scripts"
make_scripts_executable scripts

# Build images
print_header "Building Docker Images"
docker compose build --no-cache
print_success "Docker images built"

# Start core services
print_header "Starting Core Services"
docker compose up -d mariadb valkey
print_info "Waiting for services to be ready..."

# Verify services
if ! wait_for_service "MariaDB" "docker exec wpfleet_mariadb mysqladmin ping -h localhost --silent" 30; then
    print_error "MariaDB failed to start"
    exit 1
fi

if ! wait_for_service "Valkey" "docker exec wpfleet_valkey valkey-cli ping | grep -q PONG" 30; then
    print_error "Valkey failed to start"
    exit 1
fi

# Final summary
print_header "Installation Complete!"
echo ""
echo "WPFleet has been successfully installed!"
echo ""
echo "Important information:"
echo "====================="
echo "Configuration file: .env"
echo "MariaDB root password: (see .env file)"
echo "WordPress admin password: (see .env file)"
echo ""
echo "Next steps:"
echo "1. Add your first site:"
echo "   ./scripts/site-manager.sh add example.com"
echo ""
echo "2. Check system health:"
echo "   ./scripts/health-check.sh"
echo ""
echo "3. View available commands:"
echo "   ./scripts/site-manager.sh"
echo "   ./scripts/wp-cli.sh"
echo "   ./scripts/db-manager.sh"
echo "   ./scripts/backup.sh"
echo ""
echo "Documentation: https://github.com/Open-WP-Club/WPFleet"
echo ""
print_success "Happy hosting with WPFleet!"