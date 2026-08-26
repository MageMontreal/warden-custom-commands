#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1
assertDockerRunning

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")

warden sync-files "$@" -f pub/media/