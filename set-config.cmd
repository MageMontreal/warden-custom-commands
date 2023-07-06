#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

:: Configuring application
den env exec php-fpm bin/magento app:config:import || true

if [[ "$WARDEN_VARNISH" -eq "1" ]]; then
    :: Configuring Varnish
    den env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_host varnish
    den env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_port 80
    den env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 2
    den env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/ttl 604800
else
    den env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 1
fi

if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
    if [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
        :: Configuring OpenSearch
        ELASTICSEARCH_HOSTNAME="opensearch"
    else
        :: Configuring ElasticSearch
        ELASTICSEARCH_HOSTNAME="elasticsearch"
    fi

    den env exec php-fpm bin/magento config:set --lock-env catalog/search/engine elasticsearch7
    den env exec php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_hostname $ELASTICSEARCH_HOSTNAME
    den env exec php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_port 9200
    den env exec php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_index_prefix magento2
    den env exec php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_enable_auth 0
    den env exec php-fpm bin/magento config:set --lock-env catalog/search/elasticsearch7_server_timeout 15
fi

if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    den env exec php-fpm bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 --cache-backend-redis-port=6379 --no-interaction
    den env exec php-fpm bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 --page-cache-redis-port=6379 --no-interaction
    den env exec php-fpm bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-max-concurrency=20 --session-save-redis-db=2 --session-save-redis-port=6379 --no-interaction
fi

den env exec php-fpm bin/magento setup:upgrade

den db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path IN('web/secure/base_url','web/unsecure/base_url','web/unsecure/base_link_url','web/secure/base_link_url')"
den db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'dev_$((1000 + $RANDOM % 10000))' WHERE path = 'algoliasearch_credentials/credentials/index_prefix'"

den env exec php-fpm bin/magento config:set --lock-env web/unsecure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
den env exec php-fpm bin/magento config:set --lock-env web/secure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

den env exec php-fpm bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto || true
den env exec php-fpm bin/magento config:set --lock-env klaviyo_reclaim_general/general/enable 0 || true
den env exec php-fpm bin/magento config:set --lock-env klaviyo_reclaim_webhook/klaviyo_webhooks/using_product_delete_before_webhook 0 || true
den env exec php-fpm bin/magento config:set --lock-env paypal/wpp/sandbox_flag 1 || true
den env exec php-fpm bin/magento config:set --lock-env web/cookie/cookie_domain "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
den env exec php-fpm bin/magento config:set --lock-env payment/checkmo/active 1 || true
den env exec php-fpm bin/magento config:set --lock-env payment/stripe_payments/active 0 || true
den env exec php-fpm bin/magento config:set --lock-env payment/stripe_payments_basic/stripe_mode test || true

:: Creating admin user
den env exec php-fpm bin/magento admin:user:create \
    --admin-password=Admin123 \
    --admin-user=magento2docker \
    --admin-firstname=Admin \
    --admin-lastname=Admin \
    --admin-email="magento2docker@den.test"