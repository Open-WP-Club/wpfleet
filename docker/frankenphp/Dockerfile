ARG PHP_VERSION=8.3

FROM dunglas/frankenphp:latest-php${PHP_VERSION}-alpine

# Install required PHP extensions and tools
RUN apk add --no-cache \
  # Build dependencies
  $PHPIZE_DEPS \
  linux-headers \
  # Required libraries
  freetype-dev \
  libjpeg-turbo-dev \
  libpng-dev \
  libwebp-dev \
  libavif-dev \
  imagemagick-dev \
  graphicsmagick-dev \
  # Other required libraries
  libzip-dev \
  icu-dev \
  libxml2-dev \
  gettext-dev \
  libmcrypt-dev \
  # Tools
  bash \
  curl \
  vim \
  mariadb-client \
  # For WP-CLI
  less \
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
  && pecl install \
  redis \
  imagick \
  gmagick \
  apcu \
  && docker-php-ext-enable \
  redis \
  imagick \
  gmagick \
  apcu \
  && apk del $PHPIZE_DEPS linux-headers \
  && rm -rf /var/cache/apk/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && chmod +x wp-cli.phar \
  && mv wp-cli.phar /usr/local/bin/wp

# Copy PHP configuration
COPY php.ini /usr/local/etc/php/conf.d/wpfleet.ini

# Create www-data user if it doesn't exist
RUN adduser -D -H -u 1000 -s /bin/bash www-data 2>/dev/null || true

# Set up directory structure
RUN mkdir -p /var/www/html \
  && chown -R www-data:www-data /var/www/html

# Copy Caddyfile template (not used in single container setup)
# COPY Caddyfile.template /etc/caddy/Caddyfile.template

# Set working directory
WORKDIR /var/www/html

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Switch to www-data user
USER www-data

# Set FrankenPHP specific environment variables
ENV FRANKENPHP_CONFIG=""
ENV PHP_FPM_PM="dynamic"
ENV PHP_FPM_PM_MAX_CHILDREN="50"
ENV PHP_FPM_PM_START_SERVERS="5"
ENV PHP_FPM_PM_MIN_SPARE_SERVERS="5"
ENV PHP_FPM_PM_MAX_SPARE_SERVERS="35"

# Entrypoint script to configure environment
COPY --chown=www-data:www-data docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]