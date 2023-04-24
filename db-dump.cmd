#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function dumpCloud () {
    RELATIONSHIP=database-slave

    echo -e "🤔 \033[1;34mChecking which database relationship to use ...\033[0m"
    EXISTS=$(magento-cloud environment:relationships \
        --project="$CLOUD_PROJECT" \
        --environment="$DUMP_HOST" \
        --property=database-slave.0.host \
        2>/dev/null || true)
    [[ -z "$EXISTS" ]] && RELATIONSHIP=database

    echo -e "⌛ \033[1;32mDumping \033[33m${DUMP_HOST}\033[1;32m database ...\033[0m"
    magento-cloud db:dump \
        --project="$CLOUD_PROJECT" \
        --environment="$DUMP_HOST" \
        --relationship=$RELATIONSHIP \
        --gzip \
        --file "$DUMP_FILENAME"
}

function dumpPremise () {
    eval "ssh_host=\${"REMOTE_${DUMP_SOURCE_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${DUMP_SOURCE_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${DUMP_SOURCE_VAR}_PORT"}"
    eval "remote_dir=\${"REMOTE_${DUMP_SOURCE_VAR}_PATH"}"

    local db_info=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['host'];")
    local db_user=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['username'];")
    local db_pass=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['password'];")
    local db_name=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['dbname'];")

    local db_dump="export MYSQL_PWD=\"${db_pass}\";mysqldump --no-tablespaces -h$db_host -u$db_user $db_name --skip-triggers | gzip"
    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ssh_host}\033[1;32m...\033[0m"
    ssh -p $ssh_port $ssh_user@$ssh_host "$db_dump" > "$DUMP_FILENAME"
}

DUMP_SOURCE=staging
DUMP_HOST=STAGING
DUMP_FILENAME=

while (( "$#" )); do
    case "$1" in
        --file=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        --environment=*)
            DUMP_SOURCE="${1#*=}"
            shift
            ;;
        *)
            echo "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

DUMP_SOURCE_VAR=$(echo "$DUMP_SOURCE" | tr '[:lower:]' '[:upper:]')
DUMP_ENV="REMOTE_${DUMP_SOURCE_VAR}_HOST"

if [ -z ${!DUMP_ENV+x} ]; then
    echo "Invalid environment '${DUMP_SOURCE}'"
    exit 2
fi

if [ -z "$DUMP_FILENAME" ]; then
    DUMP_FILENAME="${WARDEN_ENV_NAME}_${DUMP_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
fi

DUMP_HOST=${!DUMP_ENV}

if [[ "${DUMP_HOST}" ]]; then
    if [ -z "$CLOUD_PROJECT" ]; then
        dumpPremise
    else
        dumpCloud
    fi
fi
