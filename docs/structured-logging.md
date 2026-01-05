# Structured Logging with FrankenPHP 1.11+

WPFleet now includes comprehensive structured logging support using FrankenPHP 1.11's native `frankenphp_log()` function. This provides better observability, easier debugging, and seamless integration with monitoring platforms like Datadog, Grafana Loki, and Elastic.

## Table of Contents

- [Overview](#overview)
- [PHP Structured Logging](#php-structured-logging)
- [Bash Script Logging](#bash-script-logging)
- [FrankenPHP Worker Logging](#frankenphp-worker-logging)
- [Integration with Monitoring Tools](#integration-with-monitoring-tools)
- [Examples](#examples)

## Overview

Structured logging outputs logs in JSON format with contextual metadata, making them:
- **Machine-readable**: Easy to parse and query
- **Searchable**: Filter by specific fields
- **Contextual**: Include relevant metadata automatically
- **Standardized**: Consistent format across all components

### Benefits

- Better debugging with rich context
- Easier log aggregation and analysis
- Performance monitoring built-in
- Security event tracking
- Integration with modern observability platforms

## PHP Structured Logging

### Installation

Copy the logger library to your WordPress mu-plugins directory:

```bash
cp config/php/wpfleet-logger.php data/wordpress/wp-content/mu-plugins/
```

### Basic Usage

```php
// Simple logging
wpfleet_log('User action completed', 'info', [
    'user_id' => 123,
    'action' => 'post_published'
]);

// Different log levels
wpfleet_log('Debug information', 'debug', ['var' => $value]);
wpfleet_log('Something noteworthy', 'info');
wpfleet_log('Potential issue', 'warn', ['reason' => 'slow_query']);
wpfleet_log('Error occurred', 'error', ['error_code' => 500]);
```

### Object-Oriented Interface

```php
// Create a logger with default context
$logger = new WPFleet_Logger([
    'component' => 'payment_processor',
    'version' => '1.0.0'
]);

// All logs will include the default context
$logger->info('Payment processed', [
    'amount' => 99.99,
    'currency' => 'USD'
]);

$logger->error('Payment failed', [
    'reason' => 'insufficient_funds'
]);
```

### Logging Exceptions

```php
try {
    // Your code here
    risky_operation();
} catch (Exception $e) {
    $logger->exception('Operation failed', $e, [
        'user_id' => get_current_user_id(),
        'additional' => 'context'
    ]);
}
```

### Performance Monitoring

```php
$start = microtime(true);

// Your operation
perform_expensive_operation();

$duration = (microtime(true) - $start) * 1000; // Convert to ms

$logger->performance('expensive_operation', $duration, [
    'items_processed' => 1000,
    'cache_hits' => 850
]);
```

### Automatic WordPress Integration

The logger automatically hooks into WordPress events:

```php
// Automatically logs:
- Failed login attempts
- Successful logins
- WordPress errors (wp_error_added)
- PHP errors (when WPFLEET_LOG_PHP_ERRORS is enabled)
```

Enable PHP error logging in wp-config.php:

```php
define('WPFLEET_LOG_PHP_ERRORS', true);
```

### Log Output Format

```json
{
  "timestamp": "2026-01-05T16:30:45Z",
  "level": "INFO",
  "message": "User logged in",
  "context": {
    "site": "example.com",
    "request_uri": "/wp-admin/",
    "user_agent": "Mozilla/5.0...",
    "php_version": "8.3.0",
    "user_id": 123,
    "user_login": "admin",
    "ip": "192.168.1.100"
  }
}
```

## Bash Script Logging

### Installation

The enhanced logger is available in `scripts/lib/logger.sh`. Source it in your scripts:

```bash
#!/bin/bash

# Source the logger library
source "$(dirname "$0")/lib/logger.sh"

# Now use logging functions
log_info "Script starting"
```

### Basic Usage

```bash
# Different log levels
log_debug "Debug information"
log_info "Informational message"
log_warn "Warning message"
log_error "Error message"
```

### Structured Logging in Bash

Enable JSON output:

```bash
export STRUCTURED_LOGGING=true
export LOG_FILE="/var/log/wpfleet/script.log"

log_info "Site provisioned" \
    "site=example.com" \
    "database=wp_example_com" \
    "size_mb=250"
```

Output:
```json
{
  "timestamp": "2026-01-05T16:30:45Z",
  "level": "INFO",
  "message": "Site provisioned",
  "script": "site-manager.sh",
  "hostname": "wpfleet-server",
  "pid": 12345,
  "site": "example.com",
  "database": "wp_example_com",
  "size_mb": "250"
}
```

### Operation Logging

```bash
start_time=$(date +%s)

# Perform operation
perform_backup

end_time=$(date +%s)

log_operation "backup" "$start_time" "$end_time" "success" \
    "site=example.com" \
    "size_mb=500"
```

### Execute with Logging

```bash
execute_with_logging "database_backup" \
    "docker exec wpfleet_mariadb mysqldump wpfleet > backup.sql"
```

### Container Metrics Logging

```bash
log_container_metrics "wpfleet_frankenphp"
```

### Disk Usage Logging

```bash
log_disk_usage "/var/www/html/sites/example.com"
```

### Database Metrics Logging

```bash
log_database_metrics "wp_example_com"
```

## FrankenPHP Worker Logging

The worker script (`docker/frankenphp/worker.php`) includes comprehensive logging:

- Worker initialization and shutdown
- Request completion with performance metrics
- Exception handling with full stack traces
- Periodic health checks (every 100 requests)
- Memory threshold warnings

### Worker Log Example

```json
{
  "level": "info",
  "message": "Request completed",
  "context": {
    "duration_ms": 45.23,
    "memory_mb": 128.5,
    "uri": "/wp-admin/post.php",
    "method": "POST",
    "status": 200,
    "requests_total": 523,
    "worker_uptime_seconds": 3600
  }
}
```

## Integration with Monitoring Tools

### Grafana Loki

All logs are in JSON format, making them compatible with Grafana Loki:

```yaml
# Promtail config
scrape_configs:
  - job_name: wpfleet
    static_configs:
      - targets:
          - localhost
        labels:
          job: wpfleet
          __path__: /var/log/frankenphp/*.log
```

### Datadog

Configure Datadog agent to collect JSON logs:

```yaml
logs:
  - type: file
    path: /var/log/frankenphp/*.log
    service: wpfleet
    source: frankenphp
```

### Elastic/Logstash

Use Filebeat to ship logs to Elasticsearch:

```yaml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/frankenphp/*.log
    json.keys_under_root: true
    json.add_error_key: true
```

## Examples

### Example 1: Site Provisioning

```php
$logger = new WPFleet_Logger(['component' => 'site_manager']);

$start = microtime(true);

try {
    $logger->info('Starting site provisioning', [
        'domain' => $domain,
        'user_id' => get_current_user_id()
    ]);

    create_database($domain);
    create_site_directory($domain);
    configure_caddy($domain);

    $duration = (microtime(true) - $start) * 1000;

    $logger->info('Site provisioned successfully', [
        'domain' => $domain,
        'duration_ms' => round($duration, 2)
    ]);

} catch (Exception $e) {
    $logger->exception('Site provisioning failed', $e, [
        'domain' => $domain
    ]);
    throw $e;
}
```

### Example 2: Backup Script

```bash
#!/bin/bash
source "$(dirname "$0")/lib/logger.sh"

STRUCTURED_LOGGING=true
LOG_FILE="/var/log/wpfleet/backup.log"

SITE=$1
start_time=$(date +%s)

log_info "Starting backup" "site=$SITE"

if execute_with_logging "backup_files" "./backup-files.sh $SITE"; then
    if execute_with_logging "backup_database" "./backup-db.sh $SITE"; then
        end_time=$(date +%s)
        log_operation "full_backup" "$start_time" "$end_time" "success" \
            "site=$SITE"
    else
        log_error "Database backup failed" "site=$SITE"
        exit 1
    fi
else
    log_error "File backup failed" "site=$SITE"
    exit 1
fi
```

### Example 3: Custom WordPress Plugin

```php
<?php
/**
 * Plugin Name: My Plugin with Logging
 */

// Create a logger for this plugin
$logger = new WPFleet_Logger([
    'plugin' => 'my-plugin',
    'version' => '1.0.0'
]);

add_action('save_post', function($post_id) use ($logger) {
    $start = microtime(true);

    // Your logic here
    process_post_data($post_id);

    $duration = (microtime(true) - $start) * 1000;

    $logger->performance('post_processing', $duration, [
        'post_id' => $post_id,
        'post_type' => get_post_type($post_id)
    ]);
});

add_action('wp_ajax_my_action', function() use ($logger) {
    try {
        $result = perform_ajax_action();

        $logger->info('AJAX action completed', [
            'action' => 'my_action',
            'user_id' => get_current_user_id()
        ]);

        wp_send_json_success($result);

    } catch (Exception $e) {
        $logger->exception('AJAX action failed', $e, [
            'action' => 'my_action'
        ]);

        wp_send_json_error([
            'message' => 'Operation failed'
        ]);
    }
});
```

## Best Practices

1. **Include Relevant Context**: Add useful metadata that helps debugging
2. **Use Appropriate Log Levels**: Debug for development, Info for operations, Warn for issues, Error for failures
3. **Log Performance Metrics**: Track operation duration for optimization
4. **Don't Log Sensitive Data**: Avoid passwords, API keys, personal information
5. **Be Consistent**: Use standardized field names across your application
6. **Log at Boundaries**: Log at system entry/exit points and integration points

## Viewing Logs

### Development

```bash
# View all logs
docker-compose logs -f frankenphp

# View structured logs
docker exec wpfleet_frankenphp tail -f /var/log/frankenphp/access.log | jq .

# View specific log level
docker exec wpfleet_frankenphp tail -f /var/log/frankenphp/access.log | jq 'select(.level == "ERROR")'
```

### Production

Use your monitoring platform's query interface to search and filter logs:

```
# Grafana Loki query
{job="wpfleet"} | json | level="error"

# Find slow requests
{job="wpfleet"} | json | duration_ms > 1000
```

## Configuration

### PHP Logger

Configure in wp-config.php:

```php
// Enable PHP error logging
define('WPFLEET_LOG_PHP_ERRORS', true);

// Set WordPress environment
define('WP_ENV', 'production');
```

### Bash Logger

Set environment variables:

```bash
export STRUCTURED_LOGGING=true
export LOG_LEVEL=INFO  # DEBUG, INFO, WARN, ERROR
export LOG_FILE=/var/log/wpfleet/mylog.log
```

### FrankenPHP

Configure in docker-compose.yml or .env:

```env
FRANKENPHP_WORKER_ENABLED=true
FRANKENPHP_WORKER_MAX_MEMORY=536870912  # 512MB
```

## Troubleshooting

### Logs Not Appearing

1. Check if FrankenPHP 1.11+ is installed:
   ```bash
   docker exec wpfleet_frankenphp frankenphp version
   ```

2. Verify log file permissions:
   ```bash
   docker exec wpfleet_frankenphp ls -la /var/log/frankenphp/
   ```

3. Check if frankenphp_log function exists:
   ```bash
   docker exec wpfleet_frankenphp php -r "var_dump(function_exists('frankenphp_log'));"
   ```

### Fallback Behavior

If `frankenphp_log()` is not available, the library automatically falls back to standard `error_log()` with JSON formatting, ensuring logs are still structured.
