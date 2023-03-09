#!/usr/bin/env bash
SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function dumpCloud () {
    RELATIONSHIP=database-slave

    echo -e "🤔 \033[1;34mChecking which database relationship to use ...\033[0m"
    EXISTS=$(magento-cloud environment:relationships \
        --project=$CLOUD_PROJECT \
        --environment=$DUMP_SOURCE \
        --property=database-slave.0.host \
        2>/dev/null || true)
    [[ -z "$EXISTS" ]] && RELATIONSHIP=database

    echo -e "⌛ \033[1;32mDumping \033[33m${DUMP_SOURCE}\033[1;32m database ...\033[0m"
    magento-cloud db:dump \
        --project=$CLOUD_PROJECT \
        --environment=$DUMP_SOURCE \
        --relationship=$RELATIONSHIP \
        --gzip \
        --file $DUMP_FILENAME
}

function dumpPremise () {
    eval "ssh_host=\${"REMOTE_${DUMP_SOURCE_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${DUMP_SOURCE_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${DUMP_SOURCE_VAR}_PORT"}"
    eval "remote_dir=\${"REMOTE_${DUMP_SOURCE_VAR}_PATH"}"

    db_host=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; print_r(\$a[\"db\"][\"connection\"][\"default\"][\"host\"]);"')
    db_user=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; print_r(\$a[\"db\"][\"connection\"][\"default\"][\"username\"]);"')
    db_pass=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; print_r(\$a[\"db\"][\"connection\"][\"default\"][\"password\"]);"')
    db_name=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; print_r(\$a[\"db\"][\"connection\"][\"default\"][\"dbname\"]);"')

    db_dump="export MYSQL_PWD=${db_pass}; mysqldump --no-tablespaces -h$db_host -u$db_user $db_name --triggers | gzip"
    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ssh_host}\033[1;32m...\033[0m"
    ssh -p $ssh_port $ssh_user@$ssh_host "$db_dump" > $DUMP_FILENAME
}

DUMP_SOURCE="${DUMP_SOURCE:-staging}"
DUMP_FILENAME="${WARDEN_ENV_NAME}_${DUMP_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
DUMP_HOST=

while (( "$#" )); do
    case "$1" in
        -f|--file)
            DUMP_FILENAME="$2"
            shift 2
            ;;
        -e|--environment)
            DUMP_SOURCE_VAR=$(echo "${2:-staging}" | tr '[:lower:]' '[:upper:]')
            DUMP_ENV="REMOTE_${DUMP_SOURCE_VAR}_HOST"

            if [ -z ${!DUMP_ENV+x} ]; then
                error "Invalid environment '${DUMP_SOURCE}'"
            fi

            DUMP_HOST=${!DUMP_ENV}

            shift 2
            ;;
        -*|--*|*)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

if [[ "${DUMP_HOST}" ]]; then
    if [[ "${DUMP_HOST}" = "CLOUD" ]]; then
        dumpCloud
    else
        dumpPremise
    fi
fi
