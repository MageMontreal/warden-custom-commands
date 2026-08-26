#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
assertDockerRunning

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function syncCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${ENV_SOURCE}\033[0m ..."
    magento-cloud mount:download -p "$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        "${exclude_opts[@]}" \
        --mount=pub/media/ \
        --target=pub/media/ \
        -y \
        || true
}

function syncPremise () {
    echo -e "⌛ \033[1;32mDownloading files from $ENV_SOURCE_HOST\033[0m ..."

    local src="${DUMP_FILENAME%/}"
    local dest_dir
    dest_dir=$(dirname "$src")
    warden env exec php-fpm mkdir -p "$dest_dir"

    warden env exec php-fpm rsync -az --info=progress2 -e 'ssh -p '"$ENV_SOURCE_PORT" \
        "${exclude_opts[@]}" \
        $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/"$src" "$dest_dir"/
}

DUMP_INCLUDE_PRODUCT=0
DUMP_FILENAME="pub/media/"
NO_EXCLUDE=0

while (( "$#" )); do
    case "$1" in
        --include-product)
            DUMP_INCLUDE_PRODUCT=1
            shift
            ;;
        --no-exclude)
          NO_EXCLUDE=1
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

EXCLUDE=(
    'tmp'
    'itm'
    'import'
    'export'
    'importexport'
    'captcha'
    'customer'
    'feeds'
    '*.gz'
    '*.zip'
    '*.tar'
    '*.7z'
    '*.sql'
    'amasty/blog/cache'
    'amasty/amoptimizer_dump'
    'amasty/amoptmobile'
    'amasty/amopttablet'
    'amasty/webp'
    'amasty/amcustomform'
    'aw_rma'
    'ulmod_gallerypro/cache'
    'resized'
    'mf_webp'
    'cache/dakzilla_intervention'
    'catalog/product.rm'
    'catalog/product/product'
    'customer_address'
    'feed'
)
exclude_opts=()

if [[ "$DUMP_INCLUDE_PRODUCT" -eq "0" ]]; then
    EXCLUDE+=('catalog/product')
else
    EXCLUDE+=('catalog/product/cache')
    EXCLUDE+=('amasty/amfile')
fi

if [[ -n "${PROJECT_FILES_EXCLUDE+1}" ]]; then
    EXCLUDE+=("${PROJECT_FILES_EXCLUDE[@]}")
fi

if [[ "$NO_EXCLUDE" -eq "0" ]]; then
  for item in "${EXCLUDE[@]}"; do
      exclude_opts+=( --exclude="$item" )
  done
fi

if [ -z ${CLOUD_PROJECT+x} ]; then
    syncPremise
else
    syncCloud
fi

