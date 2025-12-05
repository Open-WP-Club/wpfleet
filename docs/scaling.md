# Scaling Guide

This guide covers scaling WPFleet for increased traffic and site capacity.

## Overview

WPFleet can scale in two ways:
- **Vertical Scaling:** Increasing resources on a single server
- **Horizontal Scaling:** Distributing load across multiple servers

## Vertical Scaling

Vertical scaling involves increasing the resources available to your WPFleet server.

### Increase Container Resources

Configure resource limits in `.env`:

```env
# FrankenPHP resources
FRANKENPHP_CPU_LIMIT=4.0        # 4 CPU cores
FRANKENPHP_MEM_LIMIT=8g         # 8GB memory

# MariaDB resources
MYSQL_CPU_LIMIT=2.0             # 2 CPU cores
MYSQL_MEM_LIMIT=4g              # 4GB memory

# Valkey resources
REDIS_CPU_LIMIT=2.0             # 2 CPU cores
REDIS_MAXMEMORY=2gb             # 2GB memory
```

Apply changes:

```bash
docker-compose up -d
```

### Tune MariaDB

Optimize MariaDB for your server's memory:

**For 8GB server:**

```env
MYSQL_MEM_LIMIT=2g
```

**For 16GB server:**

```env
MYSQL_MEM_LIMIT=4g
```

**For 32GB+ server:**

```env
MYSQL_MEM_LIMIT=8g
```

Configure in `docker/mariadb/my.cnf`:

```ini
[mysqld]
# InnoDB buffer pool (50-70% of MySQL memory)
innodb_buffer_pool_size = 2G

# Connection settings
max_connections = 200

# Query cache
query_cache_type = 1
query_cache_size = 64M

# Temp table sizes
tmp_table_size = 64M
max_heap_table_size = 64M
```

### Tune Valkey

Increase Valkey memory in `.env`:

```env
# For high-traffic sites
REDIS_MAXMEMORY=4gb
```

Configure in `docker/valkey/valkey.conf`:

```conf
maxmemory 4gb
maxmemory-policy allkeys-lru

# Connection settings
maxclients 10000

# Performance tuning
tcp-backlog 511
```

### Optimize PHP

Configure PHP settings in `config/php/php.ini`:

```ini
; Memory
memory_limit = 512M
max_execution_time = 300

; OPcache (already optimized in FrankenPHP)
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60

; File uploads
upload_max_filesize = 128M
post_max_size = 128M
```

## Horizontal Scaling

For high-traffic setups, distribute load across multiple servers.

### Architecture Options

#### Option 1: Separate Database Server

Move MariaDB to dedicated server:

**Database Server (db.example.com):**

```yaml
version: '3.8'
services:
  mariadb:
    image: mariadb:11
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
    ports:
      - "3306:3306"
```

**Web Servers (web1.example.com, web2.example.com):**

Update `.env` on web servers:

```env
DB_HOST=db.example.com
```

#### Option 2: Separate Cache Server

Move Valkey to dedicated server:

**Cache Server (cache.example.com):**

```yaml
version: '3.8'
services:
  valkey:
    image: valkey/valkey:latest
    ports:
      - "6379:6379"
```

**Web Servers:**

Update `wp-config.php`:

```php
define( 'WP_REDIS_HOST', 'cache.example.com' );
```

#### Option 3: Multiple Web Servers with Load Balancer

**Load Balancer (Nginx):**

```nginx
upstream wpfleet_backend {
    least_conn;
    server web1.example.com:443;
    server web2.example.com:443;
    server web3.example.com:443;
}

server {
    listen 80;
    listen 443 ssl http2;
    server_name *.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass https://wpfleet_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Web Servers:**

Each runs WPFleet with shared storage (NFS, GlusterFS, or object storage).

### Shared Storage

Use shared storage for WordPress files across multiple servers.

#### NFS Setup

**NFS Server:**

```bash
# Install NFS
sudo apt-get install nfs-kernel-server

# Configure exports
sudo nano /etc/exports
```

Add:

```
/data/wordpress *(rw,sync,no_subtree_check,no_root_squash)
```

**NFS Clients (Web Servers):**

```bash
# Install NFS client
sudo apt-get install nfs-common

# Mount NFS share
sudo mount nfs-server:/data/wordpress /path/to/wpfleet/data/wordpress

# Add to /etc/fstab for persistence
nfs-server:/data/wordpress /path/to/wpfleet/data/wordpress nfs defaults 0 0
```

#### Object Storage (S3)

Use S3-compatible object storage for media files:

**Install WP Offload Media plugin:**

```bash
./scripts/wp-cli.sh example.com plugin install amazon-s3-and-cloudfront --activate
```

**Configure via WP-CLI:**

```bash
./scripts/wp-cli.sh example.com option update tantan_wordpress_s3 '{"provider":"aws","access-key-id":"YOUR_KEY","secret-access-key":"YOUR_SECRET","bucket":"your-bucket","region":"us-east-1"}'
```

## Content Delivery Network (CDN)

Use a CDN to offload static content delivery.

### Cloudflare Setup

1. **Add site to Cloudflare**
2. **Update nameservers**
3. **Configure settings:**
   - SSL/TLS: Full (strict)
   - Auto Minify: Enable for HTML, CSS, JS
   - Brotli: Enable
   - HTTP/2: Enable
   - HTTP/3: Enable

### AWS CloudFront

**Create distribution:**

```bash
aws cloudfront create-distribution \
    --origin-domain-name example.com \
    --default-root-object index.php
```

**WordPress configuration:**

Install CDN Enabler plugin:

```bash
./scripts/wp-cli.sh example.com plugin install cdn-enabler --activate
```

Configure CDN URL:

```bash
./scripts/wp-cli.sh example.com option update cdn_enabler_url 'https://d111111abcdef8.cloudfront.net'
```

## Database Optimization

### Read Replicas

Set up MariaDB read replicas for read-heavy workloads.

**Primary Database:**

Configure in `my.cnf`:

```ini
[mysqld]
server-id = 1
log_bin = /var/log/mysql/mysql-bin.log
binlog_do_db = wp_example_com
```

**Replica Database:**

```ini
[mysqld]
server-id = 2
relay-log = /var/log/mysql/mysql-relay-bin
log_bin = /var/log/mysql/mysql-bin.log
read_only = 1
```

**Configure replication:**

```sql
-- On primary
CREATE USER 'replicator'@'%' IDENTIFIED BY 'password';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

-- On replica
CHANGE MASTER TO
    MASTER_HOST='primary.example.com',
    MASTER_USER='replicator',
    MASTER_PASSWORD='password',
    MASTER_LOG_FILE='mysql-bin.000001',
    MASTER_LOG_POS=0;

START SLAVE;
```

**WordPress configuration:**

Use HyperDB plugin for read/write splitting:

```bash
./scripts/wp-cli.sh example.com plugin install hyperdb --activate
```

### Database Sharding

Split databases across multiple servers by site:

**Sites 1-100:** db1.example.com
**Sites 101-200:** db2.example.com
**Sites 201-300:** db3.example.com

Configure each site's `wp-config.php` accordingly.

## Caching Strategy

### Multi-Tier Caching

Implement multiple caching layers:

1. **Browser Cache** - Via cache headers
2. **CDN Cache** - Cloudflare, CloudFront
3. **Full-Page Cache** - Cache Enabler
4. **Object Cache** - Valkey/Redis
5. **OPcache** - PHP opcode cache

### Varnish Cache

Add Varnish as reverse proxy:

```yaml
version: '3.8'
services:
  varnish:
    image: varnish:latest
    ports:
      - "80:80"
    environment:
      - VARNISH_SIZE=2G
    volumes:
      - ./config/varnish/default.vcl:/etc/varnish/default.vcl
```

**Varnish configuration (`default.vcl`):**

```vcl
vcl 4.0;

backend default {
    .host = "frankenphp";
    .port = "8080";
}

sub vcl_recv {
    # Don't cache WordPress admin
    if (req.url ~ "^/wp-(admin|login)") {
        return (pass);
    }

    # Don't cache logged-in users
    if (req.http.Cookie ~ "wordpress_logged_in") {
        return (pass);
    }

    return (hash);
}

sub vcl_backend_response {
    # Cache for 1 hour
    set beresp.ttl = 1h;
}
```

## Load Balancing Strategies

### DNS Round Robin

Simple load balancing via DNS:

```
example.com    A    192.168.1.10    # Web1
example.com    A    192.168.1.11    # Web2
example.com    A    192.168.1.12    # Web3
```

### HAProxy

Advanced load balancing:

**Install HAProxy:**

```bash
sudo apt-get install haproxy
```

**Configure (`/etc/haproxy/haproxy.cfg`):**

```
frontend http_front
    bind *:80
    bind *:443 ssl crt /etc/haproxy/certs/
    default_backend http_back

backend http_back
    balance roundrobin
    option httpchk HEAD / HTTP/1.1\r\nHost:\ example.com
    server web1 192.168.1.10:443 check ssl verify none
    server web2 192.168.1.11:443 check ssl verify none
    server web3 192.168.1.12:443 check ssl verify none
```

## Performance Benchmarking

### Baseline Metrics

Establish performance baselines:

```bash
# Using Apache Bench
ab -n 1000 -c 10 https://example.com/

# Using WP-CLI
./scripts/wp-cli.sh example.com profile command --warmup --iterations=10
```

### Load Testing

Test under load:

```bash
# Install k6
sudo apt-get install k6

# Create load test script
cat > loadtest.js <<EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
    stages: [
        { duration: '2m', target: 100 }, // Ramp up to 100 users
        { duration: '5m', target: 100 }, // Stay at 100 users
        { duration: '2m', target: 0 },   // Ramp down
    ],
};

export default function () {
    let response = http.get('https://example.com');
    check(response, {
        'status is 200': (r) => r.status === 200,
        'response time < 500ms': (r) => r.timings.duration < 500,
    });
    sleep(1);
}
EOF

# Run load test
k6 run loadtest.js
```

## Monitoring at Scale

### Centralized Logging

Use ELK stack (Elasticsearch, Logstash, Kibana):

```yaml
version: '3.8'
services:
  elasticsearch:
    image: elasticsearch:8.10.0
    environment:
      - discovery.type=single-node

  logstash:
    image: logstash:8.10.0
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf

  kibana:
    image: kibana:8.10.0
    ports:
      - "5601:5601"
```

### Metrics Collection

Use Prometheus + Grafana:

```yaml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
```

## Cost Optimization

### Resource Right-Sizing

Monitor and adjust resources:

```bash
# Check actual usage
docker stats

# Reduce if underutilized
# Increase if hitting limits
```

### Spot Instances / Preemptible VMs

Use cheaper cloud instances for non-critical workloads:
- Development servers
- Staging environments
- Backup servers

### Reserved Instances

Commit to long-term instances for discounts:
- 1-year: ~30% discount
- 3-year: ~60% discount

## Scaling Checklist

- [ ] Monitor current resource usage
- [ ] Identify bottlenecks (CPU, memory, disk, network)
- [ ] Optimize current setup before scaling
- [ ] Enable full caching (page + object)
- [ ] Use CDN for static assets
- [ ] Optimize database queries
- [ ] Consider vertical scaling first
- [ ] Plan horizontal scaling architecture
- [ ] Implement shared storage if needed
- [ ] Set up load balancer
- [ ] Configure database replication
- [ ] Implement centralized logging
- [ ] Set up comprehensive monitoring
- [ ] Load test new configuration
- [ ] Document scaling procedures
- [ ] Plan for failover and redundancy

## Related Documentation

- [Installation Guide](./installation.md)
- [Monitoring](./monitoring.md)
- [Cache Management](./cache-management.md)
- [Security](./security.md)
- [Troubleshooting](./troubleshooting.md)
