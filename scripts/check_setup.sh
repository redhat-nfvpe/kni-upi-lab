#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

CONTAINTER_NAME="check"

set -o pipefail

usage() {
    cat <<-EOM
    Verifies a KNI Baremetal UPI install

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-v] [-m manfifest_dir] manifests|lookups|container|haproxy|ocp
            manifests   - Verify the content and completeness of the config manifests
            lookups     - Verify DNS lookup funtionality
            container   - Verify the health of all the support containers
            haproxy     - Verify the operation of haproxy
            ocp         - Verify the health of the ocp cluster 

    Options
        -v verbose
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
EOM
    exit 0
}

check_lookups() {
    local cluster_id="${FINAL_VALS[cluster_id]}"
    local cluster_domain="${FINAL_VALS[cluster_domain]}"

    declare -A LOOKUP_MAP=(
        ["api.$cluster_id.$cluster_domain."]="$(nthhost "$BM_IP_CIDR" 1)"
        ["api-int.$cluster_id.$cluster_domain."]="$(nthhost "$BM_IP_CIDR" 1)"
        ["$cluster_id-master-0.$cluster_domain."]="$(get_master_bm_ip 0)"
        ["$cluster_id-bootstrap.$cluster_domain."]="$(nthhost "$BM_IP_CIDR" 10)"
        ["foo.apps.test1.tt.testing."]="$(nthhost "$BM_IP_CIDR" 1)"
    )
    for srv in "" '@192.168.111.1'; do
        echo "srv = $srv"
        for addr in "${!LOOKUP_MAP[@]}"; do
        echo "addr = $addr"
            if ! res=$(dig $srv +short "$addr"); then
                printf "Failed lookup of %s\n" "$addr"
                exit 1
            fi
            if [[ ! $res =~ ${LOOKUP_MAP[$addr]} ]]; then
                printf "Lookup of %s failed for server ip \"%s\"" "$addr" "$srv"
                exit 1
            fi
        done
    done
}

check_container_status() {
    local name="$1"

    if inspect=$(podman inspect "$name"); then
        printf "Error checking the %s container!\n" "$name"
        exit 1
    fi
    if ! run_status=$(jq .[0].State.Running <<< "$inspect"); then
        printf "Error checking the %s container json!\n" "$name"
        exit 1
    fi
    if [[ "$run_status" =~ false ]]; then
        printf "%s container is not running...\n" "name"
        podman logs "$name"
        exit 1
    fi
}

check_containers() {
    check_container_status "dnsmasq_prov"
    check_container_status "dnsmasq_bm"
    check_container_status "akraino-haproxy"
    check_container_status "coredns"
    check_container_status "matchbox"
}

check_dnsmasq_prov() {
    return
}

check_dirs() {

    mkdir -p ~/.matchbox || exit 1
    mkdir -p "$MATCHBOX_DIR" || exit 1
    mkdir -p "$MATCHBOX_ETC_DIR" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB/assets" || exit 1
}

VERBOSE="false"
export VERBOSE

while getopts ":hm:v" opt; do
    case ${opt} in
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

MATCHBOX_ETC_DIR="$MATCHBOX_DATA_DIR/etc/matchbox"
MATCHBOX_VAR_LIB="$MATCHBOX_DATA_DIR/var/lib/matchbox"

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
    ;;
repo)
    make_clone
    ;;
lookup)
    check_lookups
    ;;
containers)
    check_containers
    ;;
start)
    start_matchbox
    ;;
stop)
    cid=$(podman stop "$CONTAINTER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$CONTAINTER_NAME" 2>/dev/null && podman rm "$CONTAINTER_NAME" >/dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
