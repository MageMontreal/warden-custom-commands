#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
[[ ! ${DEN_MEDIA_SYNC} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

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

PROJECT_ENVIRONMENT=""

while (( "$#" )); do
    case "$1" in
        --environment)
            PROJECT_ENVIRONMENT="$2"
            shift 2
            ;;
        -*|--*|*)
            error "Unrecognized sync media (cloud) argument '$1'"
            exit 1
            ;;
    esac
done

echo -e "\033[1;32mDownloading files from \033[33mAdobe Commerce Cloud \033[1;36m${PROJECT_ENVIRONMENT}\033[0m ..."
magento-cloud mount:download -p $ADOBE_CLOUD_PROJECT_ID \
    --environment="${PROJECT_ENVIRONMENT:-staging}" \
    --exclude="cache/*" \
    --mount=pub/media/ \
    --target=pub/media/ \
    -y \
    || true
