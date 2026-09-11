#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
COMMANDS_DIR="$(cd "${SUBCOMMAND_DIR}" && pwd)"

source "${SUBCOMMAND_DIR}"/include

# Load YAML config (default + project override concatenated, then parsed once)
anon_cfg=$(mktemp)
cat "${COMMANDS_DIR}/anonymize.yaml" > "$anon_cfg"
if [[ -f "${WARDEN_ENV_PATH}/.warden/anonymize.yaml" ]]; then
    cat "${WARDEN_ENV_PATH}/.warden/anonymize.yaml" >> "$anon_cfg"
fi
PARSED_YAML=$(parse_yaml_file "$anon_cfg" "cfg" ".")
rm -f "$anon_cfg"

# Build table arrays from parsed YAML
# skip: true    → no schema, no data (disposable: _idx, _tmp, _cl, _replica)
# truncate: true → schema kept, data excluded (sessions, cache, logs, indexes)
IGNORED_SCHEMA=()
IGNORED_TABLES=()
SALES_TABLES=()
CUSTOMER_TABLES=()

while IFS= read -r table; do
    IGNORED_SCHEMA+=("$table")
    IGNORED_TABLES+=("$table")
done < <(echo "$PARSED_YAML" | grep "\.skip='true'" | sed "s/^cfgtables\.\(.*\)\.skip=.*/\1/" | sort -u)

while IFS= read -r table; do
    IGNORED_TABLES+=("$table")
done < <(echo "$PARSED_YAML" | grep "\.truncate='true'" | sed "s/^cfgtables\.\(.*\)\.truncate=.*/\1/" | sort -u)

while IFS= read -r table; do
    SALES_TABLES+=("$table")
done < <(echo "$PARSED_YAML" | grep "\.group='sales'" | sed "s/^cfgtables\.\(.*\)\.group=.*/\1/" | sort -u)

while IFS= read -r table; do
    CUSTOMER_TABLES+=("$table")
done < <(echo "$PARSED_YAML" | grep "\.group='customer'" | sed "s/^cfgtables\.\(.*\)\.group=.*/\1/" | sort -u)

ignored_tables=()
ignored_schema=()


function dumpCloud () {
    RELATIONSHIP=database-slave

    echo -e "🤔 \033[1;34mChecking which database relationship to use ...\033[0m"
    local db_name=$(magento-cloud environment:relationships \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --property=database-slave.0.path \
        2>/dev/null || true)
    [[ -z "$db_name" ]] && RELATIONSHIP=database

    if [[ "$FULL_DUMP" -eq "0" ]]; then
      for table in "${IGNORED_SCHEMA[@]}"; do
          ignored_schema+=( --exclude-table="${REMOTE_DB_PREFIX}${table}" )
      done
      for table in "${IGNORED_TABLES[@]}"; do
          ignored_tables+=( --exclude-table="${REMOTE_DB_PREFIX}${table}" )
      done
    fi

    echo -e "⌛ \033[1;32mDumping \033[33m$ENV_SOURCE_HOST\033[1;32m database ...\033[0m"
    magento-cloud db:dump \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --relationship=$RELATIONSHIP \
        --schema-only \
        ${ignored_schema[@]-} \
        --stdout \
        --gzip > "$DUMP_FILENAME"

    magento-cloud db:dump \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --relationship=$RELATIONSHIP \
        ${ignored_tables[@]-} \
        --stdout \
        --gzip >> "$DUMP_FILENAME"

    echo -e "✅ \033[32mDatabase dump complete! File: $DUMP_FILENAME\033[0m"
}

function dumpPremise () {
    local db_info=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST 'php -r "\$a=include \"'"$ENV_SOURCE_DIR"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')

    if [ -z "$db_info" ]; then
      exit
    fi

    local db_host=$(php -r "\$a=$db_info;echo \$a['host'];")
    local db_user=$(php -r "\$a=$db_info;echo \$a['username'];")
    local db_pass=$(php -r "\$a=$db_info;echo \$a['password'];")
    local db_name=$(php -r "\$a=$db_info;echo \$a['dbname'];")

    if [[ "$FULL_DUMP" -eq "0" ]]; then
      for table in "${IGNORED_SCHEMA[@]}"; do
          ignored_schema+=( --ignore-table="${db_name}.${REMOTE_DB_PREFIX}${table}" )
      done
      for table in "${IGNORED_TABLES[@]}"; do
          ignored_tables+=( --ignore-table="${db_name}.${REMOTE_DB_PREFIX}${table}" )
      done
    fi

    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ENV_SOURCE_HOST}\033[1;32m...\033[0m"

    local mysql="export MYSQL_PWD='${db_pass}';mysqldump -h$db_host -u$db_user $db_name"
    local db_dump="$mysql --default-character-set=utf8mb4 --no-tablespaces --single-transaction --no-data --skip-triggers --skip-comments --routines "${ignored_schema[@]-}" | gzip"

    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" > "$DUMP_FILENAME"

    local db_dump="$mysql --default-character-set=utf8mb4 --no-tablespaces --single-transaction --skip-triggers --skip-comments --no-create-info "${ignored_tables[@]-}" | gzip"

    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" >> "$DUMP_FILENAME"
    echo -e "✅ \033[32mDatabase dump complete! File: $DUMP_FILENAME\033[0m"
}

DUMP_FILENAME=
INCLUDE_CUSTOMER_DATA=0
INCLUDE_ORDER_DATA=0
FULL_DUMP=0
IMPORT_AFTER=0
ANONYMIZE=1

while (( "$#" )); do
    case "$1" in
        --file=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        -f)
            DUMP_FILENAME="${2}"
            shift 2
            ;;
        --include-customer-data|-c)
            INCLUDE_CUSTOMER_DATA=1
            shift
            ;;
        --include-order-data|-o)
            INCLUDE_CUSTOMER_DATA=1
            INCLUDE_ORDER_DATA=1
            shift
            ;;
        --full|-d)
            FULL_DUMP=1
            shift
            ;;
        --import|-i)
            IMPORT_AFTER=1
            shift
            ;;
        --no-anonymize)
            ANONYMIZE=0
            shift
            ;;
        *)
           shift
           ;;
    esac
done

if [[ -z "$DUMP_FILENAME" ]] && [[ -n "${WARDEN_PARAMS[0]+1}" ]]; then
    DUMP_FILENAME="${WARDEN_PARAMS[0]}"
fi

if [ -z "$DUMP_FILENAME" ]; then
    if [ ! -d "var" ]; then
        mkdir var
    fi
    DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
fi

if [[ "$FULL_DUMP" -eq "0" ]]; then
    if [[ "$INCLUDE_ORDER_DATA" -eq "0" ]]; then
        IGNORED_TABLES+=("${SALES_TABLES[@]}")
    fi

    if [[ "$INCLUDE_CUSTOMER_DATA" -eq "0" ]]; then
        IGNORED_TABLES+=("${CUSTOMER_TABLES[@]}")
    fi
fi

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi

if [[ "$ANONYMIZE" -eq "1" ]] && [[ "$INCLUDE_CUSTOMER_DATA" -eq "1" || "$INCLUDE_ORDER_DATA" -eq "1" || "$FULL_DUMP" -eq "1" ]]; then
    echo -e "🔒 \033[1;32mGenerating anonymization SQL ...\033[0m"

    converters_file=$(mktemp)
    while IFS= read -r line; do
        stripped="${line#cfgtables.}"
        table="${stripped%%.*}"
        rest="${stripped#*.converters.}"
        column="${rest%%.*}"
        converter=$(echo "$line" | sed "s/.*='\(.*\)'/\1/")
        param_val=$(echo "$PARSED_YAML" | grep "^cfgtables\.${table}\.converters\.${column}\.parameters\.value=" | sed "s/.*='\(.*\)'/\1/" | head -1 || true)
        param_fmt=$(echo "$PARSED_YAML" | grep "^cfgtables\.${table}\.converters\.${column}\.parameters\.formatter=" | sed "s/.*='\(.*\)'/\1/" | head -1 || true)
        echo "${table}|${column}|${converter}|${param_val}|${param_fmt}"
    done < <(echo "$PARSED_YAML" | grep '\.converters\.' | grep -v '\.eav_converters\.' | grep '\.converter=' | sort -u) > "$converters_file"

    # Extract EAV converter config: eav_table|entity_type|attribute_code|converter
    eav_file=$(mktemp)
    echo "$PARSED_YAML" | grep '\.eav_converters\.[0-9]*\.entity_type=' | sort -u | while IFS= read -r line; do
        stripped="${line#cfgtables.}"
        eav_table="${stripped%%.*}"
        rest="${stripped#*.eav_converters.}"
        idx="${rest%%.*}"
        entity_type=$(echo "$line" | sed "s/.*='\(.*\)'/\1/")
        attr_code=$(echo "$PARSED_YAML" | grep "^cfgtables\.${eav_table}\.eav_converters\.${idx}\.attribute_code=" | sed "s/.*='\(.*\)'/\1/" | head -1 || true)
        converter=$(echo "$PARSED_YAML" | grep "^cfgtables\.${eav_table}\.eav_converters\.${idx}\.converter=" | sed "s/.*='\(.*\)'/\1/" | head -1 || true)
        if [[ -n "$attr_code" ]] && [[ -n "$converter" ]]; then
            echo "${eav_table}|${entity_type}|${attr_code}|${converter}"
        fi
    done > "$eav_file"

    anon_sql=$(gunzip -c "$DUMP_FILENAME" \
        | awk -v prefix="$REMOTE_DB_PREFIX" \
              -v config_file="$converters_file" \
              -v eav_file="$eav_file" \
              -f "$COMMANDS_DIR/anonymize.awk" \
        2>/dev/null || true)

    rm -f "$converters_file" "$eav_file"

    if [[ -n "$anon_sql" ]]; then
        printf '%s\n' "$anon_sql" | gzip >> "$DUMP_FILENAME"
        echo -e "✅ \033[32mAnonymization SQL appended to dump\033[0m"
    else
        echo -e "⚠️  \033[33mNo PII columns detected, no anonymization SQL generated\033[0m"
    fi
fi

if [[ "$IMPORT_AFTER" -eq "1" ]]; then
  warden import-db "$DUMP_FILENAME"
fi
