# Migration Guide

This guide covers migrating existing WordPress sites to WPFleet.

## Overview

WPFleet makes it easy to migrate WordPress sites from other hosting platforms or between WPFleet installations. The migration process preserves your content, database, themes, plugins, and settings.

## Migrating from Another Host

### Step 1: Prepare Your Existing Site

On your current server, export the database and create an archive of WordPress files:

```bash
# Export database
mysqldump -u username -p database_name > site_backup.sql

# Or export with gzip compression
mysqldump -u username -p database_name | gzip > site_backup.sql.gz

# Create archive of WordPress files
tar -czf site_files.tar.gz /path/to/wordpress/

# Or create zip archive
zip -r site_files.zip /path/to/wordpress/
```

### Step 2: Transfer Files to WPFleet Server

Copy both files to your WPFleet server:

```bash
scp site_backup.sql site_files.tar.gz user@wpfleet-server:/path/to/wpfleet/
```

### Step 3: Import to WPFleet

Run the import command:

```bash
./scripts/site-manager.sh add yourdomain.com --import-from
```

When prompted:
- **Database file**: `./site_backup.sql` or `./site_backup.sql.gz`
- **Files archive**: `./site_files.tar.gz` or `./site_files.zip`

The script will:
1. Create the site infrastructure
2. Import your database
3. Extract WordPress files
4. Update database connection settings
5. Configure caching

### Step 4: Update DNS

Point your domain to the new WPFleet server:

1. Update your DNS A record to point to the new server IP
2. Wait for DNS propagation (usually 5-60 minutes)
3. WPFleet will automatically obtain SSL certificates from Let's Encrypt

### Step 5: Verify the Migration

1. Visit your site at `https://yourdomain.com`
2. Test login functionality
3. Check that all pages load correctly
4. Verify media files are accessible
5. Test any custom functionality

## Migrating Between WPFleet Sites

Use the built-in backup and clone functionality:

### Using Backup and Restore

```bash
# Export from existing site
./scripts/backup.sh site olddomain.com

# Import to new site
./scripts/site-manager.sh add newdomain.com --import-from
# Use the backup files from the previous step
```

### Using Site Cloning

For creating staging or test environments:

```bash
./scripts/site-manager.sh clone source.com target.com
```

This automatically:
- Copies all files
- Clones database
- Updates URLs
- Configures routing

See [Site Management](./site-management.md#cloning-sites) for details.

## URL Search and Replace

If you need to change URLs after migration (e.g., moving from `http://` to `https://` or changing domain names):

```bash
./scripts/db-manager.sh search-replace yourdomain.com 'http://olddomain.com' 'https://newdomain.com'
```

**Important Notes:**
- Always backup before running search-replace
- Include the protocol (http:// or https://)
- Use single quotes to prevent shell interpretation
- Test thoroughly after replacing URLs

## Common Migration Scenarios

### HTTP to HTTPS

```bash
./scripts/db-manager.sh search-replace yourdomain.com 'http://yourdomain.com' 'https://yourdomain.com'
```

### Different Domain Name

```bash
./scripts/db-manager.sh search-replace newdomain.com 'http://olddomain.com' 'https://newdomain.com'
```

### Subdomain to Root Domain

```bash
./scripts/db-manager.sh search-replace newdomain.com 'https://blog.olddomain.com' 'https://newdomain.com'
```

## Migration Checklist

Use this checklist to ensure a smooth migration:

- [ ] Export database from old server
- [ ] Create archive of WordPress files
- [ ] Transfer files to WPFleet server
- [ ] Run import command with correct file paths
- [ ] Verify all files were extracted correctly
- [ ] Check database connection is working
- [ ] Run URL search-replace if needed
- [ ] Update DNS records
- [ ] Wait for SSL certificate issuance
- [ ] Test site functionality
- [ ] Verify media uploads work
- [ ] Check contact forms and plugins
- [ ] Test admin login
- [ ] Enable caching for performance
- [ ] Set up automated backups
- [ ] Configure monitoring and notifications

## Troubleshooting Migration Issues

### Database Import Fails

**Error:** Large database timeout

```bash
# Manually import large databases
docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} wp_yourdomain_com < site_backup.sql
```

### Files Not Extracting

**Error:** Permissions or corrupted archive

```bash
# Check archive integrity
tar -tzf site_files.tar.gz | head
# or for zip
unzip -l site_files.zip | head

# Manually extract if needed
mkdir -p data/wordpress/yourdomain.com
tar -xzf site_files.tar.gz -C data/wordpress/yourdomain.com
```

### Site Shows Old URLs

Run the URL search-replace:

```bash
./scripts/db-manager.sh search-replace yourdomain.com 'http://old.com' 'https://new.com'
```

### Missing Media Files

Ensure media files were included in the archive:

```bash
# Check if wp-content/uploads exists
ls -la data/wordpress/yourdomain.com/wp-content/uploads/
```

### Permission Errors

Fix file permissions:

```bash
docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/yourdomain.com
```

## Post-Migration Optimization

After successful migration:

1. **Enable Caching:**
   ```bash
   ./scripts/cache-manager.sh setup yourdomain.com
   ```

2. **Set Up Backups:**
   ```bash
   # Configure in .env
   BACKUP_ENABLED=true
   BACKUP_SCHEDULE="0 2 * * *"
   docker-compose up -d cron
   ```

3. **Configure Notifications:**
   ```bash
   # Add webhooks to .env
   DISCORD_WEBHOOK_URL=your_webhook_url
   ./scripts/notify.sh test
   ```

4. **Set Disk Quota:**
   ```bash
   ./scripts/quota-manager.sh set yourdomain.com 10000  # 10GB
   ```

## Migration Time Estimates

Typical migration times (depends on site size and connection speed):

- **Small site** (< 500MB): 5-10 minutes
- **Medium site** (500MB - 5GB): 15-30 minutes
- **Large site** (5GB+): 30-60+ minutes

Database import speed: ~50-100MB per minute
File transfer speed: Depends on network bandwidth

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting Guide](./troubleshooting.md)
2. Review migration logs in `data/logs/`
3. Verify DNS settings with `dig yourdomain.com`
4. Check SSL certificate status with `./scripts/ssl-monitor.sh`
5. Open an issue on GitHub with detailed information

## Related Documentation

- [Installation Guide](./installation.md)
- [Site Management](./site-management.md)
- [Backups](./backups.md)
- [Troubleshooting](./troubleshooting.md)
