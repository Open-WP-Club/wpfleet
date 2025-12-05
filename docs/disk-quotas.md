# Disk Quota Management

Set and monitor per-site disk quotas to prevent one site from consuming all storage.

## Overview

The disk quota system allows you to:
- Set per-site storage limits
- Monitor disk usage in real-time
- Receive alerts when quotas are exceeded
- View detailed usage breakdowns
- Set default quotas for all sites

## Quick Start

### Set Quota for a Site

```bash
./scripts/quota-manager.sh set example.com 10000  # 10GB in MB
```

### Check Site Quota

```bash
./scripts/quota-manager.sh check example.com
```

### Monitor All Sites

```bash
./scripts/quota-manager.sh monitor 80  # Warn at 80% usage
```

## Commands

### Set Quota

Set or update quota for a specific site:

```bash
./scripts/quota-manager.sh set <domain> <quota_in_mb>
```

**Examples:**

```bash
# Set 5GB quota
./scripts/quota-manager.sh set example.com 5000

# Set 20GB quota
./scripts/quota-manager.sh set example.com 20000

# Set 500MB quota
./scripts/quota-manager.sh set example.com 500
```

### Check Quota

Check current usage against quota:

```bash
./scripts/quota-manager.sh check <domain>
```

**Output:**

```
Quota Status for example.com:
  Quota: 10.0 GB
  Used: 3.2 GB (32%)
  Available: 6.8 GB
  Status: OK
```

### Detailed Statistics

View detailed usage breakdown:

```bash
./scripts/quota-manager.sh stats <domain>
```

**Output:**

```
Disk Usage Statistics for example.com:

Total Usage: 3.2 GB / 10.0 GB (32%)

Breakdown by directory:
  wp-content/uploads/  1.8 GB  (56%)
  wp-content/plugins/  0.8 GB  (25%)
  wp-content/themes/   0.4 GB  (12%)
  wp-includes/         0.1 GB  (3%)
  wp-admin/           0.08 GB  (2%)
  Other               0.02 GB  (1%)
```

### List All Quotas

View quotas for all sites:

```bash
./scripts/quota-manager.sh list
```

**Output:**

```
Site Quotas:

example.com
  Quota: 10.0 GB
  Used: 3.2 GB (32%)
  Status: OK

another-site.com
  Quota: 5.0 GB
  Used: 4.2 GB (84%)
  Status: WARNING

test-site.com
  Quota: 2.0 GB
  Used: 2.1 GB (105%)
  Status: EXCEEDED
```

### Monitor All Sites

Monitor all sites and send notifications when thresholds are exceeded:

```bash
./scripts/quota-manager.sh monitor [threshold]
```

**Parameters:**
- `threshold`: Optional percentage (default: 80)

**Examples:**

```bash
# Monitor with default 80% threshold
./scripts/quota-manager.sh monitor

# Monitor with 90% threshold
./scripts/quota-manager.sh monitor 90

# Monitor with 75% threshold
./scripts/quota-manager.sh monitor 75
```

**Notifications sent when:**
- Usage > threshold%: Warning notification
- Usage > 100%: Error notification

### Remove Custom Quota

Remove custom quota and revert to default:

```bash
./scripts/quota-manager.sh remove <domain>
```

The site will use the default quota defined in `.env`.

## Configuration

### Default Quota

Set default quota for all sites in `.env`:

```env
DEFAULT_SITE_QUOTA_MB=5000  # 5GB default
```

This applies to:
- New sites without custom quota
- Sites after removing custom quota

### Automated Monitoring

Add to `.env` for automated quota monitoring:

```env
CUSTOM_CRON_JOBS="0 */6 * * * cd /wpfleet && ./scripts/quota-manager.sh monitor 80"
```

This runs every 6 hours and alerts if any site exceeds 80% of quota.

## Quota Storage

Quotas are stored in:
```
data/quotas/
├── example.com.quota        # Contains quota in MB
├── another-site.com.quota
└── ...
```

Each file contains a single line with the quota in MB.

## Use Cases

### Shared Hosting

Prevent one site from using all disk space:

```bash
# Set quotas for all sites
./scripts/quota-manager.sh set site1.com 5000
./scripts/quota-manager.sh set site2.com 10000
./scripts/quota-manager.sh set site3.com 3000
```

### Client Sites

Set different quotas based on client plans:

```bash
# Basic plan - 2GB
./scripts/quota-manager.sh set basic-client.com 2000

# Pro plan - 10GB
./scripts/quota-manager.sh set pro-client.com 10000

# Enterprise plan - 50GB
./scripts/quota-manager.sh set enterprise-client.com 50000
```

### Development Sites

Use smaller quotas for test sites:

```bash
# Production - 20GB
./scripts/quota-manager.sh set example.com 20000

# Staging - 5GB
./scripts/quota-manager.sh set staging.example.com 5000

# Development - 2GB
./scripts/quota-manager.sh set dev.example.com 2000
```

## Monitoring and Alerts

### Real-Time Monitoring

Check quota status anytime:

```bash
./scripts/quota-manager.sh check example.com
```

### Automated Alerts

Configure in cron for regular checks:

```env
# Check every 6 hours
CUSTOM_CRON_JOBS="0 */6 * * * cd /wpfleet && ./scripts/quota-manager.sh monitor 80"
```

### Notification Thresholds

Automatic notifications are sent at:

- **80% usage**: Warning notification (yellow)
  ```
  ⚠ example.com approaching quota limit
  Used: 8.0 GB / 10.0 GB (80%)
  ```

- **90% usage**: Warning notification (orange)
  ```
  ⚠ example.com approaching quota limit
  Used: 9.0 GB / 10.0 GB (90%)
  ```

- **100% usage**: Error notification (red)
  ```
  ✗ example.com exceeded quota limit
  Used: 10.5 GB / 10.0 GB (105%)
  ```

## Managing Disk Usage

### Find Large Files

Identify large files consuming space:

```bash
# Find files larger than 100MB
find data/wordpress/example.com -type f -size +100M -exec ls -lh {} \;

# Find largest files
find data/wordpress/example.com -type f -exec du -h {} \; | sort -rh | head -20
```

### Clean Up Media Library

Remove unused media files:

```bash
# List media files older than 1 year
find data/wordpress/example.com/wp-content/uploads -type f -mtime +365

# Remove old backup files
find data/wordpress/example.com -name "*.bak" -delete
find data/wordpress/example.com -name "*~" -delete
```

### Optimize Images

Use WordPress plugins or tools to compress images:

```bash
# Install image optimization plugin
./scripts/wp-cli.sh example.com plugin install ewww-image-optimizer --activate

# Bulk optimize existing images
./scripts/wp-cli.sh example.com ewwwio optimize all
```

### Clean Up Revisions

Limit post revisions in `wp-config.php`:

```php
// Limit to 5 revisions
define( 'WP_POST_REVISIONS', 5 );

// Disable revisions
define( 'WP_POST_REVISIONS', false );
```

Clean existing revisions:

```bash
./scripts/wp-cli.sh example.com post delete $(./scripts/wp-cli.sh example.com post list --post_type=revision --format=ids) --force
```

### Database Optimization

Optimize database tables:

```bash
./scripts/wp-cli.sh example.com db optimize
```

Clean up transients:

```bash
./scripts/wp-cli.sh example.com transient delete --all
```

## Quota Enforcement

### Prevention vs Monitoring

WPFleet uses a **monitoring** approach rather than hard enforcement:

- **Monitors** disk usage
- **Alerts** when quotas are exceeded
- **Does not block** writes when quota is exceeded

This prevents site breakage while still providing awareness of overuse.

### Taking Action on Exceeded Quotas

When a site exceeds its quota:

1. **Investigate usage**:
   ```bash
   ./scripts/quota-manager.sh stats example.com
   ```

2. **Clean up if possible**:
   - Remove unused plugins/themes
   - Optimize images
   - Clean up old backups

3. **Increase quota if justified**:
   ```bash
   ./scripts/quota-manager.sh set example.com 15000  # Increase to 15GB
   ```

4. **Contact site owner** if needed

## Best Practices

### 1. Set Appropriate Quotas

Consider site needs:
- **Blog/Content sites**: 2-5GB
- **Business sites**: 5-10GB
- **E-commerce**: 10-20GB
- **Media-heavy sites**: 20-50GB

### 2. Regular Monitoring

Check quotas regularly:

```bash
# Weekly check
./scripts/quota-manager.sh list
```

### 3. Automated Alerts

Always enable automated monitoring:

```env
CUSTOM_CRON_JOBS="0 */6 * * * cd /wpfleet && ./scripts/quota-manager.sh monitor 80"
```

### 4. Document Quotas

Keep records of quota assignments:

```bash
./scripts/quota-manager.sh list > quotas.txt
```

### 5. Growth Planning

Monitor trends:

```bash
# Check monthly to identify growth patterns
./scripts/quota-manager.sh stats example.com
```

## Troubleshooting

### Quota File Missing

If quota file is deleted:

```bash
# Reset quota
./scripts/quota-manager.sh set example.com 5000
```

### Incorrect Usage Reported

Verify actual disk usage:

```bash
# Check actual usage
du -sh data/wordpress/example.com

# Compare with quota report
./scripts/quota-manager.sh check example.com
```

### Notifications Not Sending

1. **Verify notification setup**:
   ```bash
   ./scripts/notify.sh test
   ```

2. **Check webhook URLs** in `.env`

3. **Test quota monitoring**:
   ```bash
   ./scripts/quota-manager.sh monitor 0  # Will alert on any usage
   ```

## Integration

### With Backups

Exclude backup files from quota calculations:

```bash
# Backup files are typically outside WordPress directory
# in data/backups/ so they don't count toward site quotas
```

### With Monitoring Dashboard

Display quota information in monitoring:

```bash
# Add to custom monitoring script
./scripts/quota-manager.sh list
```

### With Billing Systems

Export quota data for billing:

```bash
# Export quota information
./scripts/quota-manager.sh list > /path/to/billing/quotas.txt
```

## API and Automation

### Programmatic Quota Management

Use in scripts:

```bash
#!/bin/bash
# Auto-adjust quotas based on usage

SITES=$(ls data/wordpress/)

for SITE in $SITES; do
    USAGE=$(./scripts/quota-manager.sh check $SITE | grep "Used:" | awk '{print $4}' | tr -d '(%)')

    if [ "$USAGE" -gt 90 ]; then
        # Increase quota by 20%
        CURRENT=$(cat data/quotas/$SITE.quota)
        NEW=$((CURRENT * 120 / 100))
        ./scripts/quota-manager.sh set $SITE $NEW

        ./scripts/notify.sh info "Quota Auto-Adjusted" "Increased $SITE quota to ${NEW}MB"
    fi
done
```

### Export Quota Data

```bash
# Export as JSON
#!/bin/bash
echo "{"
SITES=$(ls data/wordpress/)
FIRST=true

for SITE in $SITES; do
    if [ "$FIRST" = false ]; then
        echo ","
    fi
    FIRST=false

    QUOTA=$(cat data/quotas/$SITE.quota 2>/dev/null || echo "5000")
    USAGE=$(du -sm data/wordpress/$SITE | awk '{print $1}')

    echo "  \"$SITE\": {"
    echo "    \"quota_mb\": $QUOTA,"
    echo "    \"usage_mb\": $USAGE,"
    echo "    \"percent\": $((USAGE * 100 / QUOTA))"
    echo "  }"
done

echo "}"
```

## Related Documentation

- [Site Management](./site-management.md)
- [Monitoring](./monitoring.md)
- [Notifications](./notifications.md)
- [Backups](./backups.md)
- [Troubleshooting](./troubleshooting.md)
