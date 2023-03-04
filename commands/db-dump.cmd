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

DEN_DB_DUMP=1
SUBCOMMAND=
declare PASSTHRU_PARAMS=()

while (( "$#" )); do
    case "$1" in
        --cloud|--adobe-cloud)
             SUBCOMMAND="db-dump-adobe-cloud"
            shift
            ;;
        --)
            echo "Stop parsing params flag found!"
            shift
            break
            ;;
        --skip-restore)
            PASSTHRU_PARAMS+=("--skip-restore")
            shift
            ;;
        *)
            PASSTHRU_PARAMS+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$SUBCOMMAND" ]]; then
    echo -e "😮 \033[31mMissing option to specify where to pull media from\033[0m"
    exit 1
fi

if [[ ${#PASSTHRU_PARAMS[@]} > 0 ]]; then
    set -- "${PASSTHRU_PARAMS[@]}" "$@"
else
    set -- "$@"
fi

if [[ -f "${WARDEN_ENV_PATH}/.warden/commands/${SUBCOMMAND}.cmd" ]]; then
    source "${WARDEN_ENV_PATH}/.warden/commands/${SUBCOMMAND}.cmd"
fi
