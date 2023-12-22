#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${ENV_SOURCE}\033[0m ..."
    magento-cloud mount:download -p "$CLOUD_PROJECT" \
        --environment="$ENV_SOURCE_HOST" \
        "${exclude_opts[@]}" \
        --mount=pub/media/ \
        --target=pub/media/ \
        -y \
        || true

}

function dumpPremise () {
    echo -e "⌛ \033[1;32mDownloading files from $ENV_SOURCE_HOST\033[0m ..."
    warden env exec php-fpm rsync -az --info=progress2 -e 'ssh -p '"$ENV_SOURCE_PORT" \
        "${exclude_opts[@]}" \
        $ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_DIR/pub/media/ pub/media/
}

DUMP_INCLUDE_PRODUCT=0

while (( "$#" )); do
    case "$1" in
        --include-product)
            DUMP_INCLUDE_PRODUCT=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

EXCLUDE=( 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' 'amasty/blog/cache' 'catalog/product.rm' 'catalog/product/cache' 'catalog/product/product' )

if [[ "$DUMP_INCLUDE_PRODUCT" -eq "0" ]]; then
  EXCLUDE+=('catalog/product')
fi

exclude_opts=()
for item in "${EXCLUDE[@]}"; do
    exclude_opts+=( --exclude="$item" )
done

if [ -z ${CLOUD_PROJECT+x} ]; then
    dumpPremise
else
    dumpCloud
fi

