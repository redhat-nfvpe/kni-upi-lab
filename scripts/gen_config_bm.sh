#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

CONTAINER_NAME="kni-dnsmasq-bm"
CONTAINER_IMAGE="quay.io/poseidon/dnsmasq"

set -o pipefail

# Script to generate dnsmasq.conf for the baremetal network
#

usage() {
    cat <<-EOM
    Generate configuration files for the baremetal interface 
    Files created:
        dnsmasq.conf, dnsmasq.conf
    
    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the baremetal interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
EOM
}

gen_hostfile_bm() {
    out_dir=$1

    local cid

    hostsfile="$out_dir/$BM_ETC_DIR/dnsmasq.hostsfile"

    #list of master manifest

    printf "Generating %s...\n" "$hostsfile"

    cid="${CLUSTER_FINAL_VALS[cluster_id]}"
    cdomain="${CLUSTER_FINAL_VALS[cluster_domain]}"
    {
        printf "%s,%s,%s\n" "${CLUSTER_FINAL_VALS[bootstrap_sdn_mac_address]}" "$BM_IP_BOOTSTRAP" "$cid-bootstrap-0.$cdomain"
        printf "%s,%s,%s\n" "$(get_host_var "master-0" "sdnMacAddress")" "$(get_master_bm_ip 0)" "$cid-master-0.$cdomain"

    } >"$hostsfile"

    master1_mac=$(get_host_var "master-1" "sdnMacAddress")
    master2_mac=$(get_host_var "master-2" "sdnMacAddress")

    if [ -n "$master1_mac" ] && [ -z "$master2_mac" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    if [ -z "$master1_mac" ] && [ -n "$master2_mac" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    num_masters="${HOSTS_FINAL_VALS[master_count]}"

    if [ -n "$master1_mac" ] && [ -n "$master2_mac" ] && [ "$num_masters" -eq 3 ]; then
        {
            printf "%s,%s,%s\n" "$master1_mac" "$(get_master_bm_ip 1)" "$cid-master-1.$cdomain"
            printf "%s,%s,%s\n" "$master2_mac" "$(get_master_bm_ip 2)" "$cid-master-2.$cdomain"
        } >>"$hostsfile"
    fi

    IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
    for worker in "${workers[@]}"; do
        {
            index=${worker##*-}
            printf "%s,%s,%s\n" "$(get_host_var "$worker" sdnMacAddress)" "$(get_worker_bm_ip "$index")" "$cid-$worker.$cdomain"
        } >>"$hostsfile"
    done
}

gen_bm_help() {
    echo "# The container should be run as follows with the generated dnsmasq.conf file"
    echo "# located in $etc_dir/"
    echo "# an automatically generated dnsmasq hostsfile should also be present in"
    echo "# $etc_dir/"
    echo "#"
    echo "# podman run -d --name dnsmasq-bm --net=host\\"
    echo "#  -v $var_dir:/var/run/dnsmasq:Z \\"
    echo "#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
    echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
    echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\"
    echo "#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"
}

gen_config_bm() {
    intf="$1"
    out_dir="$2"

    etc_dir="$out_dir/$BM_ETC_DIR"
    var_dir="$out_dir/$BM_VAR_DIR"

    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"

    local out_file="$etc_dir/dnsmasq.conf"

    printf "Generating %s...\n" "$out_file"

    cat <<EOF >"$out_file"
# This config file is intended for use with a container instance of dnsmasq

$(gen_bm_help)
port=0
interface=$intf
bind-interfaces

strict-order
except-interface=lo

#domain=${CLUSTER_FINAL_VALS[cluster_domain]},$BM_IP_CIDR

dhcp-range=$BM_IP_RANGE_START,$BM_IP_RANGE_END,30m
#default gateway
dhcp-option=3,$CLUSTER_DEFAULT_GW
#dns server
dhcp-option=6,$BM_IP_NS

log-queries
log-dhcp

dhcp-no-override
dhcp-authoritative

dhcp-hostsfile=/etc/dnsmasq.d/dnsmasq.hostsfile
dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

EOF
}

gen_config() {
    local out_dir="$1"

    gen_config_bm "$BM_BRIDGE" "$out_dir"
    gen_hostfile_bm "$out_dir"
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
shift $((OPTIND - 1))

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="bm"
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$DNSMASQ_DIR}
out_dir=$(realpath "$out_dir")

case "$COMMAND" in
bm | config)
    gen_variables "$manifest_dir"
    gen_config "$out_dir"
    ;;
start)
    if [[ $PROVIDE_DHCP =~ true ]]; then
        podman_exists "$CONTAINER_NAME" &&
            (podman_rm "$CONTAINER_NAME" ||
                printf "Could not remove %s!\n" "$CONTAINER_NAME")

        if ! cid=$(sudo podman run -d --name "$CONTAINER_NAME" --net=host \
            -v "$PROJECT_DIR/dnsmasq/bm/var/run:/var/run/dnsmasq:Z" \
            -v "$PROJECT_DIR/dnsmasq/bm/etc/dnsmasq.d:/etc/dnsmasq.d:Z" \
            --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 \
            --expose=69/udp --cap-add=NET_ADMIN "$CONTAINER_IMAGE" \
            --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q); then
            printf "Could not start %s container!\n" "$CONTAINER_NAME"
            exit 1
        fi

        podman_isrunning_logs "$CONTAINER_NAME" && printf "Started %s as %s...\n" "$CONTAINER_NAME" "$cid"
    fi
    ;;
stop)
    podman_stop "$CONTAINER_NAME" && printf "Stopped %s\n" "$CONTAINER_NAME" || exit 1
    ;;
remove)
    podman_rm "$CONTAINER_NAME" && printf "Removed %s\n" "$CONTAINER_NAME" || exit 1
    ;;
isrunning)
    if ! podman_isrunning "$CONTAINER_NAME"; then
        printf "%s is NOT running...\n" "$CONTAINER_NAME"
        exit 1
    else
        printf "%s is running...\n" "$CONTAINER_NAME"
    fi
    ;;
*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
