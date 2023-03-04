#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
[[ ! ${DEN_DB_DUMP} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

set -euo pipefail

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?

# Load extra config values from .env file
eval "$(cat "${WARDEN_ENV_PATH}/.env" | sed 's/\r$//g' | grep "^ADOBE_")"

## verify Den version constraint
DEN_VERSION=$(den version 2>/dev/null) || true
DEN_REQUIRE=1.0.0-beta7
if ! test $(version ${DEN_VERSION}) -ge $(version ${DEN_REQUIRE}); then
  error "Den ${DEN_REQUIRE} or greater is required (version ${DEN_VERSION} is installed)"
  exit 3
fi

assertDockerRunning

cd "${WARDEN_ENV_PATH}"

DUMP_FILENAME=""
DUMP_SOURCE="${DUMP_SOURCE:-staging}"
PULL_DB=1
SKIP_RESTORE=0

while (( "$#" )); do
    case "$1" in
        -e|--environment)
            DUMP_SOURCE="${2:-staging}"
            shift 2
            ;;
        -e=*|--environment=*)
            DUMP_SOURCE="${1#*=}"
            shift
            ;;
        -f|--file)
            DUMP_FILENAME="$2"
            PULL_DB=0
            shift 2
            ;;
        -f=*|--file=*)
            DUMP_FILENAME="${1#*=}"
            PULL_DB=0
            shift
            ;;
        --skip-restore)
            SKIP_RESTORE=1
            shift
            ;;
        -*|--*|*)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

if [[ $SKIP_RESTORE = 1 && $PULL_DB = 0 ]]; then
    echo -e "😕 \033[36mDatabase is not being dumped and it is not being imported, so there is nothing to do\033[0m"
    exit 0
fi

if [[ $PULL_DB = 1 ]]; then
    DUMP_FILENAME="${WARDEN_ENV_NAME}_${DUMP_SOURCE}-`date +%Y%m%dT%H%M%S`.sql"
    RELATIONSHIP=database-slave

    echo -e "🤔 \033[1;34mChecking which database relationship to use ...\033[0m"
    EXISTS=$(magento-cloud environment:relationships \
        --project=$ADOBE_CLOUD_PROJECT_ID \
        --environment=$DUMP_SOURCE \
        --property=database-slave.0.host \
        2>/dev/null || true)
    [[ -z "$EXISTS" ]] && RELATIONSHIP=database

    echo -e "⌛ \033[1;32mDumping \033[33m${DUMP_SOURCE}\033[1;32m database ...\033[0m"
    magento-cloud db:dump \
        --project=$ADOBE_CLOUD_PROJECT_ID \
        --environment=$DUMP_SOURCE \
        --relationship=$RELATIONSHIP \
        --stdout \
        | sed 's/\/\*[^*]*DEFINER=[^*]*\*\///g' \
        > $DUMP_FILENAME
fi

# Invoke the import-db command if it's not skipped
[[ $SKIP_RESTORE = 0 ]] && den import-db --file "${DUMP_FILENAME}"

# Only remove the dump file if it was automatically downloaded and restored
if [[ $PULL_DB = 1 && $SKIP_RESTORE = 0 ]]; then
    echo -e "⚠️  \033[31mRemoving pulled database dump \033[33m${DUMP_FILENAME}\033[31m ...\033[0m"
    rm "$DUMP_FILENAME"
fi
