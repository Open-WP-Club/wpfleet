# Troubleshooting Guide

This guide helps you diagnose and fix common issues in WPFleet.

## Quick Diagnostic Commands

```bash
# Check all services status
docker ps

# Run health check
./scripts/health-check.sh

# Check logs
docker logs wpfleet_frankenphp --tail 50
docker logs wpfleet_mariadb --tail 50
docker logs wpfleet_valkey --tail 50

# Check disk space
df -h
```

## Installation Issues

### Docker Not Installed

**Error:** `docker: command not found`

**Solution:**

Use the provided installation script:

```bash
sudo ./install_util.sh
```

Or install manually:

```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker
```

### Permission Denied

**Error:** `permission denied while trying to connect to the Docker daemon socket`

**Solution:**

Add your user to the docker group:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Log out and back in for changes to take effect.

### Port Already in Use

**Error:** `port is already allocated`

**Solution:**

Check what's using ports 80 or 443:

```bash
sudo netstat -tlnp | grep -E ':(80|443)'
```

Stop the conflicting service:

```bash
# Apache
sudo systemctl stop apache2
sudo systemctl disable apache2

# Nginx
sudo systemctl stop nginx
sudo systemctl disable nginx
```

## Site Access Issues

### Site Not Loading (502 Bad Gateway)

**Possible causes:**

1. **FrankenPHP not running:**
   ```bash
   docker ps | grep frankenphp
   ```

   **Fix:**
   ```bash
   ./scripts/site-manager.sh restart
   ```

2. **Site directory missing:**
   ```bash
   ls -la data/wordpress/example.com
   ```

   **Fix:**
   Recreate the site or restore from backup.

3. **Caddy configuration error:**
   ```bash
   cat config/caddy/sites/example.com.caddy
   ```

   **Fix:**
   Verify configuration syntax and restart.

### Site Not Loading (404 Not Found)

**Possible causes:**

1. **Caddy configuration missing:**
   ```bash
   ls config/caddy/sites/example.com.caddy
   ```

   **Fix:**
   ```bash
   ./scripts/site-manager.sh add example.com --skip-install
   ```

2. **Wrong site directory:**
   ```bash
   ls -la data/wordpress/
   ```

   **Fix:**
   Ensure directory name matches domain.

### Site Shows PHP Code Instead of Executing

**Cause:** FrankenPHP not processing PHP files

**Solution:**

1. **Restart FrankenPHP:**
   ```bash
   docker restart wpfleet_frankenphp
   ```

2. **Check Caddy configuration:**
   ```bash
   cat config/caddy/sites/example.com.caddy
   ```

   Ensure PHP handling is configured:
   ```caddy
   php_fastcgi unix//var/run/php/php-fpm.sock
   ```

### White Screen (WordPress)

**Possible causes:**

1. **Enable debug mode** in `wp-config.php`:
   ```php
   define( 'WP_DEBUG', true );
   define( 'WP_DEBUG_LOG', true );
   define( 'WP_DEBUG_DISPLAY', false );
   ```

2. **Check error log:**
   ```bash
   tail -f data/wordpress/example.com/wp-content/debug.log
   ```

3. **Common fixes:**
   - Deactivate all plugins
   - Switch to default theme
   - Increase PHP memory limit
   - Check file permissions

## SSL Certificate Issues

### Certificates Not Being Issued

**Error:** ACME challenge failed

**Solutions:**

1. **Verify DNS points to server:**
   ```bash
   dig +short example.com
   nslookup example.com
   ```

2. **Check ports are accessible:**
   ```bash
   sudo netstat -tlnp | grep -E ':(80|443)'
   ```

3. **View Caddy logs:**
   ```bash
   docker logs wpfleet_frankenphp | grep -i acme
   ```

4. **Common issues:**
   - DNS not propagated yet (wait 5-60 minutes)
   - Firewall blocking port 80 or 443
   - Domain not pointing to correct IP

### Certificate Expired

**Error:** NET::ERR_CERT_DATE_INVALID

**Solution:**

Caddy should auto-renew. Force renewal:

```bash
docker restart wpfleet_frankenphp
```

Check certificate status:

```bash
./scripts/ssl-monitor.sh
```

### Mixed Content Warnings

**Error:** Some resources load over HTTP

**Solution:**

Update URLs in database:

```bash
./scripts/db-manager.sh search-replace example.com 'http://example.com' 'https://example.com'
```

Force SSL in `wp-config.php`:

```php
define( 'FORCE_SSL_ADMIN', true );
if ( isset( $_SERVER['HTTP_X_FORWARDED_PROTO'] ) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    $_SERVER['HTTPS'] = 'on';
}
```

## Database Issues

### Cannot Connect to Database

**Error:** `Error establishing a database connection`

**Solutions:**

1. **Check MariaDB is running:**
   ```bash
   docker ps | grep mariadb
   ```

2. **Verify credentials in wp-config.php:**
   ```bash
   grep DB_ data/wordpress/example.com/wp-config.php
   ```

3. **Test database connection:**
   ```bash
   docker exec wpfleet_mariadb mysql -uwpfleet -p${MYSQL_PASSWORD} -e "SHOW DATABASES;"
   ```

4. **Check database exists:**
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" | grep wp_
   ```

### Database Import Failed

**Error:** Import timeout or errors

**Solutions:**

1. **Check database file:**
   ```bash
   # Test gzip file
   gunzip -t backup.sql.gz

   # Preview content
   gunzip -c backup.sql.gz | head
   ```

2. **Import manually:**
   ```bash
   # For .sql file
   docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} wp_example_com < backup.sql

   # For .sql.gz file
   gunzip -c backup.sql.gz | docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} wp_example_com
   ```

3. **Increase timeout** in `docker-compose.yml`:
   ```yaml
   mariadb:
     environment:
       - MYSQL_CONNECT_TIMEOUT=300
   ```

### Slow Database Queries

**Symptoms:** Slow page loads, high CPU on MariaDB

**Solutions:**

1. **Check slow query log:**
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW VARIABLES LIKE 'slow_query%'"
   ```

2. **Optimize database:**
   ```bash
   ./scripts/wp-cli.sh example.com db optimize
   ```

3. **Add indexes to common queries**

4. **Increase buffer pool** in `.env`:
   ```env
   MYSQL_MEM_LIMIT=2g
   ```

## Cache Issues

### Cache Not Working

**Check Redis Object Cache status:**

```bash
./scripts/wp-cli.sh example.com redis status
```

**Solutions:**

1. **Verify Valkey is running:**
   ```bash
   docker ps | grep valkey
   docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} ping
   ```

2. **Check wp-config.php has cache settings:**
   ```bash
   grep WP_REDIS data/wordpress/example.com/wp-config.php
   ```

3. **Enable Redis Object Cache plugin:**
   ```bash
   ./scripts/wp-cli.sh example.com plugin activate redis-cache
   ./scripts/wp-cli.sh example.com redis enable
   ```

### Cache Not Purging

**Symptoms:** Old content showing after updates

**Solutions:**

1. **Manually purge cache:**
   ```bash
   ./scripts/cache-manager.sh purge example.com
   ```

2. **Check plugin status:**
   ```bash
   ./scripts/wp-cli.sh example.com plugin list | grep cache
   ```

3. **Verify permissions:**
   ```bash
   docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
   ```

### High Memory Usage (Valkey)

**Solution:**

1. **Check Valkey memory:**
   ```bash
   docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO memory
   ```

2. **Adjust maxmemory** in `docker/valkey/valkey.conf`:
   ```conf
   maxmemory 512mb
   ```

3. **Purge all cache:**
   ```bash
   ./scripts/cache-manager.sh purge-all
   ```

## File Permission Issues

### Cannot Upload Files

**Error:** Permission denied when uploading

**Solution:**

Fix permissions:

```bash
# Fix ownership
docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com

# Fix directory permissions
docker exec wpfleet_frankenphp find /var/www/html/example.com -type d -exec chmod 755 {} \;

# Fix file permissions
docker exec wpfleet_frankenphp find /var/www/html/example.com -type f -exec chmod 644 {} \;

# Make wp-content writable
docker exec wpfleet_frankenphp chmod -R 775 /var/www/html/example.com/wp-content
```

### Cannot Update Plugins/Themes

**Error:** Could not create directory

**Solution:**

1. **Fix wp-content permissions:**
   ```bash
   docker exec wpfleet_frankenphp chmod -R 775 /var/www/html/example.com/wp-content
   ```

2. **Define FS_METHOD** in `wp-config.php`:
   ```php
   define( 'FS_METHOD', 'direct' );
   ```

## Performance Issues

### Slow Page Load Times

**Diagnostic steps:**

1. **Check cache hit rate:**
   ```bash
   ./scripts/cache-manager.sh stats example.com
   ```

2. **Monitor resources:**
   ```bash
   ./scripts/monitor.sh
   ```

3. **Check slow queries:**
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Slow_queries'"
   ```

**Solutions:**

1. **Enable full-page caching:**
   ```bash
   ./scripts/cache-manager.sh setup example.com
   ```

2. **Warm cache:**
   ```bash
   ./scripts/cache-manager.sh warm example.com
   ```

3. **Optimize database:**
   ```bash
   ./scripts/wp-cli.sh example.com db optimize
   ```

4. **Update all plugins:**
   ```bash
   ./scripts/wp-cli.sh example.com plugin update --all
   ```

5. **Use a CDN** like Cloudflare

### High CPU Usage

**Diagnostic:**

```bash
# Check container CPU
docker stats --no-stream

# Check processes in container
docker exec wpfleet_frankenphp top -b -n 1
```

**Solutions:**

1. **Identify problematic plugin:**
   - Disable plugins one by one
   - Check CPU after each

2. **Increase PHP-FPM workers** (if using PHP-FPM)

3. **Enable OPcache** (enabled by default in FrankenPHP)

### High Memory Usage

**Diagnostic:**

```bash
docker stats --no-stream
```

**Solutions:**

1. **Increase container memory** in `.env`:
   ```env
   FRANKENPHP_MEM_LIMIT=4g
   ```

2. **Optimize wp-config.php:**
   ```php
   define( 'WP_MEMORY_LIMIT', '256M' );
   define( 'WP_MAX_MEMORY_LIMIT', '512M' );
   ```

3. **Limit post revisions:**
   ```php
   define( 'WP_POST_REVISIONS', 5 );
   ```

## Backup and Restore Issues

### Backup Fails

**Check logs:**

```bash
tail -f data/logs/cron/backup.log
```

**Common issues:**

1. **Insufficient disk space:**
   ```bash
   df -h
   ```

2. **Permission issues:**
   ```bash
   ls -la data/backups/
   chmod 755 data/backups/
   ```

3. **Database too large:**
   - Use compression
   - Backup database separately

### Restore Fails

**Solutions:**

1. **Check backup file integrity:**
   ```bash
   # Test SQL file
   gunzip -t backup.sql.gz

   # Test archive
   tar -tzf backup.tar.gz | head
   ```

2. **Manual restore:**
   ```bash
   # Import database
   gunzip -c backup.sql.gz | docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} wp_example_com

   # Extract files
   tar -xzf backup.tar.gz -C data/wordpress/example.com/

   # Fix permissions
   docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
   ```

## Docker Issues

### Container Won't Start

**Check logs:**

```bash
docker logs wpfleet_frankenphp
docker logs wpfleet_mariadb
docker logs wpfleet_valkey
```

**Common solutions:**

1. **Port conflict:**
   ```bash
   sudo netstat -tlnp | grep -E ':(80|443|3306|6379)'
   ```

2. **Volume permission issues:**
   ```bash
   sudo chown -R $USER:$USER data/
   ```

3. **Recreate container:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Out of Disk Space

**Check disk usage:**

```bash
df -h
du -sh data/*
```

**Solutions:**

1. **Clean Docker:**
   ```bash
   docker system prune -a
   ```

2. **Remove old backups:**
   ```bash
   find data/backups/ -mtime +30 -delete
   ```

3. **Clean WordPress uploads:**
   ```bash
   # Find large files
   find data/wordpress/*/wp-content/uploads -size +100M
   ```

4. **Optimize images:**
   ```bash
   ./scripts/wp-cli.sh example.com plugin install ewww-image-optimizer --activate
   ```

### Container Keeps Restarting

**Check logs:**

```bash
docker logs wpfleet_frankenphp --tail 100
```

**Common causes:**

1. **Configuration error**
2. **Out of memory**
3. **Dependency not available**

**Solution:**

```bash
# Check container exit code
docker ps -a

# Inspect container
docker inspect wpfleet_frankenphp
```

## Network Issues

### Cannot Access from Internet

**Diagnostic:**

1. **Check firewall:**
   ```bash
   sudo ufw status
   sudo iptables -L
   ```

2. **Verify ports are open:**
   ```bash
   sudo netstat -tlnp | grep -E ':(80|443)'
   ```

3. **Test from external:**
   ```bash
   curl -I http://your-server-ip
   ```

**Solutions:**

1. **Open firewall ports:**
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

2. **Check cloud provider security groups** (AWS, DigitalOcean, etc.)

### DNS Issues

**Check DNS:**

```bash
dig +short example.com
nslookup example.com
```

**Wait for propagation:**
- Can take 5-60 minutes
- Check with multiple DNS servers

## WP-CLI Issues

### WP-CLI Command Fails

**Error:** Container not found

**Solution:**

```bash
# Ensure FrankenPHP is running
docker ps | grep frankenphp

# Try with full path
./scripts/wp-cli.sh example.com core version
```

### Permission Errors in WP-CLI

**Solution:**

Run as www-data user:

```bash
docker exec -u www-data wpfleet_frankenphp wp --path=/var/www/html/example.com core version
```

## Getting Additional Help

### Collect Diagnostic Information

```bash
#!/bin/bash
# diagnostic.sh - Collect system information

echo "=== WPFleet Diagnostic Report ===" > diagnostic.txt
echo "Date: $(date)" >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Docker Info ===" >> diagnostic.txt
docker --version >> diagnostic.txt
docker-compose --version >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Container Status ===" >> diagnostic.txt
docker ps -a >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Disk Usage ===" >> diagnostic.txt
df -h >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Service Logs ===" >> diagnostic.txt
docker logs wpfleet_frankenphp --tail 50 >> diagnostic.txt
echo "" >> diagnostic.txt

echo "Diagnostic report saved to diagnostic.txt"
```

### Where to Get Help

1. **GitHub Issues:**
   - https://github.com/Open-WP-Club/wpfleet/issues
   - Search existing issues
   - Provide diagnostic information

2. **Documentation:**
   - Read all relevant documentation
   - Check related guides

3. **Community Support:**
   - WordPress forums
   - Docker community
   - Stack Overflow

### When Reporting Issues

Include:
- WPFleet version
- Docker version
- Operating system
- Error messages
- Steps to reproduce
- Relevant logs
- What you've already tried

## Related Documentation

- [Installation Guide](./installation.md)
- [Site Management](./site-management.md)
- [Migration Guide](./migration.md)
- [Monitoring](./monitoring.md)
- [Security](./security.md)
- [Cache Management](./cache-management.md)
- [Backups](./backups.md)
