#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/include

function deploy_static() {
    warden shell -c "mr dev:asset:clear"
    warden env exec php-fpm bin/magento setup:static-content:deploy -f
}

function deploy_full() {
  warden shell -c "composer install"
  warden shell -c "php vendor/bin/ece-patches apply" || true
  warden shell -c "bin/magento setup:upgrade"
  warden shell -c "bin/magento setup:di:compile"
  deploy_static
}

ENV_HOOKS_FILE="${WARDEN_ENV_PATH}/.warden/hooks"
if [ -f "${ENV_HOOKS_FILE}" ]; then
    source "${ENV_HOOKS_FILE}"
fi

while (( "$#" )); do
    case "$1" in
        *)
            shift
            ;;
    esac
done

if [ -z ${WARDEN_PARAMS[0]+x} ]; then
    OPTION='full'
else
  OPTION=${WARDEN_PARAMS[0]}
fi

VALID_OPTIONS=( 'full' 'static' )
IS_VALID=$(array_contains VALID_OPTIONS "$OPTION")

if [[ "$IS_VALID" -eq "1" ]]; then
    echo "Invalid option. Valid options: "
    echo "  ${VALID_OPTIONS[*]}"
    exit 2
fi

deploy_"${OPTION}"




