#!/bin/bash

set -e

echo "WPFleet Cron Scheduler Starting..."

# Setup timezone
if [ -n "$TZ" ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
    echo $TZ > /etc/timezone
    echo "Timezone set to: $TZ"
fi

# Create crontab based on environment variables
CRONTAB_FILE="/etc/crontabs/root"

# Clear existing crontab
echo "# WPFleet Automated Tasks" > $CRONTAB_FILE

# Backup schedule (default: daily at 2 AM)
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
if [ "$BACKUP_ENABLED" != "false" ]; then
    echo "$BACKUP_SCHEDULE cd /wpfleet && ./scripts/backup.sh all >> /var/log/cron/backup.log 2>&1" >> $CRONTAB_FILE
    echo "✓ Backup scheduled: $BACKUP_SCHEDULE"
else
    echo "⊘ Backup disabled"
fi

# Health check schedule (default: every hour)
HEALTH_CHECK_SCHEDULE="${HEALTH_CHECK_SCHEDULE:-0 * * * *}"
if [ "$HEALTH_CHECK_ENABLED" != "false" ]; then
    echo "$HEALTH_CHECK_SCHEDULE cd /wpfleet && ./scripts/health-check.sh >> /var/log/cron/health-check.log 2>&1" >> $CRONTAB_FILE
    echo "✓ Health check scheduled: $HEALTH_CHECK_SCHEDULE"
else
    echo "⊘ Health check disabled"
fi

# Backup cleanup schedule (default: weekly on Sunday at 3 AM)
BACKUP_CLEANUP_SCHEDULE="${BACKUP_CLEANUP_SCHEDULE:-0 3 * * 0}"
if [ "$BACKUP_CLEANUP_ENABLED" != "false" ]; then
    echo "$BACKUP_CLEANUP_SCHEDULE cd /wpfleet && ./scripts/backup.sh cleanup >> /var/log/cron/cleanup.log 2>&1" >> $CRONTAB_FILE
    echo "✓ Backup cleanup scheduled: $BACKUP_CLEANUP_SCHEDULE"
else
    echo "⊘ Backup cleanup disabled"
fi

# Custom cron jobs (can be added via environment variable)
if [ -n "$CUSTOM_CRON_JOBS" ]; then
    echo "# Custom cron jobs" >> $CRONTAB_FILE
    echo "$CUSTOM_CRON_JOBS" >> $CRONTAB_FILE
    echo "✓ Custom cron jobs added"
fi

echo ""
echo "Active crontab:"
cat $CRONTAB_FILE
echo ""

# Create log files
touch /var/log/cron/backup.log
touch /var/log/cron/health-check.log
touch /var/log/cron/cleanup.log
touch /var/log/cron/cron.log

# Start cron in foreground
echo "Starting crond..."
exec crond -f -l 2 -L /var/log/cron/cron.log
