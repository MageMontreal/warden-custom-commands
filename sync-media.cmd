#!/usr/bin/env bash
SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${DUMP_SOURCE}\033[0m ..."
    magento-cloud mount:download -p $CLOUD_PROJECT \
        --environment=$DUMP_SOURCE \
        --exclude 'catalog/product/cache' \
        --exclude 'tmp' \
        --exclude 'itm' \
        --exclude 'import' \
        --exclude 'export' \
        --exclude 'importexport' \
        --exclude 'captcha' \
        --exclude '*.gz' \
        --exclude '*.zip' \
        --exclude '*.tar' \
        --exclude '*.7z' \
        --exclude '*.sql' \
        --mount=pub/media/ \
        --target=pub/media/ \
        -y \
        || true

}

function dumpPremise () {
    eval "ssh_host=\${"REMOTE_${DUMP_SOURCE_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${DUMP_SOURCE_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${DUMP_SOURCE_VAR}_PORT"}"
    eval "remote_dir=\${"REMOTE_${DUMP_SOURCE_VAR}_PATH"}"

    echo -e "⌛ \033[1;32mDownloading files from ${ssh_host}\033[0m ..."
    rsync -azvP -e 'ssh -p '"$ssh_port" \
        --exclude 'catalog/product/cache' \
        --exclude 'tmp' \
        --exclude 'itm' \
        --exclude 'import' \
        --exclude 'export' \
        --exclude 'importexport' \
        --exclude 'captcha' \
        --exclude '*.gz' \
        --exclude '*.zip' \
        --exclude '*.tar' \
        --exclude '*.7z' \
        --exclude '*.sql' \
        $ssh_user@$ssh_host:$remote_dir/pub/media/ pub/media/
}

DUMP_SOURCE="${DUMP_SOURCE:-STAGING}"

while (( "$#" )); do
    case "$1" in
        -e|--environment)
            DUMP_SOURCE_VAR=$(echo "${2:-staging}" | tr '[:lower:]' '[:upper:]')
            DUMP_ENV="REMOTE_${DUMP_SOURCE_VAR}_HOST"

            if [ -z ${!DUMP_ENV+x} ]; then
                error "Invalid environment '${DUMP_SOURCE}'"
            fi

            DUMP_HOST=${!DUMP_ENV}

            if [[ "${DUMP_HOST}" = "CLOUD" ]]; then
                dumpCloud
            else
                dumpPremise
            fi
            shift 2
            ;;
        -*|--*|*)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done
