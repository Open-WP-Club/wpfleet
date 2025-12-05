# WPFleet - Docker-based WordPress Multi-Site Hosting

WPFleet is a production-ready, scalable solution for hosting multiple WordPress sites on a single server using Docker, FrankenPHP, MariaDB, and Valkey (Redis-compatible cache).

## Features

- **FrankenPHP** - Modern PHP application server with built-in Caddy
- **Automatic SSL** - Let's Encrypt certificates via Caddy
- **Shared MariaDB** - Single database server with isolated databases
- **Valkey Caching** - Redis-compatible object cache for improved performance
- **WP-CLI** - Built-in WordPress command-line interface
- **Security First** - Isolated containers, security headers, and best practices
- **Resource Management** - CPU and memory limits per site
- **Easy Management** - Simple scripts for common tasks
- **Migration Support** - Import WordPress sites from archives and database dumps
- **Automated Backups** - Scheduled backups with configurable retention
- **Discord & Slack Notifications** - Real-time alerts for backups, health issues, and deployments
- **Site Cloning** - One-command site duplication for staging or testing
- **Git-Based Deployments** - Deploy themes and plugins directly from Git repositories
- **Disk Quota Management** - Per-site disk quotas with monitoring and alerts
- **Full-Page Caching** - Redis Object Cache and Cache Enabler for maximum performance

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

```bash
./scripts/site-manager.sh add example.com
```

That's it! Your site will be available at `https://example.com` with automatic SSL.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

### Getting Started
- **[Installation Guide](docs/installation.md)** - Detailed installation instructions and requirements
- **[Migration Guide](docs/migration.md)** - Migrate existing WordPress sites to WPFleet

### Core Features
- **[Site Management](docs/site-management.md)** - Adding, removing, cloning, and managing sites
- **[Cache Management](docs/cache-management.md)** - Object and full-page caching
- **[Backups](docs/backups.md)** - Automated backup scheduling and restoration
- **[Git Deployments](docs/git-deployments.md)** - Deploy themes and plugins from Git
- **[Disk Quotas](docs/disk-quotas.md)** - Per-site storage limits and monitoring

### Operations
- **[Monitoring](docs/monitoring.md)** - Real-time dashboard and health checks
- **[Notifications](docs/notifications.md)** - Discord and Slack integration
- **[Security](docs/security.md)** - Security features and best practices
- **[Scaling](docs/scaling.md)** - Vertical and horizontal scaling strategies
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Requirements

- Docker Engine 20.10+
- Docker Compose 2.0+
- Linux server (Ubuntu 20.04+ recommended)
- Domain names pointing to your server
- Ports 80 and 443 available
- Minimum 2GB RAM (4GB+ recommended)
- SSH access for management

## Common Operations

### Add a Site

```bash
./scripts/site-manager.sh add example.com
```

### Clone a Site

```bash
./scripts/site-manager.sh clone source.com staging.com
```

### Backup a Site

```bash
./scripts/backup.sh site example.com
```

### Monitor Services

```bash
./scripts/monitor.sh
```

### Run Health Check

```bash
./scripts/health-check.sh
```

### Use WP-CLI

```bash
./scripts/wp-cli.sh example.com plugin list
```

## Project Structure

```
wpfleet/
├── config/           # Configuration files (Caddy, PHP, etc.)
├── docker/           # Dockerfiles and container configs
├── docs/             # Documentation
├── scripts/          # Management scripts
│   ├── site-manager.sh    # Site operations
│   ├── backup.sh          # Backup functionality
│   ├── cache-manager.sh   # Cache operations
│   ├── git-deploy.sh      # Git deployments
│   ├── quota-manager.sh   # Disk quotas
│   ├── monitor.sh         # Real-time monitoring
│   ├── health-check.sh    # Health checks
│   ├── notify.sh          # Notifications
│   └── wp-cli.sh          # WordPress CLI
├── data/             # Runtime data (created on first run)
│   ├── wordpress/    # WordPress site files
│   ├── mysql/        # MariaDB data
│   ├── valkey/       # Cache data
│   ├── backups/      # Backup storage
│   └── logs/         # Log files
├── .env.example      # Environment configuration template
└── docker-compose.yml
```

## Architecture

- **FrankenPHP**: Serves PHP applications with built-in Caddy web server
- **MariaDB**: Shared database with isolated databases per site
- **Valkey**: Redis-compatible cache for object caching
- **Docker Compose**: Orchestrates all services

Each WordPress site runs in an isolated directory with its own database, while sharing the same PHP server and cache infrastructure.

## Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -am 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Submit a pull request

## Support

- **Issues**: [GitHub Issues](https://github.com/Open-WP-Club/wpfleet/issues)
- **Documentation**: See [docs/](docs/) directory
- **Discussions**: [GitHub Discussions](https://github.com/Open-WP-Club/wpfleet/discussions)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [FrankenPHP](https://frankenphp.dev/) - Modern PHP application server
- [Caddy](https://caddyserver.com/) - Automatic HTTPS server
- [WordPress](https://wordpress.org/) - The world's most popular CMS
- [Docker](https://www.docker.com/) - Container platform
- [Valkey](https://valkey.io/) - Redis-compatible cache
