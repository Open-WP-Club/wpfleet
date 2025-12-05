FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    bash \
    docker-cli \
    curl \
    jq \
    gzip \
    tar \
    findutils \
    coreutils \
    tzdata

# Create cron log directory
RUN mkdir -p /var/log/cron

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set timezone (can be overridden with TZ environment variable)
ENV TZ=UTC

ENTRYPOINT ["/entrypoint.sh"]
