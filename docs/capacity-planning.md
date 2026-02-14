# Capacity Planning

This guide helps you estimate resource requirements, plan server sizing, and know when to scale your WPFleet deployment.

## Resource Requirements per Site

Baseline resource consumption for a typical WordPress site running on WPFleet:

| Resource | Idle | Light Traffic (100 req/min) | Heavy Traffic (1000 req/min) |
|----------|------|----------------------------|------------------------------|
| RAM | ~50MB | ~100-200MB | ~300-500MB |
| CPU | <1% | 5-10% of 1 core | 20-50% of 1 core |
| Disk (WP core) | ~60MB | ~60MB | ~60MB |
| Disk (content) | ~500MB-2GB | ~500MB-2GB | ~500MB-2GB |
| DB size | ~20MB | ~50-200MB | ~200MB-1GB |

**Notes:**
- FrankenPHP shares a single process across all sites, so per-site RAM overhead is lower than traditional PHP-FPM setups.
- Object cache (Valkey) typically uses 10-50MB per site depending on plugin count and data.
- These are estimates -- actual usage varies significantly with themes, plugins, and content.

## Server Sizing Guide

Recommended specifications for different site counts:

### 5 Sites (Starter)

| Component | Specification |
|-----------|--------------|
| CPU | 2 cores |
| RAM | 4GB |
| Disk | 40GB SSD |
| `.env` settings | `FRANKENPHP_MEM_LIMIT=1g`, `FRANKENPHP_CPU_LIMIT=1.5` |
| MariaDB | Default settings |
| Valkey | `REDIS_MAXMEMORY=256mb` |

### 10 Sites (Small)

| Component | Specification |
|-----------|--------------|
| CPU | 4 cores |
| RAM | 8GB |
| Disk | 80GB SSD |
| `.env` settings | `FRANKENPHP_MEM_LIMIT=3g`, `FRANKENPHP_CPU_LIMIT=3` |
| MariaDB | `MYSQL_MEM_LIMIT=2g` |
| Valkey | `REDIS_MAXMEMORY=512mb` |

### 25 Sites (Medium)

| Component | Specification |
|-----------|--------------|
| CPU | 8 cores |
| RAM | 16GB |
| Disk | 200GB SSD |
| `.env` settings | `FRANKENPHP_MEM_LIMIT=6g`, `FRANKENPHP_CPU_LIMIT=6` |
| MariaDB | `MYSQL_MEM_LIMIT=4g` |
| Valkey | `REDIS_MAXMEMORY=1gb` |

### 50 Sites (Large)

| Component | Specification |
|-----------|--------------|
| CPU | 16 cores |
| RAM | 32GB |
| Disk | 500GB SSD |
| `.env` settings | `FRANKENPHP_MEM_LIMIT=12g`, `FRANKENPHP_CPU_LIMIT=12` |
| MariaDB | `MYSQL_MEM_LIMIT=8g` |
| Valkey | `REDIS_MAXMEMORY=2gb` |

### 100 Sites (Enterprise)

| Component | Specification |
|-----------|--------------|
| CPU | 32 cores |
| RAM | 64GB |
| Disk | 1TB NVMe SSD |
| `.env` settings | `FRANKENPHP_MEM_LIMIT=24g`, `FRANKENPHP_CPU_LIMIT=24` |
| MariaDB | Separate server recommended |
| Valkey | Separate server, `REDIS_MAXMEMORY=4gb` |

At 100+ sites, consider horizontal scaling (see [Scaling Guide](./scaling.md)).

## Monitoring Capacity

Use the existing `health-check.sh` to track resource utilization:

```bash
# Run a one-time health check
./scripts/health-check.sh

# Check container resource usage
docker stats --no-stream

# Check disk usage per site
du -sh data/wordpress/*/

# Check database sizes
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "
    SELECT table_schema AS 'Database',
           ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    GROUP BY table_schema
    ORDER BY SUM(data_length + index_length) DESC;
"
```

### Key Metrics to Watch

| Metric | Tool | Warning | Critical |
|--------|------|---------|----------|
| CPU usage | `docker stats` | >70% sustained | >90% sustained |
| Memory usage | `docker stats` | >80% | >90% |
| Disk usage | `df -h` | >75% | >90% |
| DB connections | MariaDB status | >80% of max | >95% of max |
| Response time | `health-check.sh` | >1s average | >3s average |
| PHP errors | `data/logs/*/error.log` | >10/hour | >100/hour |

## Disk Space Planning

### WordPress Installation Sizes

| Component | Typical Size |
|-----------|-------------|
| WordPress core | 60MB |
| Average theme | 5-20MB |
| Plugins (10 average) | 50-200MB |
| Media uploads (first year) | 500MB-5GB |
| Database (first year) | 50-500MB |

### Growth Rates

- **Media uploads:** 50-200MB/month for active content sites
- **Database:** 5-20MB/month for typical sites, more for WooCommerce
- **Logs:** 10-50MB/month per site (Caddy access logs are rotated at 100MB)
- **Backups:** 1x site size per backup, retained per `BACKUP_RETENTION_DAYS`

### Disk Budget Formula

Estimate total disk needed:

```
Total = (sites x avg_site_size) + (sites x avg_db_size) + backup_storage + overhead

Where:
  avg_site_size  = 1-2GB (WordPress + uploads)
  avg_db_size    = 100-500MB
  backup_storage = sites x avg_site_size x backup_retention_copies
  overhead       = 20% of total (logs, temp files, Docker images)
```

**Example for 25 sites:**
```
Sites:   25 x 1.5GB = 37.5GB
DB:      25 x 200MB = 5GB
Backups: 25 x 1.5GB x 7 copies = 262.5GB
Overhead: 20% = 61GB
Total:   ~366GB -> provision 500GB
```

## When to Scale

### Scale Up (Vertical) When:

- **CPU >70% sustained** for more than 30 minutes -- add more CPU cores
- **Memory >80%** -- increase container memory limits or server RAM
- **Disk >75%** -- expand storage or clean up old backups/logs
- **Response time >1 second** average -- check bottleneck (CPU, DB, or disk I/O)
- **Database connections near max** -- increase `max_connections` or add replicas

### Scale Out (Horizontal) When:

- Vertical scaling hits provider limits (largest available instance)
- Single-server reliability is insufficient (need redundancy)
- Geographic distribution is needed (multi-region)
- 50+ high-traffic sites on a single server

### Scale Down When:

- CPU <20% sustained during peak hours
- Memory <40% during peak hours
- Costs exceed budget and traffic doesn't justify current sizing

## Capacity Estimation Commands

Quick commands to assess your current capacity:

```bash
# Overall system resources
free -h && echo "---" && nproc && echo "---" && df -h /

# Container resource usage (snapshot)
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

# Count total sites
ls -d data/wordpress/*/ 2>/dev/null | wc -l

# Largest sites by disk
du -sh data/wordpress/*/ 2>/dev/null | sort -rh | head -10

# Largest databases
docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -N -e "
    SELECT table_schema, ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
    FROM information_schema.tables
    WHERE table_schema LIKE 'wp_%'
    GROUP BY table_schema
    ORDER BY SUM(data_length + index_length) DESC
    LIMIT 10;
"

# Estimate remaining capacity (rough)
echo "=== Capacity Estimate ==="
TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
USED_MEM=$(free -m | awk '/^Mem:/{print $3}')
SITE_COUNT=$(ls -d data/wordpress/*/ 2>/dev/null | wc -l)
AVG_MEM_PER_SITE=$((USED_MEM / (SITE_COUNT > 0 ? SITE_COUNT : 1)))
REMAINING_MEM=$((TOTAL_MEM - USED_MEM))
ESTIMATED_CAPACITY=$((REMAINING_MEM / (AVG_MEM_PER_SITE > 0 ? AVG_MEM_PER_SITE : 200)))
echo "Current sites: $SITE_COUNT"
echo "Avg memory per site: ~${AVG_MEM_PER_SITE}MB"
echo "Remaining memory: ${REMAINING_MEM}MB"
echo "Estimated additional capacity: ~${ESTIMATED_CAPACITY} sites"
```

## Related Documentation

- [Scaling Guide](./scaling.md)
- [Monitoring](./monitoring.md)
- [Installation Guide](./installation.md)
