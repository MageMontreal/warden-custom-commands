#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

IGNORED_TABLES=(
    'admin_passwords'
    'admin_system_messages'
    'admin_user'
    'admin_user_expiration'
    'admin_user_session'
    'adminnotification_inbox'
    'cache_tag'
    'catalog_product_index_price_final_idx'
    'catalog_product_index_price_bundle_opt_idx'
    'catalog_product_index_price_bundle_idx'
    'catalog_product_index_price_downlod_idx'
    'catalog_product_index_price_cfg_opt_idx'
    'catalog_product_index_price_opt_idx'
    'catalog_product_index_price_cfg_opt_agr_idx'
    'catalog_product_index_price_opt_agr_idx'
    'catalog_product_index_price_bundle_sel_idx'
    'catalog_product_index_eav_decimal_idx'
    'cataloginventory_stock_status_idx'
    'catalog_product_index_eav_idx'
    'catalog_product_index_price_idx'
    'catalog_product_index_price_downlod_tmp'
    'catalog_product_index_price_cfg_opt_tmp'
    'catalog_product_index_eav_tmp'
    'catalog_product_index_price_tmp'
    'catalog_product_index_price_opt_tmp'
    'catalog_product_index_price_cfg_opt_agr_tmp'
    'catalog_product_index_eav_decimal_tmp'
    'catalog_product_index_price_opt_agr_tmp'
    'catalog_product_index_price_bundle_tmp'
    'catalog_product_index_price_bundle_sel_tmp'
    'cataloginventory_stock_status_tmp'
    'catalog_product_index_price_final_tmp'
    'catalog_product_index_price_bundle_opt_tmp'
    'catalog_category_product_index_tmp'
    'catalog_category_product_index_replica'
    'catalog_product_index_price_replica'
    'core_cache'
    'customer_log'
    'customer_visitor'
    'login_as_customer'
    'magento_bulk'
    'magento_login_as_customer_log'
    'magento_logging_event'
    'magento_logging_event_changes'
    'queue_message'
    'queue_message_status'
    'report_event'
    'report_compared_product_index'
    'report_viewed_product_aggregated_daily'
    'report_viewed_product_aggregated_monthly'
    'report_viewed_product_aggregated_yearly'
    'report_viewed_product_index'
    'reporting_module_status'
    'reporting_system_updates'
    'reporting_users'
    'sales_bestsellers_aggregated_daily'
    'sales_bestsellers_aggregated_monthly'
    'sales_bestsellers_aggregated_yearly'
    'search_query'
    'session'
    'ui_bookmark'
    'amasty_fpc_activity'
    'amasty_fpc_log'
    'amasty_fpc_pages_to_flush'
    'amasty_fpc_queue_page'
    'amasty_fpc_reports'
    'amasty_xsearch_users_search'
    'amasty_reports_abandoned_cart'
    'amasty_reports_customers_customers_daily'
    'amasty_reports_customers_customers_monthly'
    'amasty_reports_customers_customers_weekly'
    'amasty_reports_customers_customers_yearly'
    'kiwicommerce_activity'
    'kiwicommerce_activity_detail'
    'kiwicommerce_activity_log'
    'kiwicommerce_login_activity'
    'kl_events'
    'kl_products'
    'kl_sync'
    'mageplaza_smtp_log'
    'mailchimp_errors'
    'mailchimp_sync_batches'
    'mailchimp_sync_ecommerce'
    'mailchimp_webhook_request'
 )
ignored_opts=()

function dumpCloud () {
    RELATIONSHIP=database-slave

    echo -e "🤔 \033[1;34mChecking which database relationship to use ...\033[0m"
    local db_name=$(magento-cloud environment:relationships \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --property=database-slave.0.path \
        2>/dev/null || true)
    [[ -z "$db_name" ]] && RELATIONSHIP=database

    for table in "${IGNORED_TABLES[@]}"; do
        ignored_opts+=( --exclude-table="${DB_PREFIX}${table}" )
    done

    echo -e "⌛ \033[1;32mDumping \033[33m$ENV_SOURCE_HOST\033[1;32m database ...\033[0m"
    magento-cloud db:dump \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --relationship=$RELATIONSHIP \
        --schema-only \
        --stdout \
        --gzip > "$DUMP_FILENAME"

    magento-cloud db:dump \
        --project="$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        --relationship=$RELATIONSHIP \
        ${ignored_opts[@]} \
        --stdout \
        --gzip >> "$DUMP_FILENAME"
}

function dumpPremise () {
    local db_info=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST 'php -r "\$a=include \"'"$ENV_SOURCE_DIR"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['host'];")
    local db_user=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['username'];")
    local db_pass=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['password'];")
    local db_name=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['dbname'];")

    for table in "${IGNORED_TABLES[@]}"; do
        ignored_opts+=( --ignore-table="${db_name}.${DB_PREFIX}${table}" )
    done

    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ENV_SOURCE_HOST}\033[1;32m...\033[0m"

    local db_dump="export MYSQL_PWD='${db_pass}';mysqldump -h$db_host -u$db_user $db_name --no-tablespaces --single-transaction --skip-triggers --no-data | gzip"
    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" > "$DUMP_FILENAME"

    local db_dump="export MYSQL_PWD='${db_pass}';mysqldump  -h$db_host -u$db_user $db_name --no-tablespaces --single-transaction --skip-triggers --no-create-info "${ignored_opts[@]}" | gzip"
    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" >> "$DUMP_FILENAME"
}

DUMP_FILENAME=

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
        *)
            shift
            ;;
    esac
done

if [ -z "$DUMP_FILENAME" ]; then
    DUMP_FILENAME="${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
fi

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi

