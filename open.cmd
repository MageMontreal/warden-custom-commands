#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

SUBCOMMAND_DIR=$(dirname "${BASH_SOURCE[0]}")
source "${SUBCOMMAND_DIR}"/include

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

function open_link() {
    if [[ "$OPEN_CL" -eq "1" ]]; then
        OPEN=$(which xdg-open || which open || which start) || true
        if [ -n "$OPEN" ]; then
            $OPEN "${1}"
        fi
    fi
}

function findLocalPort() {
    LOCAL_PORT=$1

    while [[ $(lsof -Pi :$LOCAL_PORT -sTCP:LISTEN -t) ]]; do
        LOCAL_PORT=$((LOCAL_PORT+1))
    done
}

function remote_db () {
    REMOTE_PORT=3306
    findLocalPort $REMOTE_PORT

    local db_info=$(ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST 'php -r "\$a=include \"'"$ENV_SOURCE_DIR"'/app/etc/env.php\"; var_export(\$a[\"db\"][\"connection\"][\"default\"]);"')
    local db_host=$(php -r "\$a=$db_info;echo \$a['host'];")
    local db_user=$(php -r "\$a=$db_info;echo \$a['username'];")
    local db_pass=$(php -r "\$a=$db_info;echo \$a['password'];")
    local db_name=$(php -r "\$a=$db_info;echo \$a['dbname'];")

    DB="mysql://$db_user:$db_pass@127.0.0.1:$LOCAL_PORT/$db_name"

    echo -e "SSH tunnel opened to \033[32m$db_name\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $DB

    ssh -L $LOCAL_PORT:"$db_host":"$REMOTE_PORT" -N -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST || true
}
function local_db() {
    REMOTE_PORT=3306
    findLocalPort $REMOTE_PORT

    DB_ENV_NAME="$WARDEN_ENV_NAME"-db-1
    DB="mysql://magento:magento@127.0.0.1:$LOCAL_PORT/magento"

    echo -e "SSH tunnel opened to \033[32m$DB_ENV_NAME\033[0m at: \033[32m$DB\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $DB

    ssh -L "$LOCAL_PORT":"$DB_ENV_NAME":"$REMOTE_PORT" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}
function cloud_db() {
    magento-cloud tunnel:single -e "$ENV_SOURCE_HOST" -p "$CLOUD_PROJECT" -r database
}

function local_shell() {
    warden shell
}
function remote_shell() {
    ssh -p $ENV_SOURCE_PORT $ENV_SOURCE_USER@$ENV_SOURCE_HOST
}
function cloud_shell() {
    magento-cloud ssh -e "$ENV_SOURCE_HOST" -p "$CLOUD_PROJECT"
}
function local_sftp() {
    echo "Not Supported."
}
function remote_sftp() {
    SFTP_LINK="sftp://$ENV_SOURCE_USER@$ENV_SOURCE_HOST:$ENV_SOURCE_PORT$ENV_SOURCE_DIR"
    echo -e "SFTP to \033[32m$ENV_SOURCE_VAR\033[0m at: \033[32m$SFTP_LINK\033[0m"
    open_link $SFTP_LINK
}
function cloud_sftp() {
    SFTP_LINK="sftp://$(magento-cloud ssh --pipe -e "$ENV_SOURCE_HOST" -p "$CLOUD_PROJECT")"
    echo -e "SFTP to \033[32m$ENV_SOURCE_HOST\033[0m at: \033[32m$SFTP_LINK\033[0m"
    open_link $SFTP_LINK
}
function remote_web() {
    APP_DOMAIN="https://${TRAEFIK_SUBDOMAIN}.${TRAEFIK_DOMAIN}"
    echo -e "Local address: \033[32m$CLOUD_ENV\033[0m at: \033[32m$SFTP_LINK\033[0m"
    open_link $SFTP_LINK
}
function local_elasticsearch() {
    REMOTE_PORT=9200
    findLocalPort $REMOTE_PORT

    if [[ "$WARDEN_ELASTICSEARCH" -eq "1" ]] || [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
        if [[ "$WARDEN_OPENSEARCH" -eq "1" ]]; then
            ES_ENV_NAME="$WARDEN_ENV_NAME"-opensearch-1
        else
            ES_ENV_NAME="$WARDEN_ENV_NAME"-elasticsearch-1
        fi
    else
      echo "Elastic Search or Open Search not enabled for project"
      exit
    fi

    ES="http://localhost:$LOCAL_PORT"

    echo -e "Elastic Search tunnel opened to \033[32m$ES_ENV_NAME\033[0m at: \033[32m$ES\033[0m"
    echo
    echo "Quitting this command (with Ctrl+C or equivalent) will close the tunnel."
    echo

    open_link $ES

    ssh -L "$LOCAL_PORT":"$ES_ENV_NAME":"$REMOTE_PORT" -N -p 2222 -i ~/.warden/tunnel/ssh_key user@tunnel.warden.test || true
}
function remote_elasticsearch() {
    echo "Not yet supported."
    exit
}
function cloud_elasticsearch() {
    ES_ENV_NAME='elasticsearch'
    magento-cloud service:list \
      --project="$CLOUD_PROJECT" \
      --environment="$ENV_SOURCE_HOST" \
      --columns=name \
      --format=plain \
      --no-header | grep -q 'opensearch' && ES_ENV_NAME='opensearch'

    magento-cloud tunnel:single -e "$ENV_SOURCE_HOST" -p "$CLOUD_PROJECT" -r "$ES_ENV_NAME"
}

if [[ "$ENV_SOURCE_DEFAULT" -eq "1" ]]; then
    ENV_SOURCE_VAR="LOCAL"
fi

OPEN_CL=0

while (( "$#" )); do
    case "$1" in
        -a)
            OPEN_CL=1
            shift
            ;;
        *)
            shift
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

VALID_SERVICES=( 'db' 'shell' 'sftp' 'elasticsearch' 'opensearch' )
IS_VALID=$(array_contains VALID_SERVICES "$SERVICE")

if [[ "$IS_VALID" -eq "1" ]]; then
    echo "Invalid service. Valid services: "
    echo "  ${VALID_SERVICES[*]}"
    exit 2
fi

if [[ "$SERVICE" = "opensearch" ]]; then
    SERVICE="elasticsearch"
fi

if [[ "$ENV_SOURCE_VAR" = "LOCAL" ]]; then
    local_"${SERVICE}"
else
    if [ -z ${CLOUD_PROJECT+x} ]; then
        remote_"${SERVICE}"
    else
        cloud_"${SERVICE}"
    fi
fi
