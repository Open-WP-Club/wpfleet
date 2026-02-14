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

## Auto-Scaling Strategies

Automated scaling removes manual intervention by making scaling decisions based on metrics.

### Metrics-Based Decisions

Define thresholds that trigger scaling actions:

| Metric | Scale Up Trigger | Scale Down Trigger | Cool-Down |
|--------|-----------------|-------------------|-----------|
| CPU | >70% for 5 min | <20% for 30 min | 10 min |
| Memory | >80% for 5 min | <40% for 30 min | 10 min |
| Request latency | p95 >2s for 5 min | p95 <200ms for 30 min | 15 min |
| Active connections | >80% of max | <20% of max | 10 min |

**Cool-down periods** prevent rapid scale up/down oscillation. After any scaling event, ignore triggers for the cool-down duration.

### Monitoring Script Integration

Use the existing `health-check.sh` output as a scaling signal:

```bash
#!/bin/bash
# auto-scale-check.sh - Example scaling decision script

CPU_THRESHOLD=70
MEM_THRESHOLD=80
COOLDOWN_FILE="/tmp/wpfleet_scale_cooldown"
COOLDOWN_SECONDS=600

# Check cool-down
if [ -f "$COOLDOWN_FILE" ]; then
    last_scale=$(cat "$COOLDOWN_FILE")
    now=$(date +%s)
    if (( now - last_scale < COOLDOWN_SECONDS )); then
        echo "In cool-down period, skipping"
        exit 0
    fi
fi

# Get current CPU usage from container stats
CPU=$(docker stats wpfleet_frankenphp --no-stream --format "{{.CPUPerc}}" | tr -d '%')
MEM=$(docker stats wpfleet_frankenphp --no-stream --format "{{.MemPerc}}" | tr -d '%')

if (( $(echo "$CPU > $CPU_THRESHOLD" | bc -l) )) || \
   (( $(echo "$MEM > $MEM_THRESHOLD" | bc -l) )); then
    echo "Threshold exceeded: CPU=${CPU}%, MEM=${MEM}%"
    # Trigger your scaling action here
    date +%s > "$COOLDOWN_FILE"
fi
```

## Container Auto-Scaling with Docker

### Scaling the Web Tier with Docker Compose

For stateless web workers, use `docker compose --scale`:

```bash
# Scale FrankenPHP to 3 instances
docker compose up -d --scale frankenphp=3
```

This requires a load balancer in front. Add one to your `docker-compose.yml`:

```yaml
services:
  loadbalancer:
    image: caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/caddy/Caddyfile.lb:/etc/caddy/Caddyfile
    depends_on:
      - frankenphp

  frankenphp:
    # ... existing config ...
    # Remove direct port bindings when using a load balancer
    expose:
      - "443"
```

**Load balancer Caddyfile:**

```
{
    auto_https off
}

:80, :443 {
    reverse_proxy frankenphp:443 {
        lb_policy round_robin
        health_uri /wp-admin/install.php
        health_interval 30s
    }
}
```

### Scaling Limitations

Docker Compose scaling works for stateless services. WPFleet has constraints:

- **WordPress files** must be on shared storage (NFS/GlusterFS) when using multiple web instances
- **Database** is a single instance -- scale via read replicas, not multiple containers
- **Valkey** is a single instance -- use Redis Sentinel or Cluster for HA
- **SSL certificates** must be shared or managed at the load balancer level

## Cloud Provider Auto-Scaling

### AWS Auto Scaling Group

```bash
# Create launch template
aws ec2 create-launch-template \
    --launch-template-name wpfleet-web \
    --launch-template-data '{
        "ImageId": "ami-YOUR-WPFLEET-AMI",
        "InstanceType": "c6i.xlarge",
        "UserData": "'$(base64 -w0 <<'USERDATA'
#!/bin/bash
cd /opt/wpfleet
docker compose up -d
USERDATA
)'"
    }'

# Create Auto Scaling Group
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name wpfleet-asg \
    --launch-template LaunchTemplateName=wpfleet-web,Version='$Latest' \
    --min-size 2 \
    --max-size 10 \
    --desired-capacity 2 \
    --target-group-arns arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/wpfleet/ID

# Create scaling policy (target tracking)
aws autoscaling put-scaling-policy \
    --auto-scaling-group-name wpfleet-asg \
    --policy-name cpu-target-tracking \
    --policy-type TargetTrackingScaling \
    --target-tracking-configuration '{
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "ASGAverageCPUUtilization"
        },
        "TargetValue": 70.0,
        "ScaleInCooldown": 300,
        "ScaleOutCooldown": 60
    }'
```

### DigitalOcean

DigitalOcean doesn't have native auto-scaling groups, but you can script it:

```bash
# Create a new droplet when needed
doctl compute droplet create wpfleet-web-$(date +%s) \
    --image YOUR_SNAPSHOT_ID \
    --size s-4vcpu-8gb \
    --region nyc1 \
    --tag-name wpfleet-web \
    --user-data '#!/bin/bash
cd /opt/wpfleet && docker compose up -d'

# Add to load balancer
doctl compute load-balancer add-droplets YOUR_LB_ID \
    --droplet-ids NEW_DROPLET_ID
```

### Hetzner Cloud

```bash
# Scale using hcloud CLI
hcloud server create \
    --name wpfleet-web-$(date +%s) \
    --type cx31 \
    --image YOUR_SNAPSHOT_ID \
    --location nbg1 \
    --label env=production \
    --label role=web \
    --user-data '#!/bin/bash
cd /opt/wpfleet && docker compose up -d'

# Add to load balancer
hcloud load-balancer add-target YOUR_LB_ID \
    --server NEW_SERVER_NAME
```

## Health-Check Driven Scaling

Integrate WPFleet's existing monitoring with scaling decisions:

```bash
#!/bin/bash
# health-scale.sh - Scale based on health check results

source scripts/lib/utils.sh

# Run health check and capture output
HEALTH_OUTPUT=$(./scripts/health-check.sh 2>&1)

# Parse critical issues
CRITICAL_COUNT=$(echo "$HEALTH_OUTPUT" | grep -c "CRITICAL\|FAIL" || true)
WARNING_COUNT=$(echo "$HEALTH_OUTPUT" | grep -c "WARNING\|WARN" || true)

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    print_error "Critical issues detected ($CRITICAL_COUNT), triggering scale-up"
    # Your scale-up command here
elif [ "$WARNING_COUNT" -gt 2 ]; then
    print_warning "Multiple warnings ($WARNING_COUNT), consider scaling"
    # Send notification via existing notify.sh
    ./scripts/notify.sh "WPFleet: $WARNING_COUNT warnings detected, consider scaling"
fi
```

### Cron Integration

Add health-based scaling checks to the cron schedule:

```env
# In .env
CUSTOM_CRON_JOBS="*/5 * * * * /opt/wpfleet/scripts/health-scale.sh >> /var/log/wpfleet/auto-scale.log 2>&1"
```

## Scale-Down Policies

Scaling down requires care to avoid dropping active requests.

### Safe Scale-Down Procedure

1. **Mark instance for removal** -- stop sending new traffic
2. **Drain connections** -- wait for active requests to complete
3. **Run health check** -- verify remaining instances can handle load
4. **Remove instance** -- terminate the server/container

```bash
#!/bin/bash
# scale-down.sh - Safely remove a web instance

TARGET_SERVER=$1
DRAIN_TIMEOUT=300  # 5 minutes

echo "Draining connections from $TARGET_SERVER..."

# Step 1: Remove from load balancer (stop new traffic)
# Adjust for your LB provider:
# doctl compute load-balancer remove-droplets LB_ID --droplet-ids DROPLET_ID
# hcloud load-balancer remove-target LB_ID --server SERVER_NAME
# aws elbv2 deregister-targets --target-group-arn ARN --targets Id=INSTANCE_ID

# Step 2: Wait for active connections to drain
echo "Waiting ${DRAIN_TIMEOUT}s for connections to drain..."
sleep "$DRAIN_TIMEOUT"

# Step 3: Verify remaining capacity
REMAINING_SERVERS=$(docker compose ps --format json | jq -s 'length')
if [ "$REMAINING_SERVERS" -lt 2 ]; then
    echo "Cannot scale below 2 instances, aborting"
    # Re-add to load balancer
    exit 1
fi

# Step 4: Stop and remove
docker compose stop "$TARGET_SERVER"
echo "Instance $TARGET_SERVER removed"
```

### Connection Draining

When using Caddy as a load balancer, configure health check intervals to detect removed backends:

```
reverse_proxy frankenphp:443 {
    lb_policy round_robin
    health_uri /wp-login.php
    health_interval 10s
    health_timeout 5s
    fail_duration 30s
}
```

Backends that fail health checks are automatically removed from the pool within `fail_duration`.

### Minimum Instance Policy

Always maintain a minimum number of instances for reliability:

- **Production:** minimum 2 instances (for redundancy)
- **Staging:** minimum 1 instance
- **Development:** scale to 0 allowed (cost savings)

## Related Documentation

- [Capacity Planning](./capacity-planning.md)
- [Installation Guide](./installation.md)
- [Monitoring](./monitoring.md)
- [Cache Management](./cache-management.md)
- [Security](./security.md)
- [Troubleshooting](./troubleshooting.md)
