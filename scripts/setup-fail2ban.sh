#!/bin/bash

# WPFleet Fail2ban Setup Script
# Configures Fail2ban for WordPress protection

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common library
source "$SCRIPT_DIR/lib/common.sh"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_header "WPFleet Fail2ban Setup"

# Check if Fail2ban is installed
if ! command -v fail2ban-server >/dev/null 2>&1; then
    print_info "Installing Fail2ban..."
    apt-get update
    apt-get install -y fail2ban
fi

# Copy filter configuration
print_info "Installing WPFleet Fail2ban filter..."
cp "$PROJECT_ROOT/docker/fail2ban/filter.d/wpfleet.conf" /etc/fail2ban/filter.d/

# Copy jail configuration
print_info "Installing WPFleet Fail2ban jail..."
if [ -f /etc/fail2ban/jail.local ]; then
    print_warning "jail.local exists, backing up..."
    cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup
fi

# Merge with existing jail.local or create new
cat "$PROJECT_ROOT/docker/fail2ban/jail.local" >> /etc/fail2ban/jail.local

# Update log paths
print_info "Updating log paths..."
sed -i "s|/var/log/frankenphp|$PROJECT_ROOT/data/logs/frankenphp|g" /etc/fail2ban/jail.local

# Restart Fail2ban
print_info "Restarting Fail2ban..."
systemctl restart fail2ban
systemctl enable fail2ban

# Show status
print_success "Fail2ban installed and configured!"
echo ""
print_info "Active jails:"
fail2ban-client status

echo ""
print_info "Monitor Fail2ban:"
echo "  fail2ban-client status wpfleet-login"
echo "  fail2ban-client status wpfleet-xmlrpc"
echo "  tail -f /var/log/fail2ban.log"
