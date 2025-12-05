# Security

WPFleet includes comprehensive security features to protect your WordPress sites.

## Overview

WPFleet provides multiple layers of security:
- **Automatic HTTPS** with Let's Encrypt certificates
- **Security headers** configured by default
- **Container isolation** for process separation
- **File access restrictions** to protect sensitive files
- **Network security** with Docker networking
- **XML-RPC blocking** to prevent brute force attacks
- **Regular security updates** via Docker images

## Built-in Security Features

### Automatic HTTPS

**What it does:**
- Automatically obtains SSL certificates from Let's Encrypt
- Renews certificates before expiration
- Redirects HTTP to HTTPS
- Enforces secure connections

**Configuration:**

Configured automatically in Caddy for each site:

```caddy
example.com {
    # Automatic HTTPS enabled by default
    tls {
        protocols tls1.2 tls1.3
    }
}
```

**Monitor SSL certificates:**

```bash
./scripts/ssl-monitor.sh
```

### Security Headers

WPFleet configures these security headers for all sites:

**Content Security Policy (CSP):**
```
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';
```

**HTTP Strict Transport Security (HSTS):**
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

**X-Frame-Options:**
```
X-Frame-Options: SAMEORIGIN
```

**X-Content-Type-Options:**
```
X-Content-Type-Options: nosniff
```

**X-XSS-Protection:**
```
X-XSS-Protection: 1; mode=block
```

**Referrer Policy:**
```
Referrer-Policy: strict-origin-when-cross-origin
```

**Permissions Policy:**
```
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

### File Access Restrictions

Caddy blocks access to sensitive files:

- `wp-config.php` - WordPress configuration
- `.git/` - Git repositories
- `.env` - Environment files
- `.htaccess` - Apache configuration
- `*.sql` - Database dumps
- `*.log` - Log files

**Configured in Caddy:**

```caddy
# Block sensitive files
@forbidden {
    path /wp-config.php /.git/* /.env .htaccess *.sql *.log
}
respond @forbidden 403
```

### XML-RPC Protection

XML-RPC is blocked by default to prevent:
- Brute force attacks
- DDoS amplification
- Pingback spam

**Configured in Caddy:**

```caddy
# Block XML-RPC
@xmlrpc path /xmlrpc.php
respond @xmlrpc 403
```

**To enable XML-RPC if needed:**

Edit `config/caddy/sites/example.com.caddy` and remove the XML-RPC block.

### Container Isolation

Each service runs in isolated containers:

- **FrankenPHP**: Runs as `www-data` (unprivileged)
- **MariaDB**: Isolated database with limited access
- **Valkey**: Password-protected cache service
- **Cron**: Separate container for scheduled tasks

**Benefits:**
- Process isolation prevents cross-contamination
- Limited attack surface per container
- Easy to restart or update individual services

### Network Security

Docker network isolation:

```yaml
networks:
  wpfleet:
    driver: bridge
    internal: false
```

**Security features:**
- Services communicate via internal Docker network
- MariaDB and Valkey not exposed to host
- Only FrankenPHP exposes ports 80 and 443

## Database Security

### Password Protection

**Strong passwords required:**

```env
MYSQL_ROOT_PASSWORD=generate_strong_password_here
MYSQL_PASSWORD=generate_strong_password_here
```

**Generate secure passwords:**

```bash
openssl rand -base64 32
```

### Limited Access

Database access is restricted:

- Root user only accessible from within Docker network
- Application user (`wpfleet`) has limited permissions
- No external port exposure by default

### Database Connections

**From host machine** (requires Docker exec):

```bash
docker exec -it wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD}
```

**For external access** (not recommended for production):

```bash
# Create SSH tunnel instead
ssh -L 3306:localhost:3306 user@your-server
```

## Valkey (Redis) Security

### Password Authentication

Valkey requires authentication:

```env
REDIS_PASSWORD=generate_strong_password_here
```

**Configured in Valkey:**

```conf
requirepass your_password_here
```

### Disabled Dangerous Commands

These commands are disabled for security:

- `FLUSHALL` - Delete all keys
- `FLUSHDB` - Delete database keys
- `CONFIG` - Change configuration
- `KEYS` - List all keys (performance risk)

**Configured in `docker/valkey/valkey.conf`:**

```conf
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command KEYS ""
```

### Network Isolation

Valkey only accessible via Docker network, not exposed to host.

## WordPress Security

### File Permissions

Proper permissions are critical:

```bash
# Set correct ownership
docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com

# Set directory permissions
find data/wordpress/example.com -type d -exec chmod 755 {} \;

# Set file permissions
find data/wordpress/example.com -type f -exec chmod 644 {} \;
```

### wp-config.php Security

WPFleet configures secure `wp-config.php`:

```php
// Disable file editing in WordPress admin
define( 'DISALLOW_FILE_EDIT', true );

// Limit post revisions
define( 'WP_POST_REVISIONS', 5 );

// Force SSL for admin
define( 'FORCE_SSL_ADMIN', true );

// Security keys (automatically generated)
define( 'AUTH_KEY', 'unique-key-here' );
// ... more keys
```

### Disable Directory Listing

Configured in Caddy to prevent directory browsing:

```caddy
file_server {
    hide .git
    disable_canonical_headers
}
```

## Security Best Practices

### 1. Strong Passwords

Use strong passwords for:
- MySQL root and application users
- Valkey authentication
- WordPress admin accounts
- SSH access

**Generate passwords:**

```bash
openssl rand -base64 32
```

### 2. Keep Software Updated

Regularly update:

```bash
# Update Docker images
docker-compose pull
docker-compose up -d

# Update WordPress core
./scripts/wp-cli.sh example.com core update

# Update plugins
./scripts/wp-cli.sh example.com plugin update --all

# Update themes
./scripts/wp-cli.sh example.com theme update --all
```

### 3. Use Security Plugins

Install WordPress security plugins:

```bash
# Wordfence Security
./scripts/wp-cli.sh example.com plugin install wordfence --activate

# iThemes Security
./scripts/wp-cli.sh example.com plugin install better-wp-security --activate

# Sucuri Security
./scripts/wp-cli.sh example.com plugin install sucuri-scanner --activate
```

### 4. Limit Login Attempts

Configure login attempt limiting in WordPress security plugins or use Cloudflare.

### 5. Two-Factor Authentication

Enable 2FA for WordPress admin:

```bash
./scripts/wp-cli.sh example.com plugin install two-factor --activate
```

### 6. Regular Backups

Maintain regular backups:

```env
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"
```

See [Backups](./backups.md) for details.

### 7. Monitor Logs

Regularly check logs for suspicious activity:

```bash
docker logs wpfleet_frankenphp | grep -i "error\|warning"
```

### 8. Firewall Configuration

Use a firewall (UFW on Ubuntu):

```bash
# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
```

### 9. Disable Unused Services

Only run necessary services:

```bash
# List running containers
docker ps

# Stop unused containers
docker stop container_name
```

### 10. Use CDN/DDoS Protection

Use a CDN with DDoS protection:
- **Cloudflare** (free plan available)
- **AWS CloudFront**
- **Fastly**
- **KeyCDN**

## Additional Security Layers

### CDN/DDoS Protection

**Cloudflare setup:**

1. Add your domain to Cloudflare
2. Update nameservers
3. Enable SSL/TLS (Full mode)
4. Enable DDoS protection
5. Configure firewall rules
6. Enable rate limiting

**Benefits:**
- DDoS protection
- Rate limiting
- Bot protection
- WAF (Web Application Firewall)
- Global CDN

### Fail2Ban

Install Fail2Ban on host to block brute force:

```bash
sudo apt-get install fail2ban
```

**Configure for WordPress:**

```ini
# /etc/fail2ban/jail.local
[wordpress]
enabled = true
filter = wordpress
logpath = /path/to/wpfleet/data/logs/*.log
maxretry = 5
bantime = 3600
```

### ModSecurity WAF

Add ModSecurity for additional protection:

```yaml
# In docker-compose.yml
services:
  waf:
    image: owasp/modsecurity-crs:nginx
    ports:
      - "80:80"
      - "443:443"
    environment:
      - BACKEND=http://frankenphp:8080
```

## Security Checklist

Use this checklist for new installations:

- [ ] Generate strong passwords for all services
- [ ] Configure `.env` with secure values
- [ ] Enable HTTPS for all sites
- [ ] Configure security headers
- [ ] Block XML-RPC if not needed
- [ ] Set proper file permissions
- [ ] Install WordPress security plugin
- [ ] Enable two-factor authentication
- [ ] Configure regular backups
- [ ] Set up monitoring and alerts
- [ ] Enable firewall (UFW)
- [ ] Configure fail2ban
- [ ] Use CDN/DDoS protection
- [ ] Disable directory listing
- [ ] Remove default plugins and themes
- [ ] Disable file editing in WordPress
- [ ] Limit login attempts
- [ ] Keep software updated
- [ ] Review user accounts and permissions
- [ ] Monitor logs regularly

## Security Monitoring

### Automated Security Checks

Add security checks to cron:

```bash
#!/bin/bash
# security-check.sh

# Check for weak passwords in users
WEAK=$(docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT user FROM mysql.user WHERE password = '' OR password IS NULL")

if [ -n "$WEAK" ]; then
    ./scripts/notify.sh error "Security Issue" "Found users with weak passwords"
fi

# Check for outdated plugins
OUTDATED=$(./scripts/wp-cli.sh example.com plugin list --update=available --format=count)

if [ $OUTDATED -gt 0 ]; then
    ./scripts/notify.sh warning "Updates Available" "$OUTDATED plugins need updates"
fi
```

Add to cron:

```env
CUSTOM_CRON_JOBS="0 0 * * * cd /wpfleet && ./security-check.sh"
```

### Security Audit

Regularly audit security:

```bash
# Check running containers
docker ps

# Check open ports
sudo netstat -tlnp

# Check file permissions
find data/wordpress -type f -perm 777

# Check for malware (install ClamAV)
clamscan -r data/wordpress/

# Check SSL certificates
./scripts/ssl-monitor.sh

# Review user accounts
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SELECT user, host FROM mysql.user"
```

## Incident Response

### Security Breach Response

If you suspect a security breach:

1. **Isolate affected sites:**
   ```bash
   docker stop wpfleet_frankenphp
   ```

2. **Review logs:**
   ```bash
   docker logs wpfleet_frankenphp > breach-logs.txt
   ```

3. **Check for malware:**
   ```bash
   clamscan -r data/wordpress/example.com
   ```

4. **Restore from backup:**
   ```bash
   ./scripts/site-manager.sh remove example.com
   ./scripts/site-manager.sh add example.com --import-from
   ```

5. **Update all passwords:**
   - MySQL passwords
   - Valkey password
   - WordPress admin passwords
   - SSH keys

6. **Update all software:**
   ```bash
   docker-compose pull
   ./scripts/wp-cli.sh example.com core update
   ./scripts/wp-cli.sh example.com plugin update --all
   ```

7. **Review access logs** for suspicious activity

8. **Notify users** if data was compromised

## Security Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [WordPress Security](https://wordpress.org/support/article/hardening-wordpress/)
- [Docker Security](https://docs.docker.com/engine/security/)
- [Let's Encrypt](https://letsencrypt.org/)
- [WPScan](https://wpscan.com/) - WordPress vulnerability scanner

## Related Documentation

- [Installation Guide](./installation.md)
- [Site Management](./site-management.md)
- [Backups](./backups.md)
- [Monitoring](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)
