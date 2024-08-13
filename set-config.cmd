#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function before_set_config() { :; }
function after_set_config() { :; }

ENV_HOOKS_FILE="${WARDEN_ENV_PATH}/.warden/hooks"
if [ -f "${ENV_HOOKS_FILE}" ]; then
    source "${ENV_HOOKS_FILE}"
fi

:: Importing config
warden env exec php-fpm bin/magento app:config:import || true

if [[ "$WARDEN_VARNISH" -eq "1" ]]; then
    :: Configuring Varnish
    warden env exec php-fpm bin/magento config:set -q --lock-env system/full_page_cache/varnish/backend_host varnish
    warden env exec php-fpm bin/magento config:set -q --lock-env system/full_page_cache/varnish/backend_port 80
    warden env exec php-fpm bin/magento config:set -q --lock-env system/full_page_cache/caching_application 2
    warden env exec php-fpm bin/magento config:set -q --lock-env system/full_page_cache/ttl 604800
    warden env exec php-fpm bin/magento setup:config:set -q --http-cache-hosts=varnish:80
    ::: Done
else
    warden env exec php-fpm bin/magento config:set -q --lock-env system/full_page_cache/caching_application 1
fi

if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
    if [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
        :: Configuring OpenSearch
        ELASTICSEARCH_HOSTNAME="opensearch"
        ELASTICSEARCH_ENGINE="opensearch"
        MAGENTO_VERSION=$(warden env exec php-fpm bin/magento --version | awk '{print $3}')
        if ! test "$(version "${MAGENTO_VERSION}")" -ge "$(version "2.4.6")"; then
           ELASTICSEARCH_ENGINE="elasticsearch7"
        fi
    else
        :: Configuring ElasticSearch
        ELASTICSEARCH_HOSTNAME="elasticsearch"
        ELASTICSEARCH_ENGINE="elasticsearch7"
    fi

    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/engine $ELASTICSEARCH_ENGINE
    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_hostname $ELASTICSEARCH_HOSTNAME
    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_port 9200
    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_index_prefix magento2
    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_enable_auth 0
    warden env exec php-fpm bin/magento config:set -q --lock-env catalog/search/${ELASTICSEARCH_ENGINE}_server_timeout 15
    ::: Done
fi

if [[ "$WARDEN_REDIS" -eq "1" ]]; then
    :: Configuring Redis
    warden redis flushall
    warden env exec php-fpm bin/magento setup:config:set -q --cache-backend=redis --cache-backend-redis-server=redis --cache-backend-redis-db=0 --cache-backend-redis-port=6379 --no-interaction
    warden env exec php-fpm bin/magento setup:config:set -q --page-cache=redis --page-cache-redis-server=redis --page-cache-redis-db=1 --page-cache-redis-port=6379 --no-interaction
    warden env exec php-fpm bin/magento setup:config:set -q --session-save=redis --session-save-redis-host=redis --session-save-redis-max-concurrency=20 --session-save-redis-db=2 --session-save-redis-port=6379 --no-interaction
    ::: Done
fi

:: Upgrading database
warden env exec php-fpm bin/magento setup:upgrade
::: Done

:: Configuring application
before_set_config
warden db connect -e "UPDATE ${REMOTE_DB_PREFIX}core_config_data SET value = 'https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/' WHERE path IN('web/secure/base_url','web/unsecure/base_url','web/unsecure/base_link_url','web/secure/base_link_url')"
warden db connect -e "DELETE FROM ${REMOTE_DB_PREFIX}core_config_data WHERE path IN('web/secure/base_static_url','web/secure/base_media_url','web/unsecure/base_static_url','web/unsecure/base_media_url')"

warden env exec php-fpm bin/magento config:set -q --lock-env web/unsecure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"
warden env exec php-fpm bin/magento config:set -q --lock-env web/secure/base_url "https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}/"

warden env exec php-fpm bin/magento config:set -q --lock-env web/secure/offloader_header X-Forwarded-Proto || true
warden env exec php-fpm bin/magento config:set -q --lock-env klaviyo_reclaim_general/general/enable 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env klaviyo_reclaim_webhook/klaviyo_webhooks/using_product_delete_before_webhook 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env paypal/wpp/sandbox_flag 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env web/cookie/cookie_domain "${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}" || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/checkmo/active 1 || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/stripe_payments/active 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env payment/stripe_payments_basic/stripe_mode test || true
warden env exec php-fpm bin/magento config:set -q --lock-env admin/captcha/enable 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_recaptcha/backend/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_recaptcha/frontend/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/general/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/google/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/u2fkey/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/duo/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env msp_securitysuite_twofactorauth/authy/enabled 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_invisible/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_invisible/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha_v3/public_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env recaptcha_frontend/type_recaptcha_v3/private_key '' || true
warden env exec php-fpm bin/magento config:set -q --lock-env google/analytics/active 0 || true
warden env exec php-fpm bin/magento config:set -q --lock-env google/adwords/active 0 || true
after_set_config
::: Done

:: Creating admin user
warden env exec php-fpm bin/magento admin:user:create \
    --admin-password=Admin123 \
    --admin-user=magento2docker \
    --admin-firstname=Admin \
    --admin-lastname=Admin \
    --admin-email="magento2docker@warden.test"