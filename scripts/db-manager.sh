#!/bin/bash

# WPFleet Database Manager
# Manage databases via SSH tunnel

set -e

# Load WPFleet libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/utils.sh"

# Load environment variables
load_env "$PROJECT_ROOT/.env" || exit 1

case "$1" in
    shell)
        print_info "Opening MySQL shell..."
        print_info "Use 'SHOW DATABASES;' to list all databases"
        docker exec -it wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD}
        ;;
        
    list)
        print_info "WordPress databases:"
        docker_mysql -e "SHOW DATABASES LIKE 'wp_%';" | tail -n +2
        ;;
        
    export)
        if [ -z "$2" ]; then
            print_error "Usage: $0 export <domain|all> [output_dir]"
            exit 1
        fi
        
        OUTPUT_DIR=${3:-"$PROJECT_ROOT/backups/databases"}
        mkdir -p "$OUTPUT_DIR"
        
        if [ "$2" = "all" ]; then
            print_info "Exporting all WordPress databases..."
            DATABASES=$(docker_mysql -e "SHOW DATABASES LIKE 'wp_%';" | tail -n +2)
            for db in $DATABASES; do
                FILENAME="$OUTPUT_DIR/${db}_$(date +%Y%m%d_%H%M%S).sql"
                print_info "Exporting $db to $FILENAME..."
                docker exec wpfleet_mariadb mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
                    --single-transaction --quick --lock-tables=false \
                    "$db" > "$FILENAME"
            done
            print_success "All databases exported to $OUTPUT_DIR"
        else
            DB_NAME=$(get_db_name "$2")
            FILENAME="$OUTPUT_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql"
            print_info "Exporting $DB_NAME to $FILENAME..."
            docker exec wpfleet_mariadb mysqldump -uroot -p${MYSQL_ROOT_PASSWORD} \
                --single-transaction --quick --lock-tables=false \
                "$DB_NAME" > "$FILENAME"
            print_success "Database exported to $FILENAME"
        fi
        ;;
        
    import)
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 import <domain> <sql_file>"
            exit 1
        fi
        
        if [ ! -f "$3" ]; then
            print_error "SQL file not found: $3"
            exit 1
        fi
        
        DB_NAME=$(get_db_name "$2")
        print_info "Importing to database $DB_NAME..."
        
        # Create database if it doesn't exist
        docker_mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        
        # Import the SQL file
        docker exec -i wpfleet_mariadb mysql -uroot -p${MYSQL_ROOT_PASSWORD} "$DB_NAME" < "$3"
        
        print_success "Database imported successfully!"
        ;;
        
    optimize)
        print_info "Optimizing all WordPress databases..."
        DATABASES=$(docker_mysql -e "SHOW DATABASES LIKE 'wp_%';" | tail -n +2)
        for db in $DATABASES; do
            print_info "Optimizing $db..."
            docker_mysql -e "USE \`$db\`; SHOW TABLES;" | tail -n +2 | while read table; do
                docker_mysql -e "OPTIMIZE TABLE \`$db\`.\`$table\`;" >/dev/null
            done
        done
        print_success "All databases optimized!"
        ;;
        
    size)
        print_info "Database sizes:"
        docker_mysql -e "
            SELECT 
                table_schema AS 'Database',
                ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
            FROM information_schema.tables 
            WHERE table_schema LIKE 'wp_%'
            GROUP BY table_schema
            ORDER BY SUM(data_length + index_length) DESC;
        "
        ;;
        
    search-replace)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            print_error "Usage: $0 search-replace <domain> <search> <replace>"
            exit 1
        fi
        
        print_info "Performing search-replace for $2..."
        print_info "Search: $3"
        print_info "Replace: $4"
        
        # Use WP-CLI for safe search-replace
        "$SCRIPT_DIR/wp-cli.sh" "$2" search-replace "$3" "$4" --all-tables
        
        print_success "Search-replace completed!"
        ;;
        
    *)
        echo "WPFleet Database Manager"
        echo ""
        echo "Usage: $0 {shell|list|export|import|optimize|size|search-replace} [options]"
        echo ""
        echo "Commands:"
        echo "  shell                       - Open MySQL shell"
        echo "  list                        - List all WordPress databases"
        echo "  export <domain|all> [dir]   - Export database(s)"
        echo "  import <domain> <sql_file>  - Import database from SQL file"
        echo "  optimize                    - Optimize all WordPress databases"
        echo "  size                        - Show database sizes"
        echo "  search-replace <domain> <search> <replace> - Search and replace in database"
        echo ""
        echo "Examples:"
        echo "  $0 shell"
        echo "  $0 export example.com"
        echo "  $0 export all /path/to/backups"
        echo "  $0 import example.com backup.sql"
        echo "  $0 search-replace example.com 'http://old.com' 'https://new.com'"
        exit 1
        ;;
esac