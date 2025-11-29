#!/bin/bash

# WPFleet SSL Certificate Monitoring Script
# Checks SSL certificate expiration and validity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Function to check SSL certificate for a domain
check_ssl_cert() {
    local domain=$1
    local warning_days=${2:-30}  # Warn if cert expires within 30 days

    # Try to get cert info from Caddy
    local cert_path="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${domain}/${domain}.crt"

    if docker exec wpfleet_frankenphp test -f "$cert_path" 2>/dev/null; then
        # Get cert expiration date
        local exp_date=$(docker exec wpfleet_frankenphp openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)

        if [ -n "$exp_date" ]; then
            local exp_epoch=$(date -d "$exp_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$exp_date" +%s 2>/dev/null)
            local now_epoch=$(date +%s)
            local days_until_expiry=$(( ($exp_epoch - $now_epoch) / 86400 ))

            if [ $days_until_expiry -lt 0 ]; then
                print_error "$domain - Certificate EXPIRED ${days_until_expiry#-} days ago"
                return 1
            elif [ $days_until_expiry -lt $warning_days ]; then
                print_warning "$domain - Certificate expires in $days_until_expiry days"
                return 1
            else
                print_ok "$domain - Certificate valid for $days_until_expiry days"
                return 0
            fi
        else
            print_warning "$domain - Could not parse certificate expiration"
            return 1
        fi
    else
        print_warning "$domain - No certificate found (might be using HTTP or cert pending)"
        return 1
    fi
}

# Function to get all sites
get_all_sites() {
    if [ -d "$PROJECT_ROOT/config/caddy/sites" ]; then
        find "$PROJECT_ROOT/config/caddy/sites" -name "*.caddy" -exec basename {} .caddy \; | sort
    fi
}

# Main execution
print_header "SSL Certificate Status Check"
echo "Date: $(date)"
echo ""

sites=$(get_all_sites)

if [ -z "$sites" ]; then
    print_warning "No sites configured"
    exit 0
fi

total=0
valid=0
warning=0
error=0

for domain in $sites; do
    total=$((total + 1))
    if check_ssl_cert "$domain" 30; then
        valid=$((valid + 1))
    else
        warning=$((warning + 1))
    fi
done

echo ""
print_header "Summary"
echo "Total sites: $total"
echo "Valid certificates: $valid"
echo "Warnings/Errors: $warning"

if [ $warning -gt 0 ]; then
    exit 1
else
    exit 0
fi
