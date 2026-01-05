#!/bin/bash

# WPFleet Installation Library Functions
# Helper functions for installation and setup tasks

# Generate all required passwords for WPFleet installation
# Stores passwords in associative array INSTALL_PASSWORDS
# Usage: generate_install_passwords
#        echo ${INSTALL_PASSWORDS[MYSQL_ROOT]}
generate_install_passwords() {
    declare -gA INSTALL_PASSWORDS

    INSTALL_PASSWORDS[MYSQL_ROOT]=$(generate_password 25)
    INSTALL_PASSWORDS[MYSQL_USER]=$(generate_password 25)
    INSTALL_PASSWORDS[REDIS]=$(generate_password 25)
    INSTALL_PASSWORDS[WP_ADMIN]=$(generate_password 16)

    print_success "Generated secure passwords"
}

# Update .env file with generated passwords
# Args: $1 - path to .env file
update_env_passwords() {
    local env_file=$1

    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi

    # Generate passwords if not already generated
    if [ -z "${INSTALL_PASSWORDS[MYSQL_ROOT]}" ]; then
        generate_install_passwords
    fi

    # Update .env file based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/your_secure_root_password_here/${INSTALL_PASSWORDS[MYSQL_ROOT]}/g" "$env_file"
        sed -i '' "s/your_secure_password_here/${INSTALL_PASSWORDS[MYSQL_USER]}/g" "$env_file"
        sed -i '' "s/generate_secure_redis_password_here/${INSTALL_PASSWORDS[REDIS]}/g" "$env_file"
        sed -i '' "s/generate_secure_password_here/${INSTALL_PASSWORDS[WP_ADMIN]}/g" "$env_file"
    else
        # Linux
        sed -i "s/your_secure_root_password_here/${INSTALL_PASSWORDS[MYSQL_ROOT]}/g" "$env_file"
        sed -i "s/your_secure_password_here/${INSTALL_PASSWORDS[MYSQL_USER]}/g" "$env_file"
        sed -i "s/generate_secure_redis_password_here/${INSTALL_PASSWORDS[REDIS]}/g" "$env_file"
        sed -i "s/generate_secure_password_here/${INSTALL_PASSWORDS[WP_ADMIN]}/g" "$env_file"
    fi

    print_success "Updated passwords in $env_file"
    return 0
}

# Update email addresses in .env file
# Args: $1 - path to .env file
#       $2 - email address
update_env_email() {
    local env_file=$1
    local email=$2

    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi

    if ! validate_email "$email"; then
        return 1
    fi

    # Update .env file based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/admin@yourdomain.com/$email/g" "$env_file"
        sed -i '' "s/ssl@yourdomain.com/$email/g" "$env_file"
    else
        sed -i "s/admin@yourdomain.com/$email/g" "$env_file"
        sed -i "s/ssl@yourdomain.com/$email/g" "$env_file"
    fi

    print_success "Updated email to $email in $env_file"
    return 0
}

# Create WPFleet directory structure
# Args: $1 - base directory (optional, defaults to current directory)
create_directory_structure() {
    local base_dir=${1:-.}

    local directories=(
        "$base_dir/data/wordpress"
        "$base_dir/data/mariadb"
        "$base_dir/data/valkey"
        "$base_dir/data/logs"
        "$base_dir/config/sites"
        "$base_dir/backups/databases"
        "$base_dir/backups/files"
    )

    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_success "Created: $dir"
        else
            print_info "Already exists: $dir"
        fi
    done

    # Create .gitkeep files
    touch "$base_dir/data/wordpress/.gitkeep"
    touch "$base_dir/data/mariadb/.gitkeep"
    touch "$base_dir/data/valkey/.gitkeep"
    touch "$base_dir/data/logs/.gitkeep"
    touch "$base_dir/config/sites/.gitkeep"

    return 0
}

# Make scripts executable
# Args: $1 - scripts directory path
make_scripts_executable() {
    local scripts_dir=${1:-scripts}

    if [ ! -d "$scripts_dir" ]; then
        print_error "Scripts directory not found: $scripts_dir"
        return 1
    fi

    chmod +x "$scripts_dir"/*.sh
    chmod +x docker/mariadb/init/*.sh 2>/dev/null || true

    print_success "Scripts are now executable"
    return 0
}

# Check if .env file needs to be regenerated
# Args: $1 - path to .env file
#       $2 - path to .env.example file
# Returns: 0 if should regenerate, 1 if should keep existing
should_regenerate_env() {
    local env_file=$1
    local env_example=${2:-"${env_file}.example"}

    if [ ! -f "$env_file" ]; then
        return 0  # No .env file, should create
    fi

    print_info ".env file already exists"

    if confirm "Do you want to regenerate it?"; then
        mv "$env_file" "${env_file}.backup"
        print_info "Backed up existing .env to ${env_file}.backup"
        return 0  # Should regenerate
    else
        print_info "Keeping existing .env file"
        return 1  # Keep existing
    fi
}

# Setup environment file from example
# Args: $1 - path to .env.example
#       $2 - path to .env (optional)
setup_env_file() {
    local env_example=$1
    local env_file=${2:-".env"}

    if [ ! -f "$env_example" ]; then
        print_error "Template file not found: $env_example"
        return 1
    fi

    if should_regenerate_env "$env_file" "$env_example"; then
        cp "$env_example" "$env_file"
        print_success "Created .env file from template"
        return 0
    fi

    return 1  # Kept existing file
}

# Verify Docker services are ready
# Args: $1 - container name
#       $2 - check command
#       $3 - timeout in seconds (default: 30)
wait_for_service() {
    local container=$1
    local check_cmd=$2
    local timeout=${3:-30}
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if eval "$check_cmd" >/dev/null 2>&1; then
            print_success "$container is ready"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    print_error "$container failed to start within ${timeout}s"
    return 1
}

# Export functions
export -f generate_install_passwords update_env_passwords update_env_email
export -f create_directory_structure make_scripts_executable
export -f should_regenerate_env setup_env_file wait_for_service
