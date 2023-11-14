#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

:: Configuring application
warden env exec php-fpm bin/magento app:config:import || true

if [[ "$WARDEN_VARNISH" -eq "1" ]]; then
    :: Configuring Varnish
    warden env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_host varnish
    warden env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/varnish/backend_port 80
    warden env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 2
    warden env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/ttl 604800
    warden env exec php-fpm bin/magento setup:config:set --http-cache-hosts=varnish:80
else
    warden env exec php-fpm bin/magento config:set --lock-env system/full_page_cache/caching_application 1
fi

if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
    if [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
        :: Configuring OpenSearch
        ELASTICSEARCH_HOSTNAME="opensearch"
        ELASTICSEARCH_ENGINE="opensearch"
    else
        :: Configuring ElasticSearch
        ELASTICSEARCH_HOSTNAME="elasticsearch"
        ELASTICSEARCH_ENGINE="elasticsearch7"
    fi

    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/engine $ELASTICSEARCH_ENGINE
    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_hostname $ELASTICSEARCH_HOSTNAME
    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_port 9200
    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_index_prefix magento2
    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_enable_auth 0
    warden env exec php-fpm bin/magento config:set --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_timeout 15
fi

if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    warden env exec php-fpm bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 --cache-backend-redis-port=6379 --no-interaction
    warden env exec php-fpm bin/magento setup:config:set --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 --page-cache-redis-port=6379 --no-interaction
    warden env exec php-fpm bin/magento setup:config:set --session-save=redis --session-save-redis-host=redis --session-save-redis-max-concurrency=20 --session-save-redis-db=2 --session-save-redis-port=6379 --no-interaction
fi

warden env exec php-fpm bin/magento setup:upgrade

warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path IN('web/secure/base_url','web/unsecure/base_url','web/unsecure/base_link_url','web/secure/base_link_url')"
warden db connect -e "UPDATE ${DB_PREFIX}core_config_data SET value = 'dev_$((1000 + $RANDOM % 10000))' WHERE path = 'algoliasearch_credentials/credentials/index_prefix'"

warden env exec php-fpm bin/magento config:set --lock-env web/unsecure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
warden env exec php-fpm bin/magento config:set --lock-env web/secure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

warden env exec php-fpm bin/magento config:set --lock-env web/secure/offloader_header X-Forwarded-Proto || true
warden env exec php-fpm bin/magento config:set --lock-env klaviyo_reclaim_general/general/enable 0 || true
warden env exec php-fpm bin/magento config:set --lock-env klaviyo_reclaim_webhook/klaviyo_webhooks/using_product_delete_before_webhook 0 || true
warden env exec php-fpm bin/magento config:set --lock-env paypal/wpp/sandbox_flag 1 || true
warden env exec php-fpm bin/magento config:set --lock-env web/cookie/cookie_domain "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
warden env exec php-fpm bin/magento config:set --lock-env payment/checkmo/active 1 || true
warden env exec php-fpm bin/magento config:set --lock-env payment/stripe_payments/active 0 || true
warden env exec php-fpm bin/magento config:set --lock-env payment/stripe_payments_basic/stripe_mode test || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_recaptcha/backend/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_recaptcha/frontend/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_twofactorauth/general/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_twofactorauth/google/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_twofactorauth/u2fkey/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_twofactorauth/duo/enabled 0 || true
warden env exec php-fpm bin/magento config:set --lock-env msp_securitysuite_twofactorauth/authy/enabled 0 || true

:: Creating admin user
warden env exec php-fpm bin/magento admin:user:create \
    --admin-password=Admin123 \
    --admin-user=magento2docker \
    --admin-firstname=Admin \
    --admin-lastname=Admin \
    --admin-email="magento2docker@warden.test"