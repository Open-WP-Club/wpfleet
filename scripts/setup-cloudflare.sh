#!/bin/bash

# WPFleet Cloudflare Setup Helper
# Cloudflare provides DDoS protection, rate limiting, and WAF

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/lib/common.sh"

print_header "WPFleet + Cloudflare Setup"

echo "
Cloudflare provides superior protection for WordPress:

1. DDoS Protection (automatic)
2. Rate Limiting (configurable)
3. WAF (Web Application Firewall)
4. Bot Management
5. SSL/TLS encryption
6. CDN for static assets

Setup Steps:
-----------

1. Sign up at https://cloudflare.com (free tier available)

2. Add your domain to Cloudflare

3. Update your domain's nameservers to Cloudflare's

4. Enable these Cloudflare features:
   - Security Level: Medium or High
   - Challenge Passage: 30 minutes
   - Browser Integrity Check: On
   - Rate Limiting: Create rules for /wp-login.php and /xmlrpc.php

5. Cloudflare Rate Limiting Rules (recommended):

   Rule 1 - Login Protection:
   - If URL path contains /wp-login.php
   - And Request count > 5 in 1 minute
   - Then Block for 10 minutes

   Rule 2 - XML-RPC Protection:
   - If URL path contains /xmlrpc.php
   - And Request count > 3 in 1 minute
   - Then Block for 1 hour

   Rule 3 - Admin Protection:
   - If URL path starts with /wp-admin
   - And Request count > 30 in 1 minute
   - Then Challenge

6. Enable 'Under Attack Mode' if under active attack

7. Optional: Install Cloudflare Origin CA certificates
   for end-to-end encryption (Cloudflare <-> Your Server)

Benefits over Fail2ban:
----------------------
✓ Works perfectly with Docker
✓ Protection before traffic reaches your server
✓ No iptables conflicts
✓ Better bot detection
✓ Automatic DDoS mitigation
✓ Free tier available
✓ Global CDN included

Note: Cloudflare's free tier includes basic rate limiting.
For advanced features, consider Pro plan (\$20/month).
"

print_info "Cloudflare is the recommended solution for Docker environments"
