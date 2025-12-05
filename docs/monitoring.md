# Monitoring and Health Checks

Monitor your WPFleet installation with real-time dashboards and automated health checks.

## Overview

WPFleet provides comprehensive monitoring capabilities:
- **Real-time dashboard** with resource usage
- **Automated health checks** via cron
- **Service monitoring** (MariaDB, Valkey, FrankenPHP)
- **Performance metrics** (OPcache, queries, cache hit rates)
- **SSL certificate monitoring**
- **Disk usage tracking**
- **Error log monitoring**

## Real-Time Monitoring Dashboard

### Launch Dashboard

```bash
./scripts/monitor.sh
```

Or with custom refresh interval (in seconds):

```bash
./scripts/monitor.sh 5  # Refresh every 5 seconds
```

### Dashboard Information

The dashboard displays:

**Container Resources:**
- CPU usage per container
- Memory usage (current and limit)
- Container status

**MariaDB Statistics:**
- Queries per second
- Active connections
- Slow queries
- Buffer pool usage
- Cache hit rate

**Valkey Statistics:**
- Commands per second
- Memory usage
- Cache hit rate
- Connected clients
- Evicted keys

**OPcache Statistics:**
- Hit rate
- Memory usage
- Number of cached scripts
- Cache full status

**WordPress Sites:**
- List of active sites
- Site count

**System Health:**
- Disk usage
- Recent errors from logs

### Keyboard Controls

- **q**: Quit dashboard
- **r**: Force refresh
- **Ctrl+C**: Exit

## Automated Health Checks

### Enable Health Checks

Configure in `.env`:

```env
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_SCHEDULE="0 * * * *"  # Every hour
```

Start the cron container:

```bash
docker-compose up -d cron
```

### What's Checked

The health check script verifies:

1. **Core Services**
   - MariaDB is running and responding
   - Valkey is running and responding
   - FrankenPHP is running and responding

2. **Database Connectivity**
   - Can connect to MariaDB
   - Databases are accessible
   - No corruption detected

3. **Valkey Connectivity**
   - Can connect to Valkey
   - Authentication working
   - Memory usage acceptable

4. **Site Configurations**
   - Caddy configurations valid
   - WordPress directories exist
   - Permissions are correct

5. **Disk Usage**
   - Overall disk space < 90%
   - Warning if > 80%

6. **Recent Errors**
   - Checks logs for critical errors
   - Reports unusual error rates

### Manual Health Check

Run a health check anytime:

```bash
./scripts/health-check.sh
```

**Output:**

```
WPFleet Health Check
====================

✓ MariaDB is running
✓ Valkey is running
✓ FrankenPHP is running
✓ Database connectivity OK
✓ Valkey connectivity OK
✓ Disk usage: 45% (OK)
⚠ Found 3 errors in last hour (check logs)

Sites:
  ✓ example.com - OK
  ✓ another-site.com - OK

Overall Status: HEALTHY (1 warning)
```

### Health Check Logs

View health check logs:

```bash
tail -f data/logs/cron/health-check.log
```

## SSL Certificate Monitoring

### Check SSL Status

```bash
./scripts/ssl-monitor.sh
```

**Output:**

```
SSL Certificate Status
======================

example.com
  Status: Valid
  Expires: 2024-03-15 (75 days)
  Issuer: Let's Encrypt

another-site.com
  Status: Valid
  Expires: 2024-02-01 (17 days)
  Issuer: Let's Encrypt
  ⚠ Warning: Expires in less than 30 days

test-site.com
  Status: Not Found
  ✗ No certificate found
```

### Automated SSL Monitoring

Add to cron for regular checks:

```env
CUSTOM_CRON_JOBS="0 0 * * * cd /wpfleet && ./scripts/ssl-monitor.sh"
```

Notifications are sent for:
- Certificates expiring in < 30 days
- Missing certificates
- Invalid certificates

## Service Monitoring

### MariaDB Monitoring

**Check status:**

```bash
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS"
```

**Key metrics:**

```bash
# Queries per second
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Questions'"

# Active connections
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Threads_connected'"

# Slow queries
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Slow_queries'"
```

### Valkey Monitoring

**Check status:**

```bash
docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO
```

**Key metrics:**

```bash
# Hit rate
docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO stats | grep keyspace

# Memory usage
docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO memory

# Connected clients
docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO clients
```

### FrankenPHP Monitoring

**Check status:**

```bash
docker exec wpfleet_frankenphp php -i | grep opcache
```

**Resource usage:**

```bash
docker stats wpfleet_frankenphp --no-stream
```

## Performance Metrics

### Database Performance

**Query analysis:**

```bash
# Enable slow query log
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SET GLOBAL slow_query_log = 'ON'"

# View slow queries
docker exec wpfleet_mariadb tail -f /var/log/mysql/slow.log
```

**Connection pool:**

```bash
# Current connections
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW PROCESSLIST"
```

### Cache Performance

**Object cache hit rate:**

```bash
./scripts/cache-manager.sh stats
```

**Page cache statistics:**

```bash
./scripts/cache-manager.sh stats example.com
```

### PHP Performance

**OPcache status:**

```bash
docker exec wpfleet_frankenphp php -r "print_r(opcache_get_status());"
```

## Log Monitoring

### Application Logs

**FrankenPHP logs:**

```bash
docker logs wpfleet_frankenphp
docker logs -f wpfleet_frankenphp  # Follow mode
docker logs --tail 100 wpfleet_frankenphp  # Last 100 lines
```

**MariaDB logs:**

```bash
docker logs wpfleet_mariadb
```

**Valkey logs:**

```bash
docker logs wpfleet_valkey
```

### WordPress Logs

**Error logs:**

```bash
tail -f data/wordpress/example.com/wp-content/debug.log
```

**Enable debug logging** in `wp-config.php`:

```php
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_LOG', true );
define( 'WP_DEBUG_DISPLAY', false );
```

### System Logs

**Cron logs:**

```bash
tail -f data/logs/cron/backup.log
tail -f data/logs/cron/health-check.log
tail -f data/logs/cron/cleanup.log
```

## Alerts and Notifications

### Automatic Alerts

Notifications are sent for:

**Critical (Red):**
- Service down (MariaDB, Valkey, FrankenPHP)
- Disk space > 90%
- Backup failure
- Database connection failure
- Site quota exceeded

**Warning (Yellow):**
- Disk space > 80%
- SSL certificate < 30 days
- High error rate in logs
- Site quota > 80%
- Slow queries detected

**Info (Blue):**
- Health check passed
- Backup completed
- Deployment completed

### Custom Alerts

Add custom monitoring scripts:

```bash
#!/bin/bash
# custom-monitor.sh

# Check PHP-FPM processes
PROCESSES=$(docker exec wpfleet_frankenphp ps aux | grep php-fpm | wc -l)

if [ $PROCESSES -gt 50 ]; then
    ./scripts/notify.sh warning "High PHP Processes" "PHP-FPM processes: $PROCESSES"
fi

# Check MariaDB connections
CONNECTIONS=$(docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Threads_connected'" | awk 'NR==2 {print $2}')

if [ $CONNECTIONS -gt 100 ]; then
    ./scripts/notify.sh warning "High DB Connections" "Active connections: $CONNECTIONS"
fi
```

Add to cron:

```env
CUSTOM_CRON_JOBS="*/15 * * * * cd /wpfleet && ./custom-monitor.sh"
```

## Performance Baselines

### Establish Baselines

Record normal performance metrics:

```bash
# Create baseline script
#!/bin/bash
# baseline.sh

echo "=== Performance Baseline $(date) ===" >> baseline.log

# CPU and Memory
docker stats --no-stream >> baseline.log

# Database queries
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Questions'" >> baseline.log

# Cache hit rate
./scripts/cache-manager.sh stats >> baseline.log
```

Run during normal traffic:

```bash
./baseline.sh
```

### Compare Against Baselines

Use baselines to identify anomalies:
- Sudden increase in database queries
- Drop in cache hit rate
- Memory usage spikes
- Increased error rates

## Troubleshooting with Monitoring

### High CPU Usage

1. **Identify container:**
   ```bash
   docker stats --no-stream
   ```

2. **Check processes:**
   ```bash
   docker exec wpfleet_frankenphp top
   ```

3. **Review logs:**
   ```bash
   docker logs wpfleet_frankenphp | tail -100
   ```

### High Memory Usage

1. **Check container memory:**
   ```bash
   docker stats wpfleet_mariadb --no-stream
   ```

2. **MariaDB buffer pool:**
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size'"
   ```

3. **Valkey memory:**
   ```bash
   docker exec wpfleet_valkey valkey-cli -a ${REDIS_PASSWORD} INFO memory
   ```

### Slow Performance

1. **Check cache hit rates:**
   ```bash
   ./scripts/cache-manager.sh stats
   ```

2. **Identify slow queries:**
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW STATUS LIKE 'Slow_queries'"
   ```

3. **Check OPcache:**
   ```bash
   docker exec wpfleet_frankenphp php -r "print_r(opcache_get_status());"
   ```

## Best Practices

### 1. Regular Monitoring

Check dashboard regularly:
```bash
./scripts/monitor.sh
```

### 2. Enable Automated Checks

Always run health checks:
```env
HEALTH_CHECK_ENABLED=true
HEALTH_CHECK_SCHEDULE="0 * * * *"
```

### 3. Monitor Trends

Track metrics over time:
- Daily resource usage
- Cache hit rates
- Query performance
- Error rates

### 4. Set Up Alerts

Configure notifications for all critical events.

### 5. Review Logs

Periodically review logs for patterns:
```bash
docker logs wpfleet_frankenphp | grep -i error | less
```

### 6. Document Incidents

Keep records of:
- Performance issues
- Resolution steps
- Configuration changes
- Lessons learned

## External Monitoring

### Uptime Monitoring

Use external services:
- UptimeRobot
- Pingdom
- StatusCake
- Uptime.com

Monitor your sites' HTTPS endpoints.

### APM (Application Performance Monitoring)

Integrate APM tools:
- New Relic
- Datadog
- AppDynamics
- Elastic APM

### Log Aggregation

Send logs to external services:
- Elasticsearch + Kibana
- Splunk
- Loggly
- Papertrail

Example with Filebeat:

```yaml
# filebeat.yml
filebeat.inputs:
  - type: container
    paths:
      - /var/lib/docker/containers/*/*.log

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
```

## Related Documentation

- [Site Management](./site-management.md)
- [Backups](./backups.md)
- [Notifications](./notifications.md)
- [Cache Management](./cache-management.md)
- [Disk Quotas](./disk-quotas.md)
- [Security](./security.md)
- [Troubleshooting](./troubleshooting.md)
