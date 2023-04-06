#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

source "${SUBCOMMAND_DIR}"/include

EXCLUDE=( 'catalog/product/cache' 'tmp' 'itm' 'import' 'export' 'importexport' 'captcha' '*.gz' '*.zip' '*.tar' '*.7z' '*.sql' )
exclude_opts=()
for item in "${EXCLUDE[@]}"; do
    exclude_opts+=( --exclude="$item" )
done

function dumpCloud () {
    echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${DUMP_SOURCE}\033[0m ..."
    magento-cloud mount:download -p "$CLOUD_PROJECT" \
        --environment="$DUMP_SOURCE" \
        "${exclude_opts[@]}" \
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
        "${exclude_opts[@]}" \
        $ssh_user@$ssh_host:$remote_dir/pub/media/ pub/media/
}

DUMP_SOURCE_VAR=STAGING
DUMP_SOURCE="${DUMP_SOURCE:-staging}"

while (( "$#" )); do
    case "$1" in
        --environment=*)
            DUMP_SOURCE_VAR=$(echo "${1#*=}" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        *)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

DUMP_ENV="REMOTE_${DUMP_SOURCE_VAR}_HOST"
if [ -z ${!DUMP_ENV+x} ]; then
    echo "Invalid environment '${DUMP_SOURCE}'"
    exit 2
fi

DUMP_HOST=${!DUMP_ENV}

if [[ "${DUMP_HOST}" ]]; then
    if [[ "${DUMP_HOST}" = "CLOUD" ]]; then
        dumpCloud
    else
        dumpPremise
    fi
fi
