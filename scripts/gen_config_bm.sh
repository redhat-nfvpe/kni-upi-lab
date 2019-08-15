#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

DNSMASQ_CONTAINER_NAME="dnsmasq-bm"
DNSMASQ_CONTAINER_IMAGE="quay.io/poseidon/dnsmasq"

# Script to generate dnsmasq.conf for the baremetal network
# This script is intended to be called from a master script in the
# base project or to be run from the base project directory
# i.e
#  prep_bm_host.sh calls scripts/gen_config_prov.sh
#  or
#  [basedir]./scripts/gen_config_prov.sh
#

usage() {
    cat <<-EOM
    Generate configuration files for the baremetal interface 
    Files created:
        dnsmasq.conf, dnsmasq.conf
    
    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-s prep_bm_host.src] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the baremetal interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
        -s [./../prep_host_setup.src -- Location of the config file for host prep
            Default to $PROJECT_DIR/cluster//prep_host_setup.src
EOM
}

gen_hostfile_bm() {
    out_dir=$1

    hostsfile="$out_dir/$BM_ETC_DIR/dnsmasq.hostsfile"

    #list of master manifest
    printf "Generating %s...\n" "$hostsfile"

    cid="${FINAL_VALS[cluster_id]}"
    cdomain="${FINAL_VALS[cluster_domain]}"

    echo "${FINAL_VALS[bootstrap_sdn_mac_address]},$BM_IP_BOOTSTRAP,$cid-bootstrap-0.$cdomain" >"$hostsfile"
    #  master - 0.spec.public_mac
    echo "${FINAL_VALS[master\-0.spec.public_mac]},$(get_master_bm_ip 0),$cid-master-0.$cdomain" >>"$hostsfile"

    if [ -n "${FINAL_VALS[master\-1.spec.public_mac]}" ] && [ -z "${FINAL_VALS[master\-2.spec.public_mac]}" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    if [ -z "${FINAL_VALS[master\-1.spec.public_mac]}" ] && [ -n "${FINAL_VALS[master\-2.spec.public_mac]}" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    if [ -n "${FINAL_VALS[master\-1.spec.public_mac]}" ] && [ -n "${FINAL_VALS[master\-2.spec.public_mac]}" ]; then
        echo "${FINAL_VALS[master\-1.spec.bootMACAddress]},$(get_master_bm_ip 1),$cid-master-1.$cdomain" >>"$hostsfile"
        echo "${FINAL_VALS[master\-2.spec.bootMACAddress]},$(get_master_bm_ip 2),$cid-master-2.$cdomain" >>"$hostsfile"
    fi

    # generate hostfile entries for workers
    # how?
    #num_masters="${FINAL_VALS[master_count]}"
    # for ((i = 0; i < num_masters; i++)); do
    #     m="master-$i"
    #     printf "    name: \"%s\"\n" "${FINAL_VALS[$m.metadata.name]}" | sudo tee -a "$ofile"
    #     printf "    public_ipv4: \"%s\"\n" "$(get_master_bm_ip $i)" | sudo tee -a "$ofile"
    #     printf "    ipmi_host: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.address]}" | sudo tee -a "$ofile"
    #     printf "    ipmi_user: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.user]}" | sudo tee -a "$ofile"
    #     printf "    ipmi_pass: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.password]}" | sudo tee -a "$ofile"
    #     printf "    mac_address: \"%s\"\n" "${FINAL_VALS[$m.spec.bootMACAddress]}" | sudo tee -a "$ofile"
    #
    # done
    #    cat <<EOF >>"$hostsfile"
    # 192.168.111.20,${FINAL_VALS[cluster_id]}-worker-0.${FINAL_VALS[cluster_domain]}
    # EOF

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

#domain=${FINAL_VALS[cluster_domain]},$BM_IP_CIDR

dhcp-range=$BM_IP_RANGE_START,$BM_IP_RANGE_END,30m
#default gateway
dhcp-option=3,$BM_IP_NS
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

while getopts ":ho:s:m:v" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
        ;;
    s)
        prep_host_setup_src=$OPTARG
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
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

prep_host_setup_src="$manifest_dir/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$DNSMASQ_DIR}
out_dir=$(realpath "$out_dir")

parse_manifests "$manifest_dir"

map_cluster_vars

case "$COMMAND" in
bm)
    gen_config "$out_dir"
    ;;
start)
    gen_config "$out_dir"
    if podman ps --all | grep "$DNSMASQ_CONTAINER_NAME" >/dev/null; then
        printf "%s already exists, removing and starting...\n" "$DNSMASQ_CONTAINER_NAME"
        podman stop "$DNSMASQ_CONTAINER_NAME" >/dev/null 2>&1
        if ! podman rm "$DNSMASQ_CONTAINER_NAME" >/dev/null; then
            printf "Could not remove \"%s\"" "$DNSMASQ_CONTAINER_NAME"
            exit 1
        fi
    fi
    if ! cid=$(podman run -d --name "$DNSMASQ_CONTAINER_NAME" --net=host \
        -v "$PROJECT_DIR/dnsmasq/bm/var/run:/var/run/dnsmasq:Z" \
        -v "$PROJECT_DIR/dnsmasq/bm/etc/dnsmasq.d:/etc/dnsmasq.d:Z" \
        --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 \
        --expose=69/udp --cap-add=NET_ADMIN "$DNSMASQ_CONTAINER_IMAGE" \
        --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q); then
        printf "Could not start %s container!\n" "$DNSMASQ_CONTAINER_NAME"
        exit 1
    fi
    run_status=$(podman inspect $DNSMASQ_CONTAINER_NAME | jq .[0].State.Running)
    if [[ "$run_status" =~ false ]]; then
        printf "Failed to start container...\n"
        podman logs "$DNSMASQ_CONTAINER_NAME"
    else
        printf "Started %s as id %s\n" "$DNSMASQ_CONTAINER_NAME" "$cid"
    fi
    ;;
stop)
    cid=$(podman stop "$DNSMASQ_CONTAINER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$DNSMASQ_CONTAINER_NAME" 2>/dev/null && podman rm "$DNSMASQ_CONTAINER_NAME" >/dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
