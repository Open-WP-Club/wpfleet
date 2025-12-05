# Site Management

This guide covers managing WordPress sites in WPFleet, including adding, removing, and cloning sites.

## Adding Sites

### Clean WordPress Installation

Create a new WordPress site with default configuration:

```bash
./scripts/site-manager.sh add example.com
```

This creates a fresh installation with:
- Latest WordPress core
- Clean database
- Redis Object Cache plugin (connects to Valkey)
- Optimized configuration
- Admin user with generated password

### Skip Installation (Infrastructure Only)

Create only the infrastructure without installing WordPress:

```bash
./scripts/site-manager.sh add example.com --skip-install
```

Use this when:
- You want to manually install WordPress
- You're migrating a site manually
- You need custom installation procedures

The script will provide database connection information.

### Import Existing Site

Import a WordPress site from backup files:

```bash
./scripts/site-manager.sh add example.com --import-from
```

You'll be prompted for:
- Database backup file (`.sql` or `.sql.gz`)
- Files archive (`.tar.gz` or `.zip`)

See the [Migration Guide](./migration.md) for details.

## Cloning Sites

Clone an existing site for staging, testing, or rapid deployment:

```bash
./scripts/site-manager.sh clone source.com target.com
```

**What it does:**
- Copies all WordPress files
- Clones database with new name
- Updates URLs in database automatically
- Creates new Caddy configuration
- Flushes cache

**Use cases:**
- Create staging environments: `clone example.com staging.example.com`
- Duplicate sites for testing: `clone example.com test.example.com`
- Rapid deployment of similar sites

**Example:**

```bash
# Clone production to staging
./scripts/site-manager.sh clone example.com staging.example.com

# Test changes on staging
# Deploy to production when ready
```

## Removing Sites

Remove a site and all its data:

```bash
./scripts/site-manager.sh remove example.com
```

**Warning:** This permanently deletes:
- WordPress files
- Database
- Caddy configuration
- Backups (optional)

Always backup before removing a site.

## Managing Multiple Sites

### List All Sites

```bash
./scripts/site-manager.sh list
```

Shows all configured sites with their status.

### Restart All Sites

Restart the FrankenPHP container (affects all sites):

```bash
./scripts/site-manager.sh restart
```

Use this when:
- You've made configuration changes
- Sites are not responding
- After updating PHP settings

## Site Configuration

### WordPress Configuration

Each site has its own `wp-config.php` located at:
```
data/wordpress/example.com/wp-config.php
```

WPFleet automatically configures:

```php
// Database settings
define( 'DB_NAME', 'wp_example_com' );
define( 'DB_USER', 'wpfleet' );
define( 'DB_PASSWORD', 'your_password' );
define( 'DB_HOST', 'mariadb' );

// Redis Object Cache (Valkey)
define( 'WP_REDIS_HOST', 'valkey' );
define( 'WP_REDIS_PORT', 6379 );
define( 'WP_REDIS_PASSWORD', 'your_password' );
define( 'WP_REDIS_PREFIX', 'wp_example_com' );
define( 'WP_REDIS_DATABASE', 0 );

// Enable WordPress object cache
define( 'WP_CACHE', true );

// Security keys
// ... (automatically generated)
```

### Caddy Configuration

Each site has a Caddy configuration file:
```
config/caddy/sites/example.com.caddy
```

The configuration includes:
- Automatic HTTPS with Let's Encrypt
- Security headers
- PHP-FPM routing
- Static file handling
- Compression

### File Structure

Each site's files are organized as:

```
data/wordpress/example.com/
├── wp-admin/
├── wp-content/
│   ├── plugins/
│   ├── themes/
│   └── uploads/
├── wp-includes/
├── wp-config.php
└── index.php
```

## Using WP-CLI

Execute WordPress CLI commands on any site:

```bash
./scripts/wp-cli.sh example.com <command>
```

**Common commands:**

```bash
# Update WordPress core
./scripts/wp-cli.sh example.com core update

# List plugins
./scripts/wp-cli.sh example.com plugin list

# Install and activate a plugin
./scripts/wp-cli.sh example.com plugin install contact-form-7 --activate

# Update all plugins
./scripts/wp-cli.sh example.com plugin update --all

# List themes
./scripts/wp-cli.sh example.com theme list

# Activate a theme
./scripts/wp-cli.sh example.com theme activate twentytwentyfour

# Export database
./scripts/wp-cli.sh example.com db export backup.sql

# Search and replace URLs
./scripts/wp-cli.sh example.com search-replace 'http://old.com' 'https://new.com'

# Create a user
./scripts/wp-cli.sh example.com user create newuser user@example.com --role=editor

# Flush rewrite rules
./scripts/wp-cli.sh example.com rewrite flush

# Clear cache
./scripts/wp-cli.sh example.com cache flush
```

See [WP-CLI documentation](https://wp-cli.org/commands/) for all available commands.

## Database Management

### Accessing the Database

From the host machine:

```bash
docker exec -it wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD}
```

Then select your database:

```sql
USE wp_example_com;
SHOW TABLES;
```

### Database Operations

**Export database:**

```bash
./scripts/db-manager.sh export example.com backup.sql
```

**Import database:**

```bash
./scripts/db-manager.sh import example.com backup.sql
```

**Search and replace:**

```bash
./scripts/db-manager.sh search-replace example.com 'old-value' 'new-value'
```

### Database Naming Convention

Databases are named using the pattern:
```
wp_<domain_with_underscores>
```

Examples:
- `example.com` → `wp_example_com`
- `my-site.org` → `wp_my_site_org`
- `blog.example.com` → `wp_blog_example_com`

## Resource Management

### Setting Resource Limits

Configure in `.env`:

```env
# CPU and memory limits for FrankenPHP
FRANKENPHP_CPU_LIMIT=2.0
FRANKENPHP_MEM_LIMIT=2g

# MariaDB limits
MYSQL_CPU_LIMIT=2.0
MYSQL_MEM_LIMIT=1g

# Valkey limits
REDIS_CPU_LIMIT=1.0
REDIS_MAXMEMORY=256mb
```

### Disk Quotas

Set per-site disk quotas to prevent one site from consuming all storage:

```bash
./scripts/quota-manager.sh set example.com 10000  # 10GB
```

See [Disk Quotas](./disk-quotas.md) for details.

## Site Access Information

### Finding Site Credentials

After creating a site, credentials are displayed in the terminal. You can also find them:

**Admin credentials:**
- Stored in site creation logs
- Reset with WP-CLI:
  ```bash
  ./scripts/wp-cli.sh example.com user update admin --user_pass=newpassword
  ```

**Database credentials:**
- Database name: Check `wp-config.php`
- User: `wpfleet` (default)
- Password: `MYSQL_PASSWORD` from `.env`
- Host: `mariadb` (from containers) or `localhost:3306` (from host via tunnel)

## Troubleshooting

### Site Not Accessible

1. Check if FrankenPHP is running:
   ```bash
   docker ps | grep frankenphp
   ```

2. Check Caddy logs:
   ```bash
   docker logs wpfleet_frankenphp | tail -50
   ```

3. Verify site directory exists:
   ```bash
   ls -la data/wordpress/example.com
   ```

4. Check Caddy configuration:
   ```bash
   cat config/caddy/sites/example.com.caddy
   ```

### Database Connection Errors

1. Verify database exists:
   ```bash
   docker exec wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "SHOW DATABASES;" | grep wp_
   ```

2. Check credentials in `wp-config.php`

3. Test database connection:
   ```bash
   docker exec wpfleet_mariadb mysql -uwpfleet -p${MYSQL_PASSWORD} -e "SELECT 1;"
   ```

### Permission Issues

Fix file permissions:

```bash
docker exec wpfleet_frankenphp chown -R www-data:www-data /var/www/html/example.com
```

### Site Shows White Screen

1. Enable WordPress debugging:
   ```bash
   # Edit wp-config.php
   define( 'WP_DEBUG', true );
   define( 'WP_DEBUG_LOG', true );
   define( 'WP_DEBUG_DISPLAY', false );
   ```

2. Check error logs:
   ```bash
   tail -f data/wordpress/example.com/wp-content/debug.log
   ```

## Best Practices

1. **Use descriptive domain names** for easier management
2. **Clone before making major changes** to create a safety net
3. **Regular backups** before updates or changes
4. **Monitor disk usage** with quotas
5. **Test on staging** before deploying to production
6. **Keep WordPress core and plugins updated**
7. **Use strong passwords** for admin accounts
8. **Enable caching** for better performance

## Related Documentation

- [Installation Guide](./installation.md)
- [Migration Guide](./migration.md)
- [Backups](./backups.md)
- [Cache Management](./cache-management.md)
- [Git Deployments](./git-deployments.md)
- [Disk Quotas](./disk-quotas.md)
- [Monitoring](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)
