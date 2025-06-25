ARG PHP_VERSION=8.3

# Use Debian instead of Alpine for better performance (glibc vs musl)
FROM dunglas/frankenphp:latest-php${PHP_VERSION}

# Install required PHP extensions and tools
RUN apt-get update && apt-get install -y \
  # Build dependencies
  $PHPIZE_DEPS \
  # Required libraries for WordPress
  libfreetype6-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
  libwebp-dev \
  libavif-dev \
  imagemagick \
  libmagickwand-dev \
  libzip-dev \
  libicu-dev \
  libxml2-dev \
  gettext \
  libmcrypt-dev \
  # Tools for monitoring and debugging
  htop \
  iotop \
  strace \
  # For WP-CLI and management
  less \
  curl \
  wget \
  mariadb-client \
  # For mailing
  msmtp \
  && docker-php-ext-configure gd \
  --with-freetype \
  --with-jpeg \
  --with-webp \
  --with-avif \
  && docker-php-ext-install -j$(nproc) \
  gd \
  mysqli \
  pdo_mysql \
  zip \
  intl \
  exif \
  bcmath \
  soap \
  opcache \
  gettext \
  calendar \
  sockets \
  pcntl \
  posix \
  && pecl install \
  redis \
  imagick \
  apcu \
  && docker-php-ext-enable \
  redis \
  imagick \
  apcu \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && chmod +x wp-cli.phar \
  && mv wp-cli.phar /usr/local/bin/wp

# Copy PHP configuration
COPY php.ini /usr/local/etc/php/conf.d/wpfleet.ini

# Create www-data user if it doesn't exist
RUN adduser --disabled-password --no-create-home --uid 1000 --shell /bin/bash www-data 2>/dev/null || true

# Set up directory structure
RUN mkdir -p \
  /var/www/html \
  /var/log/frankenphp \
  /var/log/php \
  /var/cache/frankenphp \
  /etc/caddy/sites \
  && chown -R www-data:www-data \
  /var/www/html \
  /var/log/frankenphp \
  /var/log/php \
  /var/cache/frankenphp \
  && chmod +x /usr/local/bin/docker-entrypoint.sh || true

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

WORKDIR /var/www/html

# Environment variables for FrankenPHP
ENV FRANKENPHP_CONFIG=""
ENV FRANKENPHP_WORKER_ENABLED="true"
ENV FRANKENPHP_NUM_THREADS="auto"
ENV FRANKENPHP_MAX_THREADS="auto"
ENV FRANKENPHP_WORKER_MAX_REQUESTS="1000"

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER www-data

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]