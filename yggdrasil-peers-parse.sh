#!/usr/bin/env bash
# vim: ts=4: sts=4: sw=4: nowrap: nu:

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

declare NUM_PEERS
declare CONF_FILE
declare DATA_DIR
declare SILENT
declare HOSTS_FILE
declare COUNTRIES
declare STATIC_PEERS

countries="
	europe/czechia
	europe/finland
	europe/france
	europe/germany
	europe/netherlands
	europe/poland
	europe/romania
	europe/russia
	europe/slovakia
	europe/sweden
	europe/ukraine
	europe/united-kingdom
	north-america/canada
	north-america/united-states
"

trimL() {
    # shellcheck disable=SC2001
    sed -e 's/^[[:space:]]*//'<<<"$@"
}

trimR() {
    # shellcheck disable=SC2001
    sed -e 's/[[:space:]]*$//'<<<"$@"
}

trim() {
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'<<<"$@"
}

join_by() {
    local IFS="$1"
    shift
    echo "$*"
}


msg() {
    if [ "${SILENT-0}" -le 0 ]; then
        printf "%s\n" "${1-}"  >&2
    fi
}

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}


list_peer_urls() {
    for country in ${COUNTRIES}
    do
        echo "https://raw.githubusercontent.com/yggdrasil-network/public-peers/master/${country}.md"
    done
}

function download_peer_files() {
    msg "Download peers files"
    declare DL
    if command -v wget >& /dev/null; then
        DL="wget -c --prefer-family=IPv4 --quiet --timeout=15"
    elif command -v curl >& /dev/null; then
        DL="curl --silent --connect-timeout=15 -O"
    else
        die "Cannot find curl or wget binary" 14
    fi

    pushd "${DATA_DIR}" > /dev/null
    for jj in $(list_peer_urls)
    do
        if $DL "${jj}" ; then
            msg "  OK : ${jj}"
        else
            msg "  FAIL : ${jj}"
        fi
    done
    popd > /dev/null


    msg "OK"
}


function make_peer_list() {
    msg "Parse peers"

    declare line proto host port param
    # shellcheck disable=SC2016
    declare -r MATCH_LINE='`(.*)`'
    declare -r MATCH_URL='^(tcp|tls)://(.*+):([0-9]{2,5})(\?(.*))*'

    while IFS='' read -r line
    do
        if [[ ! "${line}" =~ ${MATCH_LINE} ]]; then
            continue
        fi

        if [[ ! "${BASH_REMATCH[1]}" =~ $MATCH_URL ]]; then
            continue
        fi
        proto="${BASH_REMATCH[1]}"
        host="${BASH_REMATCH[2]}"
        port="${BASH_REMATCH[3]}"
        param="${BASH_REMATCH[5]}"
        echo "${proto}!${host}!${port}!${param}"
        #TODO: !!!!
    done < <(find "${DATA_DIR}" -maxdepth 1 -name '*.md' -type f -exec cat {} \;)
    msg "OK"
}

function make_hosts_list() {
    msg "Parse hosts"
    awk -F'!' '{ print $2 }' "${PEERS_FILE}" | sort -u > "${HOSTS_FILE}"
    msg "OK"
}

function get_failed_to_dial() {
    if command -v journalctl; then
        journalctl --unit=yggdrasil --no-pager --grep='Failed to dial' --since='-1d'
    else
        grep 'yggdrasil' /var/log/syslog | grep 'Failed to dial'
    fi
}

function make_failed_peers_list() {
    msg "Detect failed peers"
    get_failed_to_dial | \
        grep -oP '(TCP|TLS)\s+(.*)(?=: dial)' | \
        tr ':' '!' | \
        sort -u | \
        awk '{ print tolower($1)"!"$2"!"$3 }'
}

function make_fastest_hosts_list_ping() {
    declare nlines host
    msg "Find top ${NUM_PEERS} fastest hosts"

    nlines=$(wc -l < "${HOSTS_FILE}")
    for ((jj=1; jj < nlines; jj++)); do printf '.' >&2; done
    printf "\n" >&2

    while IFS='' read -r host
    do
        echo "$(ping -c1 "$host" 2>/dev/null | grep -oP '=\s*\K\d+') $host"
        printf '.' >&2
    done < "${HOSTS_FILE}" | sort -urn | head --lines="${NUM_PEERS}" > "${FASTEST_HOSTS_FILE}"
    printf "\n"  >&2
    msg "OK"
}

function make_fastest_hosts_list_fping() {
    msg "Find top ${NUM_PEERS} fastest hosts"
    (fping -q -a -c 16 --dontfrag --size=1250 -f "${HOSTS_FILE}" || true) 2>&1 | \
        awk -F'/' 'NF>=8 { print $8 ":" $0 } ' | \
        sort -n | \
        awk -F'[: ]' '{ print $2 }' | \
        head --lines="${NUM_PEERS}"  > "${FASTEST_HOSTS_FILE}"

    msg "OK"
}

function print_fastest_hosts_peers() {
    declare hosts mask
    readarray -t hosts < "${FASTEST_HOSTS_FILE}"
    mask="$(join_by \| "${hosts[@]}")"
    grep -P "${mask}" "${PEERS_FILE}"
}

make_fastest_peers_json() {

    declare -i count=0
    while IFS='' read -r line
    do
        if [ $count -gt 0 ]; then
            printf ",\n"
        else
            printf "[\n"
        fi
        printf "\t\"%s\"" "${line}"
        count=$((count + 1))
    done

    if [ $count -gt 0 ]; then
        printf "\n]\n"
    fi
}

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-s, --silent            Less noise
-c, --conf-file file    Some flag description
-d, --data-dir  dir
-n, --num-peers N       Some param description
-p, --peer              Add static peer
EOF
  exit
}

parse_params() {
    declare -i jj=1
    while ((jj <= $#)); do
        case "${!jj}" in
            --conf?file | -c)
                jj=$((jj + 1))
                CONF_FILE="${!jj}"
                #shellcheck disable=SC1090
                source "${CONF_FILE}" 2>/dev/null || die "cant read file: ${CONF_FILE}" 13
                ;;
            --silent | -s)
                SILENT=1
                ;;
        esac
        jj=$((jj + 1))
    done

    while :; do
        case "${1-}" in
            -h | --help) usage ;;
            -v | --verbose) set -x ;;
            # -f | --flag) flag=1 ;; # example flag
            -s | --silent) SILENT=1;;
            -n | --num?peers) # example named parameter
                NUM_PEERS="${2-}"
                shift
                ;;
            -c | --conf?file)
                #CONF_FILE="${2-}"
                shift
                ;;
            -d | --data?dir)
                DATA_DIR="${2-}"
                shift
                ;;
            -p | --peer)
                STATIC_PEERS="${2-} ${STATIC_PEERS}"
                shift
                ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done

  # check required params and arguments
  #[[ -z "${param-}" ]] && die "Missing required parameter: param"
  #[[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

  return 0
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    # script cleanup here
    find "${DATA_DIR}" -maxdepth 1 -name '*.md' -type f -delete 2>/dev/null || true
    rm "${HOSTS_FILE}" 2>/dev/null || true
    #rm "${HOSTS_FILE}" "${PEERS_FILE}" 2>/dev/null || true
}

main() {
    # script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
    SILENT=${SILENT:-0}
    NUM_PEERS=${NUM_PEERS:-8}
    DATA_DIR=${DATA_DIR:-"/var/lib/yggdrasil"}
	COUNTRIES="${COUNTRIES:-${countries}}"
    CONF_FILE=${CONF_FILE:-""}
    STATIC_PEERS=${STATIC_PEERS:-""}

    if [ -r "${CONF_FILE}" ]; then
        #shellcheck disable=SC1090
        source "${CONF_FILE}" 2>/dev/null || msg "cant read file: ${CONF_FILE}"
    fi


    parse_params "$@"

    HOSTS_FILE=${HOSTS_FILE:-"${DATA_DIR}/hosts.txt"}
    PEERS_FILE=${PEERS_FILE:-"${DATA_DIR}/peers.txt"}
    FASTEST_HOSTS_FILE=${FASTEST_HOSTS_FILE:-"${DATA_DIR}/hosts-fastest.txt"}
    FASTEST_PEERS_FILE=${FASTEST_PEERS_FILE:-"${DATA_DIR}/peers-fastest.txt"}
    FASTEST_PEERS_JSON_FILE=${FASTEST_PEERS_JSON_FILE:-"${DATA_DIR}/peers-fastest.json"}
    FAILED_PEERS_FILE=${FAILED_PEERS_FILE:-"${DATA_DIR}/peers-failed.txt"}

    msg "NUM_PEERS: ${NUM_PEERS}"
    msg "CONF_FILE: ${CONF_FILE}"
    msg "DATA_DIR : ${DATA_DIR}"
    msg "SILENT   : ${SILENT}"
	msg "COUNTRIES: ${COUNTRIES}"

    if [ ! -d "${DATA_DIR}" ]; then
        msg "create data dir: ${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
    fi

    rm "${HOSTS_FILE}" "${PEERS_FILE}" "${FASTEST_HOSTS_FILE}" "${FASTEST_PEERS_FILE}" "${FASTEST_PEERS_JSON_FILE}" >& /dev/null || true
    download_peer_files
    make_peer_list > "${PEERS_FILE}"
    make_failed_peers_list > "${FAILED_PEERS_FILE}"

    declare hosts peers mask tmp
    readarray -t peers < "${FAILED_PEERS_FILE}"
    mask="$(join_by \| "${peers[@]}")"

    tmp=$(mktemp "${DATA_DIR}/peers.XXXX")
    grep -vP "${mask}" "${PEERS_FILE}" > "${tmp}"
    mv "${tmp}" "${PEERS_FILE}"


    make_hosts_list
    if command -v fping >& /dev/null; then
        make_fastest_hosts_list_fping
    else
        make_fastest_hosts_list_ping
    fi

    if [ -n "${STATIC_PEERS}" ]; then
        for peer in ${STATIC_PEERS}; do
            printf "%s\n" "${peer}" >> "${FASTEST_PEERS_FILE}"
        done
    fi

    readarray -t hosts < "${FASTEST_HOSTS_FILE}"
    mask="$(join_by \| "${hosts[@]}")"
    grep -P "${mask}" "${PEERS_FILE}" | \
        while IFS='!' read -r proto host port param
        do
            if [ -n "$param" ]; then
                printf "%s://%s:%s?%s\n" "$proto" "$host" "$port" "$param"
            else
                printf "%s://%s:%s\n" "$proto" "$host" "$port"
            fi
        done >> "${FASTEST_PEERS_FILE}"


    make_fastest_peers_json < "${FASTEST_PEERS_FILE}" > "${FASTEST_PEERS_JSON_FILE}"

}

main "$@"
