#!/bin/bash

# WPFleet Installation Script
# Automated setup for WPFleet environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

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
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. It's recommended to run as a regular user with docker permissions."
fi

# Create directory structure
print_header "Creating Directory Structure"
directories=(
    "data/wordpress"
    "data/mariadb"
    "data/redis"
    "data/logs"
    "config/sites"
    "config/fail2ban/filter.d"
    "backups/databases"
    "backups/files"
)

for dir in "${directories[@]}"; do
    mkdir -p "$dir"
    print_success "Created: $dir"
done

# Create .gitkeep files
touch data/wordpress/.gitkeep
touch data/mariadb/.gitkeep
touch data/redis/.gitkeep
touch data/logs/.gitkeep
touch config/sites/.gitkeep

# Setup environment file
print_header "Setting Up Environment"

if [ -f .env ]; then
    print_info ".env file already exists"
    read -p "Do you want to regenerate it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Keeping existing .env file"
    else
        mv .env .env.backup
        print_info "Backed up existing .env to .env.backup"
        cp .env.example .env
    fi
else
    cp .env.example .env
    print_success "Created .env file from template"
fi

# Generate secure passwords
if grep -q "your_secure_root_password_here" .env; then
    print_info "Generating secure passwords..."
    
    MYSQL_ROOT_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    MYSQL_USER_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    WP_ADMIN_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    
    # Update .env file based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/your_secure_root_password_here/$MYSQL_ROOT_PASS/g" .env
        sed -i '' "s/your_secure_password_here/$MYSQL_USER_PASS/g" .env
        sed -i '' "s/generate_secure_password_here/$WP_ADMIN_PASS/g" .env
    else
        # Linux
        sed -i "s/your_secure_root_password_here/$MYSQL_ROOT_PASS/g" .env
        sed -i "s/your_secure_password_here/$MYSQL_USER_PASS/g" .env
        sed -i "s/generate_secure_password_here/$WP_ADMIN_PASS/g" .env
    fi
    
    print_success "Generated secure passwords"
fi

# Get user email
read -p "Enter admin email address: " ADMIN_EMAIL
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/admin@yourdomain.com/$ADMIN_EMAIL/g" .env
    sed -i '' "s/ssl@yourdomain.com/$ADMIN_EMAIL/g" .env
else
    sed -i "s/admin@yourdomain.com/$ADMIN_EMAIL/g" .env
    sed -i "s/ssl@yourdomain.com/$ADMIN_EMAIL/g" .env
fi

# Make scripts executable
print_header "Setting Up Scripts"
chmod +x scripts/*.sh
chmod +x docker/mariadb/init/*.sh 2>/dev/null || true
print_success "Scripts are now executable"

# Build images
print_header "Building Docker Images"
docker compose build --no-cache
print_success "Docker images built"

# Start core services
print_header "Starting Core Services"
docker compose up -d mariadb redis
print_info "Waiting for services to be ready..."
sleep 10

# Verify services
if docker exec wpfleet_mariadb mysqladmin ping -h localhost --silent 2>/dev/null; then
    print_success "MariaDB is ready"
else
    print_error "MariaDB failed to start"
    exit 1
fi

if docker exec wpfleet_redis redis-cli ping 2>/dev/null | grep -q PONG; then
    print_success "Redis is ready"
else
    print_error "Redis failed to start"
    exit 1
fi

# Create Fail2ban configuration
print_header "Creating Security Configuration"
cat > config/fail2ban/jail.local << 'EOF'
[wordpress]
enabled = true
filter = wordpress
logpath = /path/to/wpfleet/data/logs/*/access.log
maxretry = 5
findtime = 300
bantime = 86400
EOF

cat > config/fail2ban/filter.d/wordpress.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST .*/(wp-login\.php|xmlrpc\.php).* (401|403)
ignoreregex =
EOF

print_success "Security configuration created"

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