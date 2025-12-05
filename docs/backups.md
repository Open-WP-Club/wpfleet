# Automated Backups

WPFleet includes a comprehensive automated backup system with scheduling, retention management, and notifications.

## Overview

The backup system provides:
- **Automated scheduling** via cron container
- **Manual backups** for on-demand protection
- **Configurable retention** policies
- **Multiple backup types** (full, site, database)
- **Notification integration** for backup status
- **Easy restoration** process

## Quick Start

### Enable Automated Backups

1. Configure in `.env`:

```env
# Enable automated backups
BACKUP_ENABLED=true
BACKUP_SCHEDULE="0 2 * * *"  # 2 AM daily

# Retention settings
BACKUP_RETENTION_DAYS=7      # Keep backups for 7 days
BACKUP_RETENTION_WEEKLY=4    # Keep 4 weekly backups
BACKUP_RETENTION_MONTHLY=3   # Keep 3 monthly backups
```

2. Start the cron container:

```bash
docker-compose up -d cron
```

3. Verify backups are scheduled:

```bash
docker logs wpfleet_cron
```

### Manual Backups

Create backups on-demand:

```bash
# Backup a specific site
./scripts/backup.sh site example.com

# Backup all sites
./scripts/backup.sh all

# Backup database only
./scripts/backup.sh database example.com

# Backup files only
./scripts/backup.sh files example.com
```

## Backup Types

### Full Site Backup

Backs up both database and files:

```bash
./scripts/backup.sh site example.com
```

Creates:
- `example.com_YYYYMMDD_HHMMSS.sql.gz` - Compressed database
- `example.com_YYYYMMDD_HHMMSS.tar.gz` - Compressed files

### Database Only

```bash
./scripts/backup.sh database example.com
```

Creates:
- `example.com_db_YYYYMMDD_HHMMSS.sql.gz`

### Files Only

```bash
./scripts/backup.sh files example.com
```

Creates:
- `example.com_files_YYYYMMDD_HHMMSS.tar.gz`

### All Sites

Backup all WordPress sites:

```bash
./scripts/backup.sh all
```

Creates separate backup files for each site.

## Backup Storage

Backups are stored in:
```
data/backups/
├── example.com/
│   ├── example.com_20231201_020000.sql.gz
│   ├── example.com_20231201_020000.tar.gz
│   ├── example.com_20231202_020000.sql.gz
│   └── example.com_20231202_020000.tar.gz
└── another-site.com/
    └── ...
```

Each site has its own subdirectory for organized backup management.

## Scheduling

### Cron Schedule Format

The backup schedule uses standard cron syntax:

```
* * * * *
│ │ │ │ │
│ │ │ │ └─ Day of week (0-7, 0 and 7 are Sunday)
│ │ │ └─── Month (1-12)
│ │ └───── Day of month (1-31)
│ └─────── Hour (0-23)
└───────── Minute (0-59)
```

### Common Schedules

```env
# Daily at 2 AM
BACKUP_SCHEDULE="0 2 * * *"

# Every 12 hours
BACKUP_SCHEDULE="0 */12 * * *"

# Weekly on Sunday at 3 AM
BACKUP_SCHEDULE="0 3 * * 0"

# Monthly on the 1st at 4 AM
BACKUP_SCHEDULE="0 4 1 * *"

# Every 6 hours
BACKUP_SCHEDULE="0 */6 * * *"
```

### Custom Cron Jobs

Add custom scheduled tasks in `.env`:

```env
CUSTOM_CRON_JOBS="0 3 * * 0 cd /wpfleet && ./scripts/backup.sh all"
```

Multiple jobs can be added with newlines:

```env
CUSTOM_CRON_JOBS="0 3 * * 0 cd /wpfleet && ./scripts/backup.sh all
0 */6 * * * cd /wpfleet && ./scripts/quota-manager.sh monitor 80"
```

## Retention Management

### Retention Policies

Configure retention in `.env`:

```env
# Keep all backups for this many days
BACKUP_RETENTION_DAYS=7

# After RETENTION_DAYS, keep one weekly backup
BACKUP_RETENTION_WEEKLY=4

# After weekly retention, keep one monthly backup
BACKUP_RETENTION_MONTHLY=3
```

**How it works:**

1. **Daily retention**: All backups are kept for `BACKUP_RETENTION_DAYS` days
2. **Weekly retention**: After daily period, keep one backup per week for `BACKUP_RETENTION_WEEKLY` weeks
3. **Monthly retention**: After weekly period, keep one backup per month for `BACKUP_RETENTION_MONTHLY` months
4. **Automatic cleanup**: Runs based on `BACKUP_CLEANUP_SCHEDULE`

### Manual Cleanup

Remove old backups manually:

```bash
./scripts/backup-cleanup.sh
```

This applies the retention policy to all backup directories.

### Cleanup Schedule

Configure automated cleanup:

```env
BACKUP_CLEANUP_ENABLED=true
BACKUP_CLEANUP_SCHEDULE="0 3 * * 0"  # 3 AM every Sunday
```

## Restoration

### Restore a Site

Use the import functionality to restore:

```bash
# Create new site from backups
./scripts/site-manager.sh add example.com --import-from

# When prompted, provide the backup files:
# Database: data/backups/example.com/example.com_20231201_020000.sql.gz
# Files: data/backups/example.com/example.com_20231201_020000.tar.gz
```

### Restore Database Only

```bash
./scripts/db-manager.sh import example.com data/backups/example.com/example.com_db_20231201_020000.sql.gz
```

### Restore Files Only

```bash
# Extract files to site directory
tar -xzf data/backups/example.com/example.com_files_20231201_020000.tar.gz -C data/wordpress/example.com/

# Fix permissions
docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
```

## Monitoring Backups

### View Backup Logs

```bash
# Cron container logs
docker logs wpfleet_cron

# Backup-specific logs
tail -f data/logs/cron/backup.log

# Cleanup logs
tail -f data/logs/cron/cleanup.log
```

### List Backups

```bash
# List all backups for a site
ls -lh data/backups/example.com/

# Find backups older than 30 days
find data/backups/ -name "*.gz" -mtime +30

# Check total backup size
du -sh data/backups/
```

### Backup Notifications

Automatic notifications are sent for:
- Successful backups
- Failed backups
- Backup cleanup completion
- Low disk space warnings

Configure notifications in [Notifications Guide](./notifications.md).

## Backup to External Storage

### AWS S3

Use the AWS CLI in the cron container:

```bash
# Add to CUSTOM_CRON_JOBS
0 4 * * * aws s3 sync /wpfleet/data/backups/ s3://your-bucket/wpfleet-backups/
```

### SFTP/SCP

Copy backups to remote server:

```bash
# Add to CUSTOM_CRON_JOBS
0 4 * * * scp -r /wpfleet/data/backups/ user@backup-server:/path/to/backups/
```

### Rsync

Sync backups to external location:

```bash
# Add to CUSTOM_CRON_JOBS
0 4 * * * rsync -avz /wpfleet/data/backups/ user@backup-server:/path/to/backups/
```

## Best Practices

1. **Regular testing**: Periodically test backup restoration
2. **Multiple locations**: Store backups in multiple locations
3. **Monitor disk space**: Ensure adequate space for backups
4. **Verify backups**: Check backup logs for errors
5. **Document procedures**: Keep restoration procedures documented
6. **Automate offsite**: Copy backups to external storage
7. **Retention balance**: Balance storage costs with recovery needs

## Troubleshooting

### Backups Not Running

1. Check cron container status:
   ```bash
   docker ps | grep cron
   ```

2. Verify cron configuration:
   ```bash
   docker logs wpfleet_cron
   ```

3. Check backup script permissions:
   ```bash
   ls -l scripts/backup.sh
   ```

### Backup Failures

1. Check disk space:
   ```bash
   df -h
   ```

2. Review error logs:
   ```bash
   tail -f data/logs/cron/backup.log
   ```

3. Test manual backup:
   ```bash
   ./scripts/backup.sh site example.com
   ```

### Restoration Issues

1. Verify backup file integrity:
   ```bash
   # Test database file
   gunzip -t backup.sql.gz

   # Test archive file
   tar -tzf backup.tar.gz | head
   ```

2. Check available disk space:
   ```bash
   df -h data/wordpress/
   ```

3. Verify permissions after restore:
   ```bash
   docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
   ```

### Large Backup Times

1. **Exclude unnecessary files**:
   - Modify backup script to exclude cache directories
   - Skip temporary files

2. **Compress differently**:
   - Use faster compression (gzip -1 instead of gzip -9)
   - Or use pigz for parallel compression

3. **Backup during low-traffic**:
   - Schedule backups during off-peak hours

## Storage Considerations

### Estimating Backup Size

Typical compression ratios:
- **Database**: 10:1 to 20:1 compression
- **Files**: 2:1 to 5:1 compression (varies with media content)

Example: A 2GB site might create:
- Database: 100MB (compressed from 1GB)
- Files: 400MB (compressed from 1GB)
- Total: 500MB per backup

### Storage Requirements

Calculate needed storage:

```
Storage = (Daily backups × Days) + (Weekly backups × Weeks) + (Monthly backups × Months)
Storage = (500MB × 7) + (500MB × 4) + (500MB × 3)
Storage = 3.5GB + 2GB + 1.5GB = 7GB per site
```

## Related Documentation

- [Site Management](./site-management.md)
- [Migration Guide](./migration.md)
- [Notifications](./notifications.md)
- [Monitoring](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)
