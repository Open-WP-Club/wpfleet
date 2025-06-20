FROM mariadb:11

# Install additional tools for performance monitoring
RUN apt-get update && apt-get install -y \
  htop \
  iotop \
  mytop \
  mysql-utilities \
  percona-toolkit \
  && rm -rf /var/lib/apt/lists/*

# Copy optimized MariaDB configuration
COPY mariadb-wpfleet.cnf /etc/mysql/conf.d/

# Create log directories with proper permissions
RUN mkdir -p /var/log/mysql && \
  chown -R mysql:mysql /var/log/mysql && \
  chmod 755 /var/log/mysql

# Create secure file directory
RUN mkdir -p /var/lib/mysql-files && \
  chown mysql:mysql /var/lib/mysql-files && \
  chmod 700 /var/lib/mysql-files

# Copy custom initialization scripts
COPY init/ /docker-entrypoint-initdb.d/

# Health check script
COPY healthcheck.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/healthcheck.sh

# Custom entrypoint for advanced setup
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mysqld"]