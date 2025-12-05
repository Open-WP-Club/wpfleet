# Git-Based Deployments

Deploy themes and plugins directly from Git repositories to your WordPress sites.

## Overview

The Git deployment system allows you to:
- Deploy themes and plugins from any Git repository
- Track deployments and versions
- Update deployments with a single command
- Support for branches and tags
- Automatic plugin/theme activation
- Integration with notification system

## Quick Start

### Deploy a Theme

```bash
# Deploy from main/master branch
./scripts/git-deploy.sh theme example.com https://github.com/user/my-theme.git

# Deploy from specific branch
./scripts/git-deploy.sh theme example.com https://github.com/user/my-theme.git develop
```

### Deploy a Plugin

```bash
# Deploy from main/master branch
./scripts/git-deploy.sh plugin example.com https://github.com/user/my-plugin.git

# Deploy from specific branch
./scripts/git-deploy.sh plugin example.com https://github.com/user/my-plugin.git main
```

## Commands

### Deploy

Deploy a theme or plugin from a Git repository:

```bash
./scripts/git-deploy.sh <type> <domain> <repo-url> [branch]
```

**Parameters:**
- `type`: `theme` or `plugin`
- `domain`: Target WordPress site
- `repo-url`: Git repository URL (HTTPS or SSH)
- `branch`: Optional branch or tag (defaults to main/master)

**Examples:**

```bash
# Deploy theme from GitHub
./scripts/git-deploy.sh theme example.com https://github.com/username/my-theme.git

# Deploy plugin from GitLab with branch
./scripts/git-deploy.sh plugin example.com https://gitlab.com/username/my-plugin.git develop

# Deploy from private repo (requires SSH key)
./scripts/git-deploy.sh theme example.com git@github.com:username/private-theme.git

# Deploy specific tag
./scripts/git-deploy.sh plugin example.com https://github.com/username/my-plugin.git v1.2.3
```

### List Deployments

List all Git deployments for a site:

```bash
# List all deployments
./scripts/git-deploy.sh list example.com

# List only themes
./scripts/git-deploy.sh list example.com theme

# List only plugins
./scripts/git-deploy.sh list example.com plugin
```

**Output format:**
```
Git Deployments for example.com:

Themes:
  my-theme (https://github.com/user/my-theme.git, branch: main)
  another-theme (https://github.com/user/another-theme.git, branch: develop)

Plugins:
  my-plugin (https://github.com/user/my-plugin.git, branch: main)
```

### Update Deployments

Pull latest changes for all Git-deployed themes and plugins:

```bash
./scripts/git-deploy.sh update example.com
```

This will:
1. Find all Git-tracked deployments
2. Pull latest changes from each repository
3. Maintain the current branch
4. Report success/failure for each update

### Update Single Deployment

```bash
# Navigate to the deployment
cd data/wordpress/example.com/wp-content/themes/my-theme

# Pull changes manually
git pull origin main
```

## How It Works

### Initial Deployment

1. **Clone repository** to appropriate directory:
   - Themes: `wp-content/themes/<theme-name>/`
   - Plugins: `wp-content/plugins/<plugin-name>/`

2. **Checkout branch** if specified

3. **Store metadata** in `.git-deployments.json`:
   ```json
   {
     "themes": {
       "my-theme": {
         "repo": "https://github.com/user/my-theme.git",
         "branch": "main",
         "deployed_at": "2023-12-01T10:30:00Z"
       }
     },
     "plugins": {
       "my-plugin": {
         "repo": "https://github.com/user/my-plugin.git",
         "branch": "develop",
         "deployed_at": "2023-12-01T10:35:00Z"
       }
     }
   }
   ```

4. **Activate** theme or plugin via WP-CLI

5. **Send notification** if configured

### Updates

When running update:
1. Read deployment metadata
2. For each deployment:
   - Navigate to directory
   - Run `git pull`
   - Report status
3. Send notification with summary

## Repository Types

### Public Repositories

Use HTTPS URLs for public repositories:

```bash
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git
```

No authentication required.

### Private Repositories

#### Option 1: SSH Keys (Recommended)

1. **Generate SSH key** in the FrankenPHP container:
   ```bash
   docker exec -it wpfleet_frankenphp ssh-keygen -t ed25519 -C "wpfleet@example.com"
   ```

2. **Add public key** to your Git provider:
   ```bash
   docker exec wpfleet_frankenphp cat /root/.ssh/id_ed25519.pub
   ```

3. **Deploy with SSH URL**:
   ```bash
   ./scripts/git-deploy.sh theme example.com git@github.com:user/private-theme.git
   ```

#### Option 2: Personal Access Token

1. **Create a PAT** in your Git provider
2. **Use HTTPS URL with token**:
   ```bash
   ./scripts/git-deploy.sh theme example.com https://TOKEN@github.com/user/private-theme.git
   ```

**Note:** Tokens are stored in `.git-deployments.json`. Ensure proper file permissions.

## Branches and Tags

### Deploy Specific Branch

```bash
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git develop
```

### Deploy Specific Tag

```bash
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git v1.2.3
```

### Switch Branches

```bash
cd data/wordpress/example.com/wp-content/themes/my-theme
git checkout main
git pull origin main
```

## Development Workflow

### Staging to Production

1. **Deploy to staging**:
   ```bash
   ./scripts/git-deploy.sh theme staging.example.com https://github.com/user/theme.git develop
   ```

2. **Test on staging**:
   - Verify functionality
   - Check for errors
   - Review changes

3. **Deploy to production**:
   ```bash
   ./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git main
   ```

### Continuous Deployment

Create a webhook on your Git provider:

```bash
# Webhook endpoint (example using simple HTTP server)
curl -X POST https://your-server.com/deploy \
  -d "site=example.com" \
  -d "type=theme" \
  -d "name=my-theme"
```

Handle the webhook to trigger updates:

```bash
#!/bin/bash
# webhook-handler.sh
SITE=$1
TYPE=$2
NAME=$3

cd /path/to/wpfleet/data/wordpress/$SITE/wp-content/${TYPE}s/$NAME
git pull origin main

# Send notification
/path/to/wpfleet/scripts/notify.sh success \
  "Auto-Deploy" \
  "Updated $NAME on $SITE"
```

### Local Development Sync

Sync local changes to server:

```bash
# On local machine
git push origin develop

# On server
./scripts/git-deploy.sh update example.com
```

## Best Practices

### 1. Use Branches

- **main/master**: Production-ready code
- **develop**: Development and testing
- **feature/***: Feature branches
- **hotfix/***: Emergency fixes

### 2. Staging Environment

Always test on staging first:

```bash
# Deploy to staging
./scripts/git-deploy.sh theme staging.example.com https://github.com/user/theme.git develop

# Test thoroughly

# Deploy to production
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git main
```

### 3. Version Control

Use tags for releases:

```bash
# Create tag
git tag -a v1.0.0 -m "Version 1.0.0"
git push origin v1.0.0

# Deploy tagged version
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git v1.0.0
```

### 4. Automated Testing

Run tests before deploying:

```bash
# In your CI/CD pipeline
npm test
composer test
./vendor/bin/phpunit

# If tests pass, trigger deployment
./scripts/git-deploy.sh theme example.com https://github.com/user/theme.git main
```

### 5. Rollback Strategy

Keep previous versions for easy rollback:

```bash
# If new version has issues
cd data/wordpress/example.com/wp-content/themes/my-theme
git checkout v1.0.0  # Previous stable version
```

### 6. Documentation

Document your deployments:

```bash
# List all deployments
./scripts/git-deploy.sh list example.com > deployments.txt
```

## Troubleshooting

### Git Clone Fails

**Error:** Permission denied or repository not found

**Solutions:**

1. **Verify repository URL**:
   ```bash
   git ls-remote https://github.com/user/repo.git
   ```

2. **Check SSH key** for private repos:
   ```bash
   docker exec wpfleet_frankenphp ssh -T git@github.com
   ```

3. **Verify access token** for HTTPS with private repos

### Git Pull Fails

**Error:** Local changes would be overwritten

**Solutions:**

1. **Stash local changes**:
   ```bash
   cd data/wordpress/example.com/wp-content/themes/my-theme
   git stash
   git pull origin main
   ```

2. **Reset to remote**:
   ```bash
   git fetch origin
   git reset --hard origin/main
   ```

### Theme/Plugin Not Activating

**Check WP-CLI**:

```bash
# Check if theme installed
./scripts/wp-cli.sh example.com theme list

# Manually activate
./scripts/wp-cli.sh example.com theme activate my-theme

# Check for errors
./scripts/wp-cli.sh example.com theme status my-theme
```

### Deployment Metadata Missing

If `.git-deployments.json` is missing or corrupted:

1. **Recreate metadata**:
   ```bash
   # List Git repositories in themes/plugins
   find data/wordpress/example.com/wp-content/{themes,plugins} -name ".git" -type d
   ```

2. **Manually create entries** in `.git-deployments.json`

## Security Considerations

1. **Protect SSH keys**: Set proper permissions
   ```bash
   docker exec wpfleet_frankenphp chmod 600 /root/.ssh/id_ed25519
   ```

2. **Secure tokens**: Don't commit `.git-deployments.json` with tokens

3. **Review code**: Always review Git-deployed code for security issues

4. **Use signed commits**: Verify commit authenticity
   ```bash
   git log --show-signature
   ```

5. **Limit access**: Use deployment keys with read-only access when possible

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Deploy to WPFleet

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy theme
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.HOST }}
          username: ${{ secrets.USERNAME }}
          key: ${{ secrets.SSH_KEY }}
          script: |
            cd /path/to/wpfleet
            ./scripts/git-deploy.sh update example.com
```

### GitLab CI Example

```yaml
deploy:
  stage: deploy
  script:
    - ssh user@server 'cd /path/to/wpfleet && ./scripts/git-deploy.sh update example.com'
  only:
    - main
```

## Related Documentation

- [Site Management](./site-management.md)
- [Notifications](./notifications.md)
- [Monitoring](./monitoring.md)
- [Troubleshooting](./troubleshooting.md)
