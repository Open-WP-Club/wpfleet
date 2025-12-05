# Cache Management in WPFleet

WPFleet provides comprehensive caching capabilities using a two-tier approach:

1. **Object Cache**: Redis Object Cache (via Valkey)
2. **Full-Page Cache**: Cache Enabler plugin

This document describes how to manage caching for your WordPress sites.

## Overview

The cache-manager.sh script provides an interface for managing both object caching and full-page caching across all WordPress sites in your WPFleet installation.

### Architecture

- **Valkey**: Redis-compatible in-memory data store used for object caching
- **Redis Object Cache Plugin**: WordPress plugin that integrates WP object cache with Valkey
- **Cache Enabler**: Lightweight full-page caching plugin

## Quick Start

### Enable Caching for a Site

```bash
./scripts/cache-manager.sh setup example.com
```

This will:
- Install and activate Redis Object Cache plugin
- Enable object caching connection to Valkey
- Install and activate Cache Enabler plugin
- Configure both plugins for optimal performance

### Purge Cache

```bash
# Purge all cache for a specific site
./scripts/cache-manager.sh purge example.com

# Purge all cache across all sites
./scripts/cache-manager.sh purge-all

# Purge cache for a specific URL
./scripts/cache-manager.sh purge-url example.com /blog/my-post/
```

### View Cache Statistics

```bash
# Global cache statistics
./scripts/cache-manager.sh stats

# Per-site statistics
./scripts/cache-manager.sh stats example.com

# List all cached sites
./scripts/cache-manager.sh list
```

## Commands Reference

### Setup Commands

#### `setup <domain>`
Sets up full-page caching (Redis Object Cache + Cache Enabler) for a site.

```bash
./scripts/cache-manager.sh setup example.com
```

#### `install-object <domain>`
Installs only the Redis Object Cache plugin.

```bash
./scripts/cache-manager.sh install-object example.com
```

#### `install-page <domain>`
Installs only the Cache Enabler plugin.

```bash
./scripts/cache-manager.sh install-page example.com
```

### Purge Commands

#### `purge-all`
Purges all cache across all sites.

```bash
./scripts/cache-manager.sh purge-all
```

**Use cases:**
- After Valkey configuration changes
- System-wide cache invalidation
- Troubleshooting cache issues

#### `purge <domain>`
Purges all cache for a specific site.

```bash
./scripts/cache-manager.sh purge example.com
```

**Use cases:**
- After theme or plugin updates
- After content changes
- Site-specific troubleshooting

#### `purge-url <domain> <url>`
Purges cache for a specific URL.

```bash
./scripts/cache-manager.sh purge-url example.com /blog/my-post/
```

**Use cases:**
- After editing a specific page/post
- Selective cache invalidation
- Testing changes to individual pages

### Management Commands

#### `enable <domain>`
Enables caching for a site (same as `setup`).

```bash
./scripts/cache-manager.sh enable example.com
```

#### `disable <domain>`
Disables caching for a site.

```bash
./scripts/cache-manager.sh disable example.com
```

**Note:** This will:
- Deactivate Redis Object Cache plugin
- Deactivate Cache Enabler plugin
- Purge all cached data for the site

#### `warm <domain>`
Pre-warms the cache by visiting pages.

```bash
./scripts/cache-manager.sh warm example.com
```

**How it works:**
- Fetches the sitemap.xml
- Visits up to 50 URLs from the sitemap
- Pre-generates cached pages

**Best used:**
- After purging cache
- During low-traffic periods
- Before expected traffic spikes

### Statistics Commands

#### `stats`
Shows global Valkey cache statistics.

```bash
./scripts/cache-manager.sh stats
```

**Displays:**
- Valkey server information
- Memory usage statistics
- Cache hit/miss rates
- Per-site cache key counts

#### `stats <domain>`
Shows cache statistics for a specific site.

```bash
./scripts/cache-manager.sh stats example.com
```

**Displays:**
- Object cache key count
- Sample cache keys
- Redis Object Cache plugin status
- Cache Enabler status
- Page cache size and file count

#### `list`
Lists all sites with their caching status.

```bash
./scripts/cache-manager.sh list
```

**Output format:**
```
✓ example.com (object,page)
✓ staging.example.com (object)
✗ dev.example.com (no cache)
```

## Integration with Site Manager

When creating a new WordPress site, caching is automatically configured:

```bash
# Clean install automatically includes cache setup
./scripts/site-manager.sh add example.com
```

For imported sites:

```bash
# Import site first
./scripts/site-manager.sh add example.com --import-from

# Then setup caching
./scripts/cache-manager.sh setup example.com
```

## Configuration

### Valkey Configuration

Valkey is configured in `docker/valkey/valkey.conf`:

```conf
# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru
```

**Key settings:**
- `maxmemory`: Maximum memory for cache (adjust based on available RAM)
- `maxmemory-policy`: LRU eviction when memory limit is reached
- Password protection enabled via `REDIS_PASSWORD` environment variable

### WordPress Configuration

When a site is created, wp-config.php includes:

```php
// Redis Object Cache (Valkey)
define( 'WP_REDIS_HOST', 'valkey' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PASSWORD', 'your_password' );
define( 'WP_REDIS_PREFIX', 'wp_sitename' );
define( 'WP_REDIS_DATABASE', 0 );

// Enable WordPress object cache
define( 'WP_CACHE', true );
```

### Cache Prefixes

Each site uses a unique cache prefix based on its database name:
- Domain: `example.com` → Prefix: `wp_example_com:`
- Domain: `my-site.org` → Prefix: `wp_my_site_org:`

This ensures cache isolation between sites.

## Performance Tuning

### Object Cache Best Practices

1. **Monitor hit rates**: Aim for >80% hit rate
   ```bash
   ./scripts/cache-manager.sh stats
   ```

2. **Adjust Valkey memory**: Edit `.env`
   ```bash
   VALKEY_MEM_LIMIT=512m  # Increase if needed
   ```

3. **Use persistent connections**: Already configured in wp-config.php

### Page Cache Best Practices

1. **Warm cache after purges**:
   ```bash
   ./scripts/cache-manager.sh purge example.com
   ./scripts/cache-manager.sh warm example.com
   ```

2. **Exclude dynamic pages**: Configure in WordPress admin → Settings → Cache Enabler

3. **Monitor cache size**:
   ```bash
   ./scripts/cache-manager.sh stats example.com
   ```

### When to Purge Cache

**Always purge after:**
- Theme changes
- Plugin activation/deactivation
- WordPress core updates
- Content updates that affect multiple pages

**Selective purge for:**
- Individual post/page edits
- Comment moderation
- Widget changes

## Troubleshooting

### Cache Not Working

1. **Check plugins are active**:
   ```bash
   ./scripts/cache-manager.sh stats example.com
   ```

2. **Verify Valkey connection**:
   ```bash
   docker exec wpfleet_valkey valkey-cli -a $REDIS_PASSWORD ping
   ```

3. **Check WordPress object cache**:
   ```bash
   ./scripts/wp-cli.sh example.com redis status
   ```

### Cache Not Purging

1. **Manually purge**:
   ```bash
   ./scripts/cache-manager.sh purge example.com
   ```

2. **Check permissions**:
   ```bash
   docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
   ```

### High Memory Usage

1. **Check Valkey memory**:
   ```bash
   ./scripts/cache-manager.sh stats
   ```

2. **Reduce maxmemory**: Edit `docker/valkey/valkey.conf`

3. **Purge old cache**:
   ```bash
   ./scripts/cache-manager.sh purge-all
   ```

### Slow Site After Enabling Cache

1. **Warm the cache**:
   ```bash
   ./scripts/cache-manager.sh warm example.com
   ```

2. **Check cache hit rate**:
   ```bash
   ./scripts/cache-manager.sh stats example.com
   ```

3. **Verify no cache conflicts**: Check for other caching plugins

## Advanced Usage

### Automating Cache Warmup

Add to cron:

```bash
# Warm cache daily at 3 AM
0 3 * * * /path/to/wpfleet/scripts/cache-manager.sh warm example.com
```

### Monitoring Cache Health

```bash
#!/bin/bash
# Monitor cache hit rate and alert if low

STATS=$(./scripts/cache-manager.sh stats)
HIT_RATE=$(echo "$STATS" | grep "hit_rate" | awk '{print $2}' | sed 's/%//')

if (( $(echo "$HIT_RATE < 70" | bc -l) )); then
    echo "Cache hit rate is low: $HIT_RATE%"
    # Send alert...
fi
```

### Programmatic Cache Control

```bash
# In deployment scripts
./scripts/cache-manager.sh purge example.com
./scripts/cache-manager.sh warm example.com
```

## Security Considerations

1. **Password Protection**: Valkey requires authentication (configured via `REDIS_PASSWORD`)

2. **Dangerous Commands Disabled**: FLUSHALL, FLUSHDB, CONFIG, and KEYS commands are disabled in Valkey

3. **Network Isolation**: Valkey is only accessible within the Docker network

4. **Cache Isolation**: Each site has a unique cache prefix

## Performance Benchmarks

Typical performance improvements with caching enabled:

- **Object Cache**: 50-70% reduction in database queries
- **Page Cache**: 80-95% reduction in PHP execution time
- **Combined**: 10-50x faster page load times (depending on site complexity)

## API Reference

The cache-manager.sh script returns exit codes:

- `0`: Success
- `1`: Error (domain not found, Docker not running, etc.)

All output uses colored formatting:
- Green (✓): Success
- Yellow (⚠): Warning
- Red (✗): Error
- Blue: Headers/Information

## Related Documentation

- [Site Management](./site-management.md)
- [Monitoring and Health Checks](./monitoring.md)
- [Backup and Restore](./backup-restore.md)

## Support

For issues or questions:
1. Check WPFleet GitHub issues
2. Review Redis Object Cache plugin documentation
3. Review Cache Enabler plugin documentation
4. Check Valkey logs: `docker logs wpfleet_valkey`
