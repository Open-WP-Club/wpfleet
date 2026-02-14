ARG PHP_VERSION=8.4
ARG FRANKENPHP_VERSION=1.4

# Build stage - compile extensions
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION} AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
  $PHPIZE_DEPS \
  libfreetype6-dev \
  libjpeg62-turbo-dev \
  libpng-dev \
  libwebp-dev \
  libavif-dev \
  libmagickwand-dev \
  libzip-dev \
  libicu-dev \
  libxml2-dev \
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
  redis-6.3.0 \
  imagick-3.8.1 \
  apcu-5.1.24 \
  && docker-php-ext-enable \
  redis \
  imagick \
  apcu

# Production stage
FROM dunglas/frankenphp:${FRANKENPHP_VERSION}-php${PHP_VERSION}

# Copy compiled extensions from builder
COPY --from=builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Install runtime dependencies only (no dev packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
  # Runtime libraries for PHP extensions
  libfreetype6 \
  libjpeg62-turbo \
  libpng16-16 \
  libwebp7 \
  libavif15 \
  imagemagick \
  libmagickwand-6.q16-6 \
  libzip4 \
  libicu72 \
  libxml2 \
  # Essential tools
  curl \
  wget \
  less \
  mariadb-client \
  # Mail support
  msmtp \
  ca-certificates \
  # Process management
  tini \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# Install WP-CLI with verification
RUN curl -o /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && curl -o /tmp/wp-cli.phar.sha512 https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512 \
  && sha512sum -c /tmp/wp-cli.phar.sha512 \
  && chmod +x /tmp/wp-cli.phar \
  && mv /tmp/wp-cli.phar /usr/local/bin/wp \
  && rm /tmp/wp-cli.phar.sha512 \
  && wp --info --allow-root

# Copy PHP configuration
COPY php.ini /usr/local/etc/php/conf.d/wpfleet.ini

# Copy PHP-FPM pool configuration (if using PHP-FPM mode)
COPY php-fpm-pool.conf /usr/local/etc/php-fpm.d/wpfleet.conf

# Create necessary directories with proper permissions
RUN mkdir -p \
  /var/www/html \
  /var/log/frankenphp \
  /var/log/php \
  /var/cache/frankenphp \
  /var/cache/opcache \
  /etc/caddy/sites \
  /run/php \
  && chown -R www-data:www-data \
  /var/www/html \
  /var/log/frankenphp \
  /var/log/php \
  /var/cache/frankenphp \
  /var/cache/opcache \
  /run/php \
  && chmod 755 /var/www/html \
  && chmod 755 /var/log/frankenphp \
  && chmod 755 /var/log/php

# Copy entrypoint and health check scripts
COPY docker-entrypoint.sh /usr/local/bin/
COPY healthcheck.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
  && chmod +x /usr/local/bin/healthcheck.sh

# Improved health check with detailed status
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

WORKDIR /var/www/html

# Environment variables for FrankenPHP with better defaults
ENV FRANKENPHP_CONFIG="" \
  FRANKENPHP_WORKER_ENABLED="true" \
  FRANKENPHP_NUM_THREADS="auto" \
  FRANKENPHP_MAX_THREADS="auto" \
  FRANKENPHP_WORKER_MAX_REQUESTS="1000" \
  PHP_OPCACHE_PRELOAD="" \
  PHP_MAX_EXECUTION_TIME="300" \
  PHP_MEMORY_LIMIT="512M"

# Use www-data user for security
USER www-data

# Use tini for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]

# Labels for metadata
LABEL maintainer="WPFleet <https://github.com/Open-WP-Club/wpfleet>" \
  org.opencontainers.image.title="WPFleet FrankenPHP" \
  org.opencontainers.image.description="Optimized FrankenPHP container for WordPress multi-site hosting" \
  org.opencontainers.image.source="https://github.com/Open-WP-Club/wpfleet"
