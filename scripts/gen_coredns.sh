#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

COREDNS_CONTAINTER_NAME="coredns"

set -o pipefail

usage() {
    cat <<-EOM
    Generate an Coredns/db config files for Coredns

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir] [-o out_dir] corefile|db|start|stop|remove
            corefile - Generate Corefile file for Coredns
            db       - Generate db file for Coredns
            start    - Start the coredns container 
            stop     - Stop the coredns container
            remove   - Stop and remove the coredns container

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/coredns/...]
EOM
    exit 0
}

gen_config_corefile() {
    local out_dir="$1"
    local cfg_file="$out_dir/Corefile"
    local cluster_id="${FINAL_VALS[cluster_id]}"
    local cluster_domain="${FINAL_VALS[cluster_domain]}"

    mkdir -p "$out_dir"

    cat <<EOF >"$cfg_file"
.:53 {
    log
    errors
    forward . 10.11.5.19
}

$cluster_domain:53 {
    log
    errors
    file /etc/coredns/db.$cluster_domain
    debug
}
EOF
    echo "$cfg_file"
}

gen_config_db() {
    local out_dir="$1"
    local cluster_id="${FINAL_VALS[cluster_id]}"
    local cluster_domain="${FINAL_VALS[cluster_domain]}"
    local cfg_file="$out_dir/db.$cluster_domain"

    mkdir -p "$out_dir"

    cat <<EOF >"$cfg_file"
\$ORIGIN $cluster_domain.
\$TTL 10800      ; 3 hours
@       3600 IN SOA sns.dns.icann.org. noc.dns.icann.org. (
                                2019010101 ; serial
                                7200       ; refresh (2 hours)
                                3600       ; retry (1 hour)
                                1209600    ; expire (2 weeks)
                                3600       ; minimum (1 hour)
                                )

_etcd-server-ssl._tcp.$cluster_id.$cluster_domain. 8640 IN    SRV 0 10 2380 etcd-0.$cluster_id.$cluster_domain.
EOF

    # shellcheck disable=SC2129
    {
        if [ "${FINAL_VALS[master_count]}" = 3 ] &&
            [ -n "${FINAL_VALS[master\-1.spec.bootMACAddress]}" ] &&
            [ -n "${FINAL_VALS[master\-2.spec.bootMACAddress]}" ]; then
            printf "                                                   SRV 0 10 2380 etcd-1.%s.%s.\n" "$cluster_id" "$cluster_domain"
            printf "                                                   SRV 0 10 2380 etcd-2.%s.%s.\n" "$cluster_id" "$cluster_domain"
        fi
        printf "\n"
    } >>"$cfg_file"

    cat <<EOF >>"$cfg_file"
api.$cluster_id.$cluster_domain.                        A $(nthhost "$BM_IP_CIDR" 1)
api-int.$cluster_id.$cluster_domain.                    A $(nthhost "$BM_IP_CIDR" 1)
$cluster_id-master-0.$cluster_domain.                   A $(get_master_bm_ip 0)
EOF

    {
        if [ "${FINAL_VALS[master_count]}" = 3 ] &&
            [ -n "${FINAL_VALS[master\-1.spec.bootMACAddress]}" ] &&
            [ -n "${FINAL_VALS[master\-2.spec.bootMACAddress]}" ]; then
            printf "%s-master-1.%s.                   A %s\n" "$cluster_id" "$cluster_domain" "$(get_master_bm_ip 1)"
            printf "%s-master-1.%s.                   A %s\n" "$cluster_id" "$cluster_domain" "$(get_master_bm_ip 1)"
        fi
    } >>"$cfg_file"

    cat <<EOF >>"$cfg_file"
$cluster_id-worker-0.$cluster_domain.                   A $(get_worker_bm_ip 0)
$cluster_id-bootstrap.$cluster_domain.                  A $(nthhost "$BM_IP_CIDR" 10)
etcd-0.$cluster_id.$cluster_domain.                     IN  CNAME $cluster_id-master-0.$cluster_domain.

\$ORIGIN apps.$cluster_id.$cluster_domain.
*                                                    A                $(nthhost "$BM_IP_CIDR" 1)
EOF
    echo "$cfg_file"
}

gen_config() {
    local out_dir="$1"

    ofile=$(gen_config_corefile "$out_dir")
    printf "Generated %s...\n" "$ofile"

    ofile=$(gen_config_db "$out_dir")
    printf "Generated %s...\n" "$ofile"
}

VERBOSE="false"
export VERBOSE

while getopts ":ho:m:v" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="all"
fi

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

# shellcheck disable=SC1091
source "common.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

prep_host_setup_src="$manifest_dir/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$COREDNS_DIR}
out_dir=$(realpath "$out_dir")

parse_manifests "$manifest_dir"

map_cluster_vars

case "$COMMAND" in
all)
    gen_config "$out_dir"
    ;;
corefile)
    ofile=$(gen_config_corefile "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
db)
    ofile=$(gen_config_db "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
start)
    if podman ps --all | grep "$COREDNS_CONTAINTER_NAME" >/dev/null; then
        printf "Container already exists, removing and starting...\n"
        podman stop "$COREDNS_CONTAINTER_NAME" >/dev/null 2>&1
        if ! podman rm "$COREDNS_CONTAINTER_NAME" >/dev/null; then
            printf "Could not remove \"%s\"" "$COREDNS_CONTAINTER_NAME"
            exit 1
        fi
    fi
    if ! cid=$(podman run -d --expose=53/udp --name "$COREDNS_CONTAINTER_NAME" \
        -p "$(nthhost "$BM_IP_CIDR" 1):53:53" -p "$(nthhost "$BM_IP_CIDR" 1):53:53/udp" \
        -v "$PROJECT_DIR/coredns:/etc/coredns:z" --name coredns coredns/coredns:latest \
        -conf /etc/coredns/Corefile); then
        printf "Could not start coredns container!\n"
        exit 1
    fi
    run_status=$(podman inspect $COREDNS_CONTAINTER_NAME | jq .[0].State.Running)
    if [[ "$run_status" =~ false ]]; then
        printf "Failed to start container...\n"
        podman logs "$COREDNS_CONTAINTER_NAME"
    else
        printf "Started %s as id %s\n" "$DNSMASQ_CONTAINER_NAME" "$cid"
    fi
    ;;
stop)
    cid=$(podman stop "$COREDNS_CONTAINTER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$COREDNS_CONTAINTER_NAME" 2>/dev/null && podman rm "$COREDNS_CONTAINTER_NAME" >/dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
