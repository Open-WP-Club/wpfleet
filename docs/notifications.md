# Notifications

Get real-time notifications for important events via Discord or Slack webhooks.

## Overview

WPFleet's notification system keeps you informed about:
- Backup completion and failures
- Service health issues
- Disk space warnings
- SSL certificate expiration
- Git deployment status
- Disk quota violations

## Supported Platforms

- **Discord**: Rich embeds with color coding
- **Slack**: Formatted messages with attachments
- Both platforms can be enabled simultaneously

## Setup

### Discord Setup

1. **Create a webhook** in your Discord server:
   - Go to Server Settings → Integrations → Webhooks
   - Click "New Webhook"
   - Name it (e.g., "WPFleet Notifications")
   - Select the channel for notifications
   - Copy the webhook URL

2. **Add to WPFleet configuration** in `.env`:

```env
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
```

3. **Test the webhook:**

```bash
./scripts/notify.sh test
```

### Slack Setup

1. **Create an Incoming Webhook**:
   - Go to your Slack workspace settings
   - Navigate to Apps → Custom Integrations → Incoming Webhooks
   - Click "Add to Slack"
   - Choose the channel for notifications
   - Copy the webhook URL

2. **Add to WPFleet configuration** in `.env`:

```env
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

3. **Test the webhook:**

```bash
./scripts/notify.sh test
```

### Enabling Both Platforms

You can receive notifications on both Discord and Slack:

```env
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

## Notification Types

### Success Notifications (Green)

Sent for successful operations:
- Backup completion
- Site deployment success
- Health check passed
- Git deployment success

### Warning Notifications (Yellow/Orange)

Sent for potential issues:
- Disk space > 80%
- SSL certificate expiring soon (< 30 days)
- Disk quota > 80%
- Service degraded performance

### Error Notifications (Red)

Sent for failures and critical issues:
- Backup failure
- Service down
- Disk space > 90%
- Database connection failure
- Git deployment failure
- Disk quota exceeded

## Manual Notifications

Send custom notifications from scripts or command line:

### Success

```bash
./scripts/notify.sh success "Deployment Complete" "Successfully deployed to production"
```

### Warning

```bash
./scripts/notify.sh warning "High Memory Usage" "Memory usage at 85%"
```

### Error

```bash
./scripts/notify.sh error "Backup Failed" "Failed to backup example.com"
```

### Info

```bash
./scripts/notify.sh info "Maintenance" "Starting system maintenance"
```

## Automated Notifications

Notifications are automatically sent for these events:

### Backup Events

```bash
# Configured in backup script
✓ Backup completed successfully
✗ Backup failed
⚠ Backup took longer than expected
```

### Health Check Events

```bash
# Configured in health-check script
✗ MariaDB not responding
✗ Valkey not responding
✗ FrankenPHP not responding
⚠ High disk usage (>80%)
✗ Critical disk usage (>90%)
```

### Git Deployment Events

```bash
# Configured in git-deploy script
✓ Theme deployed successfully
✓ Plugin deployed successfully
✗ Git clone failed
✗ Deployment failed
```

### Disk Quota Events

```bash
# Configured in quota-manager script
⚠ Site approaching quota limit (>80%)
✗ Site exceeded quota limit
```

## Customizing Notifications

### Adding Notifications to Scripts

Example of adding notifications to a custom script:

```bash
#!/bin/bash

# Source the notification library
source "$(dirname "$0")/lib/notify.sh"

# Your script logic
if [ $? -eq 0 ]; then
    send_notification "success" "Task Completed" "Your task finished successfully"
else
    send_notification "error" "Task Failed" "Your task encountered an error"
fi
```

### Notification Format

The `notify.sh` script accepts:

```bash
./scripts/notify.sh <level> <title> <message> [url]
```

**Parameters:**
- `level`: success, warning, error, info
- `title`: Short title (shown prominently)
- `message`: Detailed message
- `url`: Optional URL to include

**Example with URL:**

```bash
./scripts/notify.sh success "Site Live" "example.com is now live" "https://example.com"
```

## Notification Best Practices

### 1. Appropriate Channels

Create dedicated channels for different notification types:
- `#wpfleet-critical` - Errors only
- `#wpfleet-alerts` - Warnings and errors
- `#wpfleet-all` - All notifications

Use separate webhooks for each channel.

### 2. Rate Limiting

Avoid notification spam:
- Combine related events
- Use summary notifications for bulk operations
- Implement cooldown periods for recurring warnings

### 3. Actionable Information

Include useful details:
- Site affected
- Error messages
- How to fix
- Links to logs or dashboards

### 4. Test Regularly

Test notifications after changes:

```bash
./scripts/notify.sh test
```

## Troubleshooting

### Notifications Not Sending

1. **Verify webhook URLs**:
   ```bash
   echo $DISCORD_WEBHOOK_URL
   echo $SLACK_WEBHOOK_URL
   ```

2. **Test webhooks manually**:
   ```bash
   ./scripts/notify.sh test
   ```

3. **Check webhook validity**:
   - Discord: Go to Server Settings → Integrations → Webhooks
   - Slack: Check Incoming Webhooks in your workspace settings

4. **Check script permissions**:
   ```bash
   ls -l scripts/notify.sh
   chmod +x scripts/notify.sh
   ```

### Incorrect Formatting

1. **Verify curl is installed**:
   ```bash
   curl --version
   ```

2. **Check JSON formatting** in notify.sh script

3. **Test with simple message**:
   ```bash
   ./scripts/notify.sh info "Test" "Simple message"
   ```

### Webhook Deleted or Regenerated

If webhooks are deleted or recreated:

1. Generate new webhook URL in Discord/Slack
2. Update `.env` file
3. Test with:
   ```bash
   ./scripts/notify.sh test
   ```

### Rate Limiting

Discord and Slack have rate limits. If you hit them:

1. **Reduce notification frequency**
2. **Batch notifications**
3. **Add delays between notifications**:
   ```bash
   ./scripts/notify.sh success "Title 1" "Message 1"
   sleep 2
   ./scripts/notify.sh success "Title 2" "Message 2"
   ```

## Integration Examples

### With Cron Jobs

```bash
# In .env CUSTOM_CRON_JOBS
0 2 * * * cd /wpfleet && ./scripts/backup.sh all && ./scripts/notify.sh success "Backups" "All sites backed up"
```

### With Git Hooks

```bash
# In .git/hooks/post-commit
#!/bin/bash
./scripts/notify.sh info "Git Commit" "New commit: $(git log -1 --pretty=%B)"
```

### With Monitoring

```bash
# Custom monitoring script
#!/bin/bash
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
    ./scripts/notify.sh warning "High CPU" "CPU usage at $CPU_USAGE%"
fi
```

### With Deployment Pipeline

```bash
# Deployment script
#!/bin/bash
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git
if [ $? -eq 0 ]; then
    ./scripts/notify.sh success "Deployment" "Theme deployed to example.com"
else
    ./scripts/notify.sh error "Deployment Failed" "Theme deployment failed"
fi
```

## Advanced Configuration

### Custom Notification Script

Create a wrapper for your specific needs:

```bash
#!/bin/bash
# custom-notify.sh

SITE=$1
ACTION=$2
STATUS=$3

if [ "$STATUS" = "success" ]; then
    ./scripts/notify.sh success \
        "[$SITE] $ACTION" \
        "Successfully completed $ACTION on $SITE" \
        "https://$SITE"
else
    ./scripts/notify.sh error \
        "[$SITE] $ACTION Failed" \
        "Failed to complete $ACTION on $SITE" \
        "https://$SITE"
fi
```

Usage:
```bash
./custom-notify.sh example.com "Backup" "success"
```

### Environment-Specific Webhooks

Use different webhooks for staging vs production:

```env
# Production .env
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/.../production

# Staging .env
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/.../staging
```

### Notification Filtering

Create notification levels:

```bash
# In your scripts
NOTIFICATION_LEVEL=${NOTIFICATION_LEVEL:-"warning"}

send_filtered_notification() {
    local level=$1
    local title=$2
    local message=$3

    case $level in
        error)
            ./scripts/notify.sh error "$title" "$message"
            ;;
        warning)
            if [[ "$NOTIFICATION_LEVEL" =~ ^(warning|info)$ ]]; then
                ./scripts/notify.sh warning "$title" "$message"
            fi
            ;;
        info)
            if [ "$NOTIFICATION_LEVEL" = "info" ]; then
                ./scripts/notify.sh info "$title" "$message"
            fi
            ;;
    esac
}
```

## Security Considerations

1. **Protect webhook URLs**: Keep them secret in `.env`
2. **Don't commit webhooks**: Ensure `.env` is in `.gitignore`
3. **Regenerate if exposed**: Generate new webhooks if accidentally exposed
4. **Limit permissions**: Use read-only channels when possible
5. **Sanitize messages**: Avoid including sensitive data in notifications

## Related Documentation

- [Backups](./backups.md)
- [Monitoring](./monitoring.md)
- [Git Deployments](./git-deployments.md)
- [Disk Quotas](./disk-quotas.md)
- [Troubleshooting](./troubleshooting.md)
