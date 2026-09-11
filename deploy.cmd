#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
assertDockerRunning

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/include

if ! declare -f deploy_static > /dev/null 2>&1; then
  function deploy_static() {
      warden env exec php-fpm mr dev:asset:clear > /dev/null 2>&1
      warden env exec php-fpm bin/magento setup:static-content:deploy -f
  }
fi

if ! declare -f deploy_full > /dev/null 2>&1; then
  function deploy_full() {
    warden env up
    warden env exec php-fpm composer install
    warden env exec php-fpm php vendor/bin/ece-patches apply || true > /dev/null 2>&1
    warden env exec php-fpm bin/magento setup:upgrade
    warden env exec php-fpm bin/magento setup:di:compile
    deploy_static
  }
fi
}

if [[ "$ENV_SOURCE_DEFAULT" -eq "1" ]]; then
    ENV_SOURCE_VAR="LOCAL"
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




