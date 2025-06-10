# WPFleet - Docker-based WordPress Multi-Site Hosting

WPFleet is a production-ready, scalable solution for hosting multiple WordPress sites on a single server using Docker, FrankenPHP, MariaDB, and Redis.

## Features

- 🚀 **FrankenPHP** - Modern PHP application server with built-in Caddy
- 🔒 **Automatic SSL** - Let's Encrypt certificates via Caddy
- 💾 **Shared MariaDB** - Single database server with isolated databases
- ⚡ **Redis Caching** - Object cache for improved performance
- 🛠️ **WP-CLI** - Built-in WordPress command-line interface
- 🔐 **Security First** - Isolated containers, security headers, and best practices
- 📊 **Resource Management** - CPU and memory limits per site
- 🎯 **Easy Management** - Simple scripts for common tasks

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
git clone https://github.com/yourusername/wpfleet.git
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
docker-compose up -d mariadb redis
```

### 5. Add Your First Site

```bash
./scripts/site-manager.sh add example.com
```

## Usage

### Managing Sites

#### Add a new site

```bash
./scripts/site-manager.sh add example.com
```

#### Add a site with specific PHP version

```bash
./scripts/site-manager.sh add example.com 8.2
```

#### List all sites

```bash
./scripts/site-manager.sh list
```

#### Remove a site

```bash
./scripts/site-manager.sh remove example.com
```

#### Restart a site

```bash
./scripts/site-manager.sh restart example.com
```

### Using WP-CLI

#### Execute WP-CLI commands

```bash
./scripts/wp-cli.sh example.com plugin list
./scripts/wp-cli.sh example.com user create john john@example.com --role=editor
./scripts/wp-cli.sh example.com theme activate twentytwentyfour
```

#### Open interactive WP-CLI shell

```bash
./scripts/wp-cli.sh example.com shell
```

#### Open bash shell in container

```bash
./scripts/wp-cli.sh example.com shell
```

### Database Management

#### Open MySQL shell

```bash
./scripts/db-manager.sh shell
```

#### Export a site's database

```bash
./scripts/db-manager.sh export example.com
```

#### Export all databases

```bash
./scripts/db-manager.sh export all
```

#### Import database

```bash
./scripts/db-manager.sh import example.com /path/to/backup.sql
```

#### Search and replace

```bash
./scripts/db-manager.sh search-replace example.com 'http://old.com' 'https://new.com'
```

## Architecture

### Container Structure

Each WordPress site runs in its own FrankenPHP container with:

- Isolated filesystem
- Dedicated Caddy configuration
- Automatic SSL certificate management
- Resource limits (CPU/Memory)
- Access to shared MariaDB and Redis

### Network Architecture

- All containers communicate on an isolated Docker network
- MariaDB and Redis are only accessible within the Docker network
- Each site container exposes ports 80/443 with Caddy handling SSL

### Data Persistence

- **WordPress Files**: `./data/wordpress/{domain}/`
- **MariaDB Data**: Docker volume `mariadb_data`
- **Redis Data**: Docker volume `redis_data`
- **Logs**: `./data/logs/{domain}/`
- **Configurations**: `./config/sites/{domain}/`

## Security

### Built-in Security Features

1. **Container Isolation**: Each site runs in its own container
2. **Network Isolation**: Internal Docker network for service communication
3. **Security Headers**: Automatically applied by Caddy
4. **SSL/TLS**: Automatic Let's Encrypt certificates
5. **Database Isolation**: Separate database per site
6. **Limited PHP Functions**: Dangerous functions disabled
7. **Read-only Configs**: Configuration files mounted read-only

### SSH-Only Database Access

Database management is restricted to SSH access only. No web-based tools are exposed.

### Fail2ban Integration (Host Configuration)

To enable Fail2ban, configure on your host system:

1. Install Fail2ban:

```bash
sudo apt-get install fail2ban
```

2. Copy the provided configuration:

```bash
sudo cp config/fail2ban/jail.local /etc/fail2ban/
sudo cp config/fail2ban/filter.d/* /etc/fail2ban/filter.d/
```

3. Restart Fail2ban:

```bash
sudo systemctl restart fail2ban
```

## Performance Optimization

### Redis Object Cache

Redis is automatically configured for each site. The Redis Cache plugin is installed and activated by default.

### PHP-FPM Tuning

PHP-FPM settings are optimized for WordPress:

- OPcache enabled with optimal settings
- Memory limits configured for WordPress
- Execution time increased for complex operations

### Resource Limits

Default limits per site (configurable in `.env`):

- Memory: 512MB
- CPU: 0.5 cores

Adjust based on your server capacity and site requirements.

## Backup Strategy

### Manual Backups

#### Full site backup

```bash
# Database
./scripts/db-manager.sh export example.com

# Files
tar -czf backup_example_com_files.tar.gz -C data/wordpress example.com
```

### Automated Backups

Create a cron job for automated backups:

```bash
# Edit crontab
crontab -e

# Add daily backup at 3 AM
0 3 * * * /path/to/wpfleet/scripts/backup.sh all
```

## Troubleshooting

### Check Container Logs

```bash
# All logs for a site
docker logs wpfleet_example_com

# Follow logs
docker logs -f wpfleet_example_com

# Last 100 lines
docker logs --tail 100 wpfleet_example_com
```

### Common Issues

#### Site not accessible

1. Check DNS is pointing to your server
2. Verify ports 80/443 are open
3. Check container is running: `docker ps | grep example_com`
4. Review Caddy logs for SSL issues

#### Database connection errors

1. Verify MariaDB is running: `docker ps | grep mariadb`
2. Check database exists: `./scripts/db-manager.sh list`
3. Verify credentials in container environment

#### Performance issues

1. Check Redis is working: `docker exec wpfleet_example_com wp redis status`
2. Monitor resource usage: `docker stats`
3. Review slow query log in MariaDB

## Scaling Considerations

### Vertical Scaling

- Increase memory/CPU limits in `.env`
- Tune MariaDB buffer pool size
- Increase Redis memory limit

### Horizontal Scaling

- Use external object storage for media files
- Implement CDN for static assets
- Consider separate database server
- Use load balancer for multiple instances

## Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -am 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

- Create an issue for bug reports or feature requests
- Check existing issues before creating new ones
- Provide detailed information for troubleshooting

## Acknowledgments

- [FrankenPHP](https://frankenphp.dev/) - Modern PHP application server
- [Caddy](https://caddyserver.com/) - Automatic HTTPS server
- [WordPress](https://wordpress.org/) - The world's most popular CMS
- [Docker](https://www.docker.com/) - Container platform
