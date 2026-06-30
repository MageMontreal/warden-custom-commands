#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
assertDockerRunning

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

## configure command defaults
REQUIRED_FILES=("${WARDEN_ENV_PATH}/auth.json" "${WARDEN_ENV_PATH}/app/etc/config.php")
DB_DUMP=
DB_IMPORT=1
DB_DUMP_OPTIONS=
AUTO_PULL=1
MEDIA_SYNC=1
COMPOSER_INSTALL=1

## parse arguments
while (( "$#" )); do
    case "$1" in
        --skip-db-import)
            DB_IMPORT=
            shift
            ;;
        --skip-media-sync)
            MEDIA_SYNC=
            shift
            ;;
        --skip-composer-install)
            COMPOSER_INSTALL=
            shift
            ;;
        --no-pull)
            AUTO_PULL=
            shift
            ;;
        --db-dump=*)
            DB_DUMP="${1#*=}"
            shift
            ;;
        --include-customer-data)
            DB_DUMP_OPTIONS="-c"
            shift
            ;;
        --include-order-data)
            DB_DUMP_OPTIONS="-o"
            shift
            ;;
        --include-product)
            DB_DUMP_OPTIONS="-o"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

## include check for DB_DUMP file only when database import is expected
[[ ${DB_IMPORT} ]] && [[ "$DB_DUMP" ]] && REQUIRED_FILES+=("${DB_DUMP}")

:: Verifying configuration
INIT_ERROR=

## attempt to install mutagen if not already present
if [[ $OSTYPE =~ ^darwin ]] && ! which mutagen >/dev/null 2>&1 && which brew >/dev/null 2>&1; then
    warning "Mutagen could not be found; attempting install via brew."
    brew install havoc-io/mutagen/mutagen
fi

## verify mutagen version constraint
if [[ $OSTYPE =~ ^darwin ]]; then
    MUTAGEN_VERSION=$(mutagen version 2>/dev/null) || true
    MUTAGEN_REQUIRE=0.11.4
    if ! test "$(version "${MUTAGEN_VERSION}")" -ge "$(version "${MUTAGEN_REQUIRE}")"; then
      error "Mutagen ${MUTAGEN_REQUIRE} or greater is required (version ${MUTAGEN_VERSION} is installed)"
      INIT_ERROR=1
    fi
fi

## verify PHP version constraint
SYSTEM_PHP_VERSION=$(php -v | awk 'NR<=1{ print $2 }' 2>/dev/null) || true
PHP_REQUIRE=8.1.0
if ! test "$(version "${SYSTEM_PHP_VERSION}")" -ge "$(version "${PHP_REQUIRE}")"; then
  error "PHP ${PHP_REQUIRE} or greater is required (version ${SYSTEM_PHP_VERSION} is installed)"
  INIT_ERROR=1
fi

## check for presence of local configuration files to ensure they exist
for REQUIRED_FILE in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${REQUIRED_FILE}" ]]; then
    error "Missing local file: ${REQUIRED_FILE}"
    INIT_ERROR=1
  fi
done

## exit script if there are any missing dependencies or configuration files
[[ ${INIT_ERROR} ]] && exit 1

:: Starting Warden
warden svc up
if [[ ! -f ~/.warden/ssl/certs/${TRAEFIK_DOMAIN}.crt.pem ]]; then
    warden sign-certificate ${TRAEFIK_DOMAIN}
fi

:: Initializing environment
warden env up

## wait for mariadb to start listening for connections
warden shell -c "while ! nc -z db 3306 </dev/null; do sleep 2; done"

if [[ $COMPOSER_INSTALL ]]; then
    :: Installing dependencies
    warden env exec php-fpm composer install
fi

## import database only if --skip-db-import is not specified
if [[ ${DB_IMPORT} ]]; then
    if [[ -z "$DB_DUMP" ]]; then
        if [ ! -d "var" ]; then
            mkdir var
        fi
        DB_DUMP="var/${WARDEN_ENV_NAME}_${ENV_SOURCE}-`date +%Y%m%dT%H%M%S`.sql.gz"
        :: Get database
        warden db-dump --file="${DB_DUMP}" -e "$ENV_SOURCE" "$DB_DUMP_OPTIONS"
    fi

    if [[ "$DB_DUMP" ]]; then
        :: Importing database
        warden import-db --file="${DB_DUMP}"
    fi
fi

warden set-config

:: Flushing cache
warden env exec php-fpm bin/magento cache:flush

if [[ $MEDIA_SYNC ]]; then
    :: Sync Media
    warden sync-media -e "$ENV_SOURCE"
fi

echo "Configuration done."
echo "Frontend: ${URL_FRONT}"
echo "Admin:    ${URL_ADMIN}"
echo "Username: magento2docker"
echo "Password: Admin123"
