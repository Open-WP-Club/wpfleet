#!/bin/bash

# WPFleet Git Deployment Script
# Deploy WordPress themes and plugins from Git repositories

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

# Check if git is available
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        print_error "git is not installed!"
        exit 1
    fi
}

# Validate domain
validate_domain() {
    local domain=$1
    if [ ! -d "$PROJECT_ROOT/data/wordpress/$domain" ]; then
        print_error "Site not found: $domain"
        return 1
    fi
    return 0
}

# Extract repository name from URL
get_repo_name() {
    local url=$1
    basename "$url" .git
}

# Deploy theme from Git
deploy_theme() {
    local domain=$1
    local git_url=$2
    local branch="${3:-main}"
    local theme_name=$(get_repo_name "$git_url")
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    local themes_dir="$site_dir/wp-content/themes"
    local theme_dir="$themes_dir/$theme_name"

    print_info "Deploying theme: $theme_name from $git_url (branch: $branch)"

    # Validate site exists
    if ! validate_domain "$domain"; then
        exit 1
    fi

    # Create themes directory if it doesn't exist
    mkdir -p "$themes_dir"

    # Check if theme already exists
    if [ -d "$theme_dir" ]; then
        print_info "Theme already exists. Pulling latest changes..."

        # Check if it's a git repository
        if [ -d "$theme_dir/.git" ]; then
            cd "$theme_dir"

            # Stash any local changes
            git stash 2>/dev/null || true

            # Fetch and pull
            git fetch origin "$branch" 2>/dev/null || {
                print_error "Failed to fetch from remote"
                exit 1
            }

            git checkout "$branch" 2>/dev/null || {
                print_error "Failed to checkout branch: $branch"
                exit 1
            }

            git pull origin "$branch" 2>/dev/null || {
                print_error "Failed to pull latest changes"
                exit 1
            }

            print_success "Theme updated successfully"
        else
            print_error "Theme directory exists but is not a git repository. Remove it manually first."
            exit 1
        fi
    else
        print_info "Cloning theme repository..."

        # Clone the repository
        git clone --branch "$branch" "$git_url" "$theme_dir" 2>/dev/null || {
            print_error "Failed to clone repository"
            exit 1
        }

        print_success "Theme cloned successfully"
    fi

    # Set proper permissions
    chown -R www-data:www-data "$theme_dir" 2>/dev/null || true

    # Check if WP-CLI is available and activate theme
    print_info "Activating theme..."
    if docker exec -u www-data wpfleet_frankenphp wp theme is-installed "$theme_name" --path="/var/www/html/$domain" 2>/dev/null; then
        docker exec -u www-data wpfleet_frankenphp wp theme activate "$theme_name" --path="/var/www/html/$domain" 2>/dev/null && {
            print_success "Theme activated: $theme_name"
        } || {
            print_warning "Theme deployed but activation failed. Activate manually via WordPress admin."
        }
    else
        print_warning "WP-CLI not available or theme not recognized. Activate manually via WordPress admin."
    fi

    # Send notification
    if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
        "$SCRIPT_DIR/notify.sh" deployment success "$domain" "theme" "$theme_name" 2>/dev/null || true
    fi

    print_success "Theme deployment completed!"
    echo ""
    print_info "Theme: $theme_name"
    print_info "Location: $theme_dir"
    print_info "Branch: $branch"
}

# Deploy plugin from Git
deploy_plugin() {
    local domain=$1
    local git_url=$2
    local branch="${3:-main}"
    local plugin_name=$(get_repo_name "$git_url")
    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    local plugins_dir="$site_dir/wp-content/plugins"
    local plugin_dir="$plugins_dir/$plugin_name"

    print_info "Deploying plugin: $plugin_name from $git_url (branch: $branch)"

    # Validate site exists
    if ! validate_domain "$domain"; then
        exit 1
    fi

    # Create plugins directory if it doesn't exist
    mkdir -p "$plugins_dir"

    # Check if plugin already exists
    if [ -d "$plugin_dir" ]; then
        print_info "Plugin already exists. Pulling latest changes..."

        # Check if it's a git repository
        if [ -d "$plugin_dir/.git" ]; then
            cd "$plugin_dir"

            # Stash any local changes
            git stash 2>/dev/null || true

            # Fetch and pull
            git fetch origin "$branch" 2>/dev/null || {
                print_error "Failed to fetch from remote"
                exit 1
            }

            git checkout "$branch" 2>/dev/null || {
                print_error "Failed to checkout branch: $branch"
                exit 1
            }

            git pull origin "$branch" 2>/dev/null || {
                print_error "Failed to pull latest changes"
                exit 1
            }

            print_success "Plugin updated successfully"
        else
            print_error "Plugin directory exists but is not a git repository. Remove it manually first."
            exit 1
        fi
    else
        print_info "Cloning plugin repository..."

        # Clone the repository
        git clone --branch "$branch" "$git_url" "$plugin_dir" 2>/dev/null || {
            print_error "Failed to clone repository"
            exit 1
        }

        print_success "Plugin cloned successfully"
    fi

    # Set proper permissions
    chown -R www-data:www-data "$plugin_dir" 2>/dev/null || true

    # Check if WP-CLI is available and activate plugin
    print_info "Activating plugin..."
    if docker exec -u www-data wpfleet_frankenphp wp plugin is-installed "$plugin_name" --path="/var/www/html/$domain" 2>/dev/null; then
        docker exec -u www-data wpfleet_frankenphp wp plugin activate "$plugin_name" --path="/var/www/html/$domain" 2>/dev/null && {
            print_success "Plugin activated: $plugin_name"
        } || {
            print_warning "Plugin deployed but activation failed. Activate manually via WordPress admin."
        }
    else
        print_warning "WP-CLI not available or plugin not recognized. Activate manually via WordPress admin."
    fi

    # Send notification
    if command -v "$SCRIPT_DIR/notify.sh" >/dev/null 2>&1; then
        "$SCRIPT_DIR/notify.sh" deployment success "$domain" "plugin" "$plugin_name" 2>/dev/null || true
    fi

    print_success "Plugin deployment completed!"
    echo ""
    print_info "Plugin: $plugin_name"
    print_info "Location: $plugin_dir"
    print_info "Branch: $branch"
}

# List deployed Git repositories
list_deployments() {
    local domain=$1
    local type="${2:-all}"  # theme, plugin, or all

    print_info "Git Deployments for: $domain"
    echo ""

    if ! validate_domain "$domain"; then
        exit 1
    fi

    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"

    # List themes
    if [ "$type" = "all" ] || [ "$type" = "theme" ]; then
        echo "Themes:"
        local themes_dir="$site_dir/wp-content/themes"
        if [ -d "$themes_dir" ]; then
            for theme_dir in "$themes_dir"/*; do
                if [ -d "$theme_dir/.git" ]; then
                    local theme_name=$(basename "$theme_dir")
                    local remote_url=$(cd "$theme_dir" && git config --get remote.origin.url 2>/dev/null || echo "unknown")
                    local branch=$(cd "$theme_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                    local last_commit=$(cd "$theme_dir" && git log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "unknown")
                    echo "  ✓ $theme_name"
                    echo "    Repository: $remote_url"
                    echo "    Branch: $branch"
                    echo "    Last commit: $last_commit"
                    echo ""
                fi
            done
        fi
    fi

    # List plugins
    if [ "$type" = "all" ] || [ "$type" = "plugin" ]; then
        echo "Plugins:"
        local plugins_dir="$site_dir/wp-content/plugins"
        if [ -d "$plugins_dir" ]; then
            for plugin_dir in "$plugins_dir"/*; do
                if [ -d "$plugin_dir/.git" ]; then
                    local plugin_name=$(basename "$plugin_dir")
                    local remote_url=$(cd "$plugin_dir" && git config --get remote.origin.url 2>/dev/null || echo "unknown")
                    local branch=$(cd "$plugin_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
                    local last_commit=$(cd "$plugin_dir" && git log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "unknown")
                    echo "  ✓ $plugin_name"
                    echo "    Repository: $remote_url"
                    echo "    Branch: $branch"
                    echo "    Last commit: $last_commit"
                    echo ""
                fi
            done
        fi
    fi
}

# Update all Git deployments for a site
update_all() {
    local domain=$1

    print_info "Updating all Git deployments for: $domain"
    echo ""

    if ! validate_domain "$domain"; then
        exit 1
    fi

    local site_dir="$PROJECT_ROOT/data/wordpress/$domain"
    local updated_count=0
    local failed_count=0

    # Update themes
    local themes_dir="$site_dir/wp-content/themes"
    if [ -d "$themes_dir" ]; then
        for theme_dir in "$themes_dir"/*; do
            if [ -d "$theme_dir/.git" ]; then
                local theme_name=$(basename "$theme_dir")
                print_info "Updating theme: $theme_name"

                cd "$theme_dir"
                local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

                if git pull origin "$branch" 2>/dev/null; then
                    print_success "Updated: $theme_name"
                    updated_count=$((updated_count + 1))
                else
                    print_error "Failed to update: $theme_name"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done
    fi

    # Update plugins
    local plugins_dir="$site_dir/wp-content/plugins"
    if [ -d "$plugins_dir" ]; then
        for plugin_dir in "$plugins_dir"/*; do
            if [ -d "$plugin_dir/.git" ]; then
                local plugin_name=$(basename "$plugin_dir")
                print_info "Updating plugin: $plugin_name"

                cd "$plugin_dir"
                local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

                if git pull origin "$branch" 2>/dev/null; then
                    print_success "Updated: $plugin_name"
                    updated_count=$((updated_count + 1))
                else
                    print_error "Failed to update: $plugin_name"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done
    fi

    echo ""
    print_info "Update summary: $updated_count succeeded, $failed_count failed"
}

# Main command handler
check_git

case "${1:-}" in
    theme)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 theme <domain> <git-url> [branch]"
            exit 1
        fi
        deploy_theme "$2" "$3" "${4:-main}"
        ;;

    plugin)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 plugin <domain> <git-url> [branch]"
            exit 1
        fi
        deploy_plugin "$2" "$3" "${4:-main}"
        ;;

    list)
        if [ -z "$2" ]; then
            print_error "Usage: $0 list <domain> [theme|plugin|all]"
            exit 1
        fi
        list_deployments "$2" "${3:-all}"
        ;;

    update)
        if [ -z "$2" ]; then
            print_error "Usage: $0 update <domain>"
            exit 1
        fi
        update_all "$2"
        ;;

    *)
        echo "WPFleet Git Deployment Manager"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  theme <domain> <git-url> [branch]   - Deploy theme from Git repository"
        echo "  plugin <domain> <git-url> [branch]  - Deploy plugin from Git repository"
        echo "  list <domain> [type]                - List Git deployments (type: theme|plugin|all)"
        echo "  update <domain>                     - Update all Git deployments for a site"
        echo ""
        echo "Examples:"
        echo "  # Deploy theme"
        echo "  $0 theme example.com https://github.com/user/my-theme.git main"
        echo ""
        echo "  # Deploy plugin"
        echo "  $0 plugin example.com https://github.com/user/my-plugin.git develop"
        echo ""
        echo "  # List all Git deployments"
        echo "  $0 list example.com"
        echo ""
        echo "  # Update all Git deployments"
        echo "  $0 update example.com"
        echo ""
        echo "Notes:"
        echo "  - Default branch is 'main' if not specified"
        echo "  - Themes/plugins are automatically activated after deployment"
        echo "  - Use HTTPS URLs for public repositories"
        echo "  - For private repositories, configure SSH keys in the container"
        exit 1
        ;;
esac
