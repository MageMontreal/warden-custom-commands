#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

set -euo pipefail

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?

## verify Den version constraint
DEN_VERSION=$(den version 2>/dev/null) || true
DEN_REQUIRE=1.0.0
if ! test $(version ${DEN_VERSION}) -ge $(version ${DEN_REQUIRE}); then
  error "Den ${DEN_REQUIRE} or greater is required (version ${DEN_VERSION} is installed)"
  exit 3
fi

assertDockerRunning

cd "${WARDEN_ENV_PATH}"

DUMP_FILENAME=""
GZIPPED=0
PV=`which pv || which cat`

while (( "$#" )); do
    case "$1" in
        -f|--file)
            DUMP_FILENAME="$2"
            shift 2
            ;;
        -f=*|--file=*)
            DUMP_FILENAME="${1#*=}"
            shift
            ;;
        --gzipped)
            GZIPPED=1
            shift
            ;;
        -*|--*|*)
            error "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

# Ensure the database service is started for this environment
launchedDatabaseContainer=0
DB_CONTAINER_ID=$(den env ps --filter status=running -q db 2>/dev/null || true)
if [[ -z "$DB_CONTAINER_ID" ]]; then
  den env up db
  DB_CONTAINER_ID=$(den env ps --filter status=running -q db 2>/dev/null || true)
  if [[ -z "$DB_CONTAINER_ID" ]]; then
    echo -e "😮 \033[31mDatabase container failed to start\033[0m"
    exit 1
  fi
  launchedDatabaseContainer=1
fi

echo -e "⌛ \033[1;32mDropping and initializing docker database ...\033[0m"
den db connect -e 'drop database magento; create database magento character set = "utf8" collate = "utf8_general_ci";'

echo -e "🔥 \033[1;32mImporting database ...\033[0m"
[[ $GZIPPED = 1 ]] && $PV "$DUMP_FILENAME" | gunzip -c | den db import
[[ $GZIPPED = 0 ]] && $PV "$DUMP_FILENAME" | den db import

[[ $launchedDatabaseContainer = 1 ]] && den env stop db

echo -e "✅ \033[32mDatabase import complete!\033[0m"
