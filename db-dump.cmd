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
    'catalog_product_index_eav_replica'
    'catalog_product_index_price_replica'
    'core_cache'
    'cron_schedule'
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
    'sales_invoiced_aggregated'
    'sales_invoiced_aggregated_order'
    'sales_order_aggregated_created'
    'sales_order_aggregated_updated'
    'sales_refunded_aggregated'
    'sales_refunded_aggregated_order'
    'sales_shipping_aggregated'
    'sales_shipping_aggregated_order'
    'catalogsearch_fulltext_cl'
    'catalogsearch_recommendations'
    'search_query'
    'persistent_session'
    'session'
    'ui_bookmark'
    'amasty_fpc_activity'
    'amasty_fpc_context_debug'
    'amasty_fpc_flushes_log'
    'amasty_fpc_job_queue'
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
    'mpproductlabels_rule_meta_cl'
    'msp_tfa_trusted'
    'msp_tfa_user_config'
    'ub_migrate_step'
    'ub_migrate_map_step_2'
    'ub_migrate_map_step_3'
    'ub_migrate_map_step_3_attribute'
    'ub_migrate_map_step_3_attribute_option'
    'ub_migrate_map_step_4'
    'ub_migrate_map_step_5'
    'ub_migrate_map_step_5_product_download'
    'ub_migrate_map_step_5_product_option'
    'ub_migrate_map_step_6'
    'ub_migrate_map_step_6_customer_address'
    'ub_migrate_map_step_7'
    'ub_migrate_map_step_7_invoice'
    'ub_migrate_map_step_7_invoice_item'
    'ub_migrate_map_step_7_order'
    'ub_migrate_map_step_7_order_address'
    'ub_migrate_map_step_7_order_item'
    'ub_migrate_map_step_7_quote'
    'ub_migrate_map_step_7_quote_address'
    'ub_migrate_map_step_7_quote_item'
    'ub_migrate_map_step_8'
    'ub_migrate_map_step_8_downloadable_link_purchased'
    'ub_migrate_map_step_8_rating'
    'ub_migrate_map_step_8_review'
    'ub_migrate_map_step_8_review_summary'
    'ub_migrate_map_step_8_subscriber'
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

    if [[ "$FULL_DUMP" -eq "0" ]]; then
      for table in "${IGNORED_TABLES[@]}"; do
          ignored_opts+=( --exclude-table="${REMOTE_DB_PREFIX}${table}" )
      done
    fi

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
        ${ignored_opts[@]-} \
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
      for table in "${IGNORED_TABLES[@]}"; do
          ignored_opts+=( --ignore-table="${db_name}.${REMOTE_DB_PREFIX}${table}" )
      done
    fi

    echo -e "⌛ \033[1;32mDumping \033[33m${db_name}\033[1;32m database from \033[33m${ENV_SOURCE_HOST}\033[1;32m...\033[0m"

    local db_dump="export MYSQL_PWD='${db_pass}';mysqldump -h$db_host -u$db_user $db_name --no-tablespaces --single-transaction --no-data --skip-comments --routines | gzip"
    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" > "$DUMP_FILENAME"

    local db_dump="export MYSQL_PWD='${db_pass}';mysqldump  -h$db_host -u$db_user $db_name --no-tablespaces --single-transaction --skip-triggers --skip-comments --no-create-info "${ignored_opts[@]-}" | gzip"
    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST "$db_dump" >> "$DUMP_FILENAME"
    echo -e "✅ \033[32mDatabase dump complete! File: $DUMP_FILENAME\033[0m"
}

DUMP_FILENAME=
INCLUDE_CUSTOMER_DATA=0
FULL_DUMP=0

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
        --full|-d)
            FULL_DUMP=1
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
    DUMP_FILENAME="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
fi

if [[ "$FULL_DUMP" -eq "0" && "$INCLUDE_CUSTOMER_DATA" -eq "0" ]]; then
  IGNORED_TABLES+=(
    'sales_order' 'sales_order_address' 'sales_order_grid' 'sales_order_item' 'sales_order_payment' 'sales_order_status_history' 'sales_order_tax' 'sales_order_tax_item' 'magento_sales_order_grid_archive'
    'sales_invoice' 'sales_invoice_comment' 'sales_invoice_grid' 'sales_invoice_item' 'magento_sales_invoice_grid_archive'
    'sales_shipment' 'sales_shipment_comment' 'sales_shipment_grid' 'sales_shipment_item' 'sales_shipment_track' 'magento_sales_shipment_grid_archive'
    'sales_creditmemo' 'sales_creditmemo_comment' 'sales_creditmemo_grid' 'sales_creditmemo_item' 'magento_sales_creditmemo_grid_archive'
    'sales_payment_transaction'
    'paypal_billing_agreement' 'paypal_billing_agreement_order' 'paypal_payment_transaction' 'paypal_settlement_report' 'paypal_settlement_report_row'
    'magento_rma' 'magento_rma_grid' 'magento_rma_status_history' 'magento_rma_shipping_label' 'magento_rma_item_entity'
    'quote' 'quote_address' 'quote_address_item' 'quote_id_mask' 'quote_item' 'quote_item_option' 'quote_payment' 'quote_shipping_rate'
    'customer_address_entity' 'customer_address_entity_datetime' 'customer_address_entity_decimal' 'customer_address_entity_int' 'customer_address_entity_text' 'customer_address_entity_varchar'
    'customer_entity' 'customer_entity_datetime' 'customer_entity_decimal' 'customer_entity_int' 'customer_entity_text' 'customer_entity_varchar' 'customer_grid_flat'
    'newsletter_subscriber'
    'product_alert_price' 'product_alert_stock'
    'vault_payment_token' 'vault_payment_token_order_payment_link'
    'wishlist' 'wishlist_item' 'wishlist_item_option'
    'company' 'company_advanced_customer_entity' 'company_credit' 'company_credit_history' 'company_order_entity' 'company_payment' 'company_permissions' 'company_roles' 'company_shipping' 'company_structure' 'company_team' 'company_user_roles'
    'negotiable_quote_company_config'
    'purchase_order_company_config'
    'magento_giftcardaccount'
    'magento_customerbalance' 'magento_customerbalance_history' 'magento_customersegment_customer'
    'magento_reward' 'magento_reward_history'
    'aw_ca_company' 'aw_ca_company_domain' 'aw_ca_company_payments' 'aw_ca_company_requisition_lists' 'aw_ca_company_user' 'aw_ca_group' 'aw_ca_role'
    'aw_ca_order_approval_state' 'aw_cl_credit_summary' 'aw_cl_customer_group_credit_limit' 'aw_cl_job' 'aw_cl_transaction' 'aw_cl_transaction_entity' 'aw_cp_category_permissions' 'aw_cp_cms_page_permissions'
    'aw_cp_product_permissions' 'aw_ctq_comment' 'aw_ctq_comment_attachment' 'aw_ctq_history' 'aw_ctq_quote' 'aw_net30_order'
  )
fi

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi

