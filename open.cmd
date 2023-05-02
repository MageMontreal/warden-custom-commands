#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

set -euo pipefail

function :: {
    echo
    echo -e "\033[32m$@\033[0m"
}

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?

loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?
eval "$(cat "${WARDEN_ENV_PATH}/.env" | sed 's/\r$//g' | grep "^CLOUD_")"
eval "$(cat "${WARDEN_ENV_PATH}/.env" | sed 's/\r$//g' | grep "^REMOTE_")"

assertDockerRunning

#OPEN=$(which xdg-open || which open || which start) || true

function rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
}

function array_contains() {
    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ $element == "$seeking" ]]; then
            in=0
            break
        fi
    done
    echo $in
}

function findLocalPort() {
    LOCAL_PORT=3306

    while [[ $(lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t) ]]; do
        LOCAL_PORT=$((LOCAL_PORT+1))
    done
}

function remote_db () {
    findLocalPort

    eval "ssh_host=\${"REMOTE_${ENV_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${ENV_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${ENV_VAR}_PORT"}"
    eval "remote_dir=\${"REMOTE_${ENV_VAR}_PATH"}"

    local db_info=$(ssh -p $ssh_port $ssh_user@$ssh_host 'php -r "\$a=include \"'"$remote_dir"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['host'];")
    local db_user=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['username'];")
    local db_pass=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['password'];")
    local db_name=$(den env exec php-fpm php -r "\$a=$db_info;echo \$a['dbname'];")

    #db_pass=$(rawurlencode $db_pass)
    DB="mysql://$db_user:$db_pass@127.0.0.1:$LOCAL_PORT/$db_name?compression=1"

    echo -e "SSH tunnel opened to \033[32m$db_name\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    #if [ -n "$OPEN" ]; then
    #    $OPEN $DB
    #fi

    ssh -L $LOCAL_PORT:"$db_host":3306 -N -p $ssh_port $ssh_user@$ssh_host || true
}
function local_db() {
    findLocalPort

    DB_ENV_NAME="$WARDEN_ENV_NAME"-db-1
    DB="mysql://magento:magento@127.0.0.1:$LOCAL_PORT/magento?compression=1"

    echo -e "SSH tunnel opened to \033[32m$DB_ENV_NAME\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    #if [ -n "$OPEN" ]; then
    #    $OPEN $DB
    #fi

    ssh -L "$LOCAL_PORT":"$DB_ENV_NAME":3306 -N -p 2222 user@tunnel.den.test || true
}
function cloud_db() {
    CLOUD_ENV=${!ENV_HOST}
    magento-cloud tunnel:single -e "$CLOUD_ENV" -p "$CLOUD_PROJECT" -r database
}

function local_shell() {
    den shell
}
function remote_shell() {
    eval "ssh_host=\${"REMOTE_${ENV_VAR}_HOST"}"
    eval "ssh_user=\${"REMOTE_${ENV_VAR}_USER"}"
    eval "ssh_port=\${"REMOTE_${ENV_VAR}_PORT"}"

    ssh -p $ssh_port $ssh_user@$ssh_host
}
function cloud_shell() {
    CLOUD_ENV=${!ENV_HOST}
    magento-cloud ssh -e "$CLOUD_ENV" -p "$CLOUD_PROJECT"
}

ENV_VAR="LOCAL"

while (( "$#" )); do
    case "$1" in
        --environment=*|-e=*|--e=*)
            ENV_VAR=$(echo "${1#*=}" | tr '[:lower:]' '[:upper:]')
            shift
            ;;
        --environment|--e|-e)
            ENV_VAR=$(echo "${2}" | tr '[:lower:]' '[:upper:]')
            shift 2
            ;;
        *)
            echo "Unrecognized argument '$1'"
            exit 2
            ;;
    esac
done

SERVICE=

if [ -z ${WARDEN_PARAMS[0]+x} ]; then
    echo "Please specify the service you want to open"
    exit 2
else
    SERVICE=${WARDEN_PARAMS[0]}
fi

VALID_SERVICES=( 'db' 'shell' )
IS_VALID=$(array_contains VALID_SERVICES "$SERVICE")

if [[ "$IS_VALID" -eq "1" ]]; then
    echo "Invalid service. Valid services: "
    echo "  ${VALID_SERVICES[*]}"
    exit 2
fi

if [[ "$ENV_VAR" == "PRODUCTION" ]]; then
    ENV_VAR="PROD"
elif [[ "$ENV_VAR" == "STAG" ]]; then
    ENV_VAR="STAGING"
elif [[ "$ENV_VAR" == "DEVELOP" || "$ENV_VAR" == "DEVELOPER" || "$ENV_VAR" == "DEVELOPMENT" ]]; then
    ENV_VAR="DEV"
fi

if [[ "$ENV_VAR" = "LOCAL" ]]; then
    local_"${SERVICE}"
else
    ENV_HOST="REMOTE_${ENV_VAR}_HOST"
    if [ -z ${!ENV_HOST+x} ]; then
        echo "Invalid environment '${ENV_VAR}'"
        exit 2
    fi
    if [ -z ${CLOUD_PROJECT+x} ]; then
        remote_"${SERVICE}"
    else
        cloud_"${SERVICE}"
    fi
fi
