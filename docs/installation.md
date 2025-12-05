# Installation Guide

This guide covers installing and configuring WPFleet for hosting multiple WordPress sites.

## Requirements

- Docker Engine 20.10+
- Docker Compose 2.0+
- Linux server (Ubuntu 20.04+ recommended)
- Domain names pointing to your server
- Ports 80 and 443 available
- Minimum 2GB RAM (4GB+ recommended)
- SSH access for management

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Open-WP-Club/wpfleet
cd wpfleet
```

### 2. Configure Environment

```bash
cp .env.example .env
nano .env  # Edit with your values
```

**Important**: Generate secure passwords for `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, and `WP_ADMIN_PASSWORD`.

### 3. Make Scripts Executable

```bash
chmod +x scripts/*.sh
```

### 4. Start Core Services

```bash
docker-compose up -d mariadb valkey
```

### 5. Add Your First Site

Choose from three installation modes:

**Clean WordPress Installation (default)**

```bash
./scripts/site-manager.sh add example.com
```

**Skip Installation (infrastructure only)**

```bash
./scripts/site-manager.sh add example.com --skip-install
```

**Import Existing Site**

```bash
./scripts/site-manager.sh add example.com --import-from
```

## Installation Modes

WPFleet supports three different ways to add WordPress sites:

### Clean Installation (Default)

```bash
./scripts/site-manager.sh add example.com
```

**Best for:** New WordPress sites from scratch

**What it does:**

- Downloads latest WordPress core
- Creates fresh database
- Installs and configures Redis Object Cache (connects to Valkey)
- Sets up optimized `wp-config.php`
- Creates admin user with generated password
- Applies security and performance settings

### Skip Installation

```bash
./scripts/site-manager.sh add example.com --skip-install
```

**Best for:** Custom installations, advanced users, or manual migrations

**What it does:**

- Creates database and file directories
- Sets up Caddy routing and SSL
- Shows database connection information
- **You handle:** WordPress installation, configuration, file uploads

**Output example:**

```
Database Information:
  Database Name: wp_example_com
  Database User: wpfleet
  Database Password: your_password
  Database Host: mariadb (or localhost:3306 from host)

Site Information:
  Files Directory: /path/to/wpfleet/data/wordpress/example.com
  Container Path: /var/www/html/example.com
  Site URL: https://example.com
```

### Import Existing Site

```bash
./scripts/site-manager.sh add example.com --import-from
```

**Best for:** Migrating existing WordPress sites to WPFleet

**What it does:**

- Creates infrastructure (database, directories, routing)
- Prompts for database backup file (`.sql` or `.sql.gz`)
- Prompts for files archive (`.tar.gz` or `.zip`)
- Imports database and extracts files
- Updates `wp-config.php` with new database settings
- Adds Valkey (Redis-compatible) cache configuration

**Migration Process:**

1. Export your existing site's database
2. Create archive of WordPress files
3. Run the import command
4. Provide paths when prompted
5. Site becomes immediately available

**Supported formats:**

- Database: `.sql`, `.sql.gz`
- Files: `.tar.gz`, `.zip`

## Automated Installation

For automated server setup, use the utility script:

```bash
sudo ./install_util.sh
```

This script automatically installs Docker Engine and Docker Compose on Ubuntu/Debian systems.

## Docker Installation Problems

**Permission Denied Errors**

If you get permission errors with Docker:

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## Post-Installation

After installing your first site:

1. Point your domain's DNS to the server IP
2. Wait for SSL certificates to be automatically issued
3. Access your site at `https://example.com`
4. Login to WordPress admin at `https://example.com/wp-admin`

## Next Steps

- [Set up automated backups](./backups.md)
- [Configure notifications](./notifications.md)
- [Enable full-page caching](./cache-management.md)
- [Set up monitoring](./monitoring.md)

## Related Documentation

- [Migration Guide](./migration.md)
- [Site Management](./site-management.md)
- [Troubleshooting](./troubleshooting.md)
