#!/usr/bin/env bash
# vim: ts=4: sts=4: sw=4: nowrap: nu:

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

declare NUM_PEERS
declare CONF_FILE
declare YGG_CONF_FILE
declare DATA_DIR
declare SILENT
declare SCRIPT_DIR


declare normal_file updated_file

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

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

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-h, --help                  Print this help and exit
-v, --verbose               Print script debug info
-s, --silent                Less noise
-c, --conf-file file        Some flag description
-d, --data-dir  dir
-y, --ygg-conf-file file
-n, --num-peers N           Some param description
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
            -y | -ygg*)
                YGG_CONF_FILE="${2-}"
                shift
                ;;
            -d | --data?dir)
                DATA_DIR="${2-}"
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
    if [ -n "${normal_file}" ]; then
        rm "${normal_file}" 2>/dev/null || true
    fi
}

main() {
    SILENT=${SILENT:-0}
    NUM_PEERS=${NUM_PEERS:-8}
    DATA_DIR=${DATA_DIR:-'/var/lib/yggdrasil'}
    CONF_FILE=${CONF_FILE:-''}
	YGG_CONF_FILE=${YGG_CONF_FILE:-'/etc/yggdrasil.conf'}
    normal_file="${DATA_DIR}/$(basename "${YGG_CONF_FILE}").json"
    updated_file="${DATA_DIR}/$(basename "${YGG_CONF_FILE}").upd"

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
    normal_file="${DATA_DIR}/$(basename "${YGG_CONF_FILE}").json"
    updated_file="${DATA_DIR}/$(basename "${YGG_CONF_FILE}").upd"

    msg "NUM_PEERS: ${NUM_PEERS}"
    msg "CONF_FILE: ${CONF_FILE}"
    msg "YGG_CONF_FILE: ${YGG_CONF_FILE}"
    msg "DATA_DIR : ${DATA_DIR}"
    msg "SILENT   : ${SILENT}"

    if [ ! -d "${DATA_DIR}" ]; then
        msg "create data dir: ${DATA_DIR}"
        mkdir -p "${DATA_DIR}"
    fi
    ## cd "${DATA_DIR}" || die "cant cd: ${DATA_DIR}" 13
    if [ ! -w "${YGG_CONF_FILE}" ]; then
		die "cannot write: ${YGG_CONF_FILE}" 21
	fi

    if ! yggdrasil  -useconffile "${YGG_CONF_FILE}"  -normaliseconf -json > "${normal_file}" 2>/dev/null; then
        die "failed normalise conf: ${YGG_CONF_FILE}" $?
    fi

    export SILENT CONF_FILE DATA_DIR NUM_PEERS HOSTS_FILE PEERS_FILE
    export FASTEST_HOSTS_FILE FASTEST_PEERS_FILE FASTEST_PEERS_JSON_FILE
    if ! "${SCRIPT_DIR}/yggdrasil-peers-parse.sh" ; then
        die "Error in yggdrasil-peers-parse: $?" $?
    fi

    declare -i count_peers
    count_peers=$(wc -l < "${FASTEST_PEERS_FILE}")
    if [ "${count_peers}" -lt "${NUM_PEERS}" ]; then
        die "Number of peers less than ${NUM_PEERS}" 22
    fi

    jq --slurpfile peers "${FASTEST_PEERS_JSON_FILE}" '.Peers = $peers[]' "${normal_file}" > "${updated_file}"

    mv -- "${YGG_CONF_FILE}" "${YGG_CONF_FILE%.*}.conf.old"
    mv -- "${updated_file}" "${YGG_CONF_FILE}"

    #systemctl restart yggdrasil 
}

main "$@"

