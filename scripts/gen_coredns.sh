#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

CONTAINER_NAME="kni-coredns"

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
            restart  - Restart coredns to reload config files

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/coredns/...]
EOM
    exit 0
}

gen_zone_info() {

    local cidr="$1"

    # cidr 192.168.111.0/24
    # cidr 192.168.64/0/18
    if ! rdns=$(ipcalc --network --broadcast --prefix "$cidr"); then
        printf "Error calculating network info for %s" "$cidr" 
    fi

    if [[ ! $rdns =~ NETWORK=([0-9.]*) ]]; then
        printf "Error calculating network info for %s" "$cidr" 
        exit 1
    fi
    network="${BASH_REMATCH[1]}"

    if [[ ! $rdns =~ BROADCAST=([0-9.]*) ]]; then
        printf "Error calculating network info for %s" "$cidr" 
        exit 1
    fi
    broadcast="${BASH_REMATCH[1]}"

    if [[ ! $rdns =~ PREFIX=([0-9.]*) ]]; then
        printf "Error calculating network info for %s" "$cidr" 
        exit 1
    fi
    prefix="${BASH_REMATCH[1]}"

    IFS='.' read -r -a split <<<"$network"

    if [ "$prefix" -eq 32 ]; then
        rdns="${split[3]}.${split[2]}.${split[1]}.${split[0]}"
        zone_name="${split[0]}.${split[1]}.${split[2]}.${split[3]}"
    elif [ "$prefix" -eq 24 ]; then
        rdns="${split[2]}.${split[1]}.${split[0]}"
        zone_name="${split[0]}.${split[1]}.${split[2]}"
    elif [ "$prefix" -eq 16 ]; then
        rdns="${split[1]}.${split[0]}"
        zone_name="${split[0]}.${split[1]}"
    elif [ "$prefix" -eq 8 ]; then
        rdns="${split[0]}"
        zone_name="${split[0]}"
    elif [ "$prefix" -gt 24 ]; then
        rdns="$network-$broadcast.${split[2]}.${split[1]}.${split[0]}"
        zone_name="${split[0]}.${split[1]}.${split[2]}"
    elif [ "$prefix" -gt 16 ]; then
        rdns="$network-$broadcast.${split[1]}.${split[0]}"
        zone_name="${split[0]}.${split[1]}"
    elif [ "$prefix" -gt 8 ]; then
        rdns="$network-$broadcast.${split[0]}"
        zone_name="${split[0]}"
    else
        printf "Invalid prefix/network!\n"
        exit 1
    fi
    rdns="$rdns.in-addr.arpa"

    echo "$zone_name    $rdns"
}

gen_config_corefile() {
    local out_dir="$1"
    local cfg_file="$out_dir/Corefile"
    local cluster_id="${CLUSTER_FINAL_VALS[cluster_id]}"
    local cluster_domain="${CLUSTER_FINAL_VALS[cluster_domain]}"

    mkdir -p "$out_dir"

    local cidr

    cat <<EOF >"$cfg_file"
.:53 {
    log
    errors
    file /etc/coredns/db.$(gen_zone_info "${SITE_CONFIG[provisioningInfrastructure.network.baremetalIpCidr]}")
    forward . $EXT_DNS1 $EXT_DNS2 $EXT_DNS3
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
    local cluster_id="${CLUSTER_FINAL_VALS[cluster_id]}"
    local cluster_domain="${CLUSTER_FINAL_VALS[cluster_domain]}"
    local cfg_file="$out_dir/db.$cluster_domain"

    mkdir -p "$out_dir"

    cat <<EOF >"$cfg_file"
\$ORIGIN $cluster_id.$cluster_domain.
\$TTL 10800      ; 3 hours
@       3600 IN SOA bastion.$cluster_id.$cluster_domain. root.$cluster_id.$cluster_domain. (
                                2019010101 ; serial
                                7200       ; refresh (2 hours)
                                3600       ; retry (1 hour)
                                1209600    ; expire (2 weeks)
                                3600       ; minimum (1 hour)
                                )
EOF

    master1_mac=$(get_host_var "master-1" "sdnMacAddress")
    master2_mac=$(get_host_var "master-2" "sdnMacAddress")

    # shellcheck disable=SC2129
    {
        printf "%-40s 8640 IN    SRV 0 10 2380 etcd-%s\n" "_etcd-server-ssl._tcp.$cluster_id.$cluster_domain." "0.$cluster_id.$cluster_domain."

        if [ "${HOSTS_FINAL_VALS[master_count]}" = 3 ] &&
            [ -n "$master1_mac" ] &&
            [ -n "$master2_mac" ]; then
            printf "%-40s            SRV 0 10 2380 etcd-1.%s.%s.\n" " " "$cluster_id" "$cluster_domain"
            printf "%-40s            SRV 0 10 2380 etcd-2.%s.%s.\n" " " "$cluster_id" "$cluster_domain"
        fi
        printf "\n"
        printf "%-40s A %s\n" "api" "$BM_INTF_IP"
        printf "%-40s A %s\n" "api-int" "$BM_INTF_IP"
        printf "%-40s A %s\n" "$cluster_id-master-0" "$(get_master_bm_ip 0)"

        if [ "${HOSTS_FINAL_VALS[master_count]}" = 3 ] &&
            [ -n "$master1_mac" ] &&
            [ -n "$master2_mac" ]; then
            printf "%-40s A %s\n" "$cluster_id-master-1" "$(get_master_bm_ip 1)"
            printf "%-40s A %s\n" "$cluster_id-master-2" "$(get_master_bm_ip 2)"
        fi

        num_workers="${HOSTS_FINAL_VALS[worker_count]}"
        if [ "$num_workers" -gt 0 ]; then
            IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
            for worker in "${workers[@]}"; do
                index=${worker##*-}
                printf "%-40s A %s\n" "$cluster_id-$worker" "$(get_worker_bm_ip "$index")"
            done
        fi
        printf "%-40s A %s\n" "$cluster_id-bootstrap" "$BM_IP_BOOTSTRAP"

        printf "%-40s IN CNAME %s\n" "etcd-0" "$cluster_id-master-0"

        if [ "${HOSTS_FINAL_VALS[master_count]}" = 3 ]; then
            printf "%-40s IN CNAME %s\n" "etcd-1" "$cluster_id-master-1"
            printf "%-40s IN CNAME %s\n" "etcd-2" "$cluster_id-master-2"
            printf "\n"
        fi
        printf "\$ORIGIN apps.%s\n" "$cluster_id.$cluster_domain."
        printf "%-40s A %s\n" "*" "$BM_INTF_IP"

    } >>"$cfg_file"

    echo "$cfg_file"
}

gen_config_db_reverse() {
    local out_dir="$1"

    local cluster_id="${CLUSTER_FINAL_VALS[cluster_id]}"
    local cluster_domain="${CLUSTER_FINAL_VALS[cluster_domain]}"

    mkdir -p "$out_dir"

    zone_info=$(gen_zone_info "${SITE_CONFIG[provisioningInfrastructure.network.baremetalIpCidr]}")
    local cfg_file="$out_dir/db.${zone_info%% *}"

    #    dns_ip=${SITE_CONFIG[provisioningInfrastructure.network.dns.cluster]}

    cat <<EOF >"$cfg_file"
\$TTL 10800      ; 3 hours

@       3600 IN SOA bastion.$cluster_id.$cluster_domain. root.$cluster_id.$cluster_domain. (
                                2019010101 ; serial
                                7200       ; refresh (2 hours)
                                3600       ; retry (1 hour)
                                1209600    ; expire (2 weeks)
                                3600       ; minimum (1 hour)
                                )

EOF

    master1_mac=$(get_host_var "master-1" "sdnMacAddress")
    master2_mac=$(get_host_var "master-2" "sdnMacAddress")

    {
        printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$BM_IP_NS")" "bastion.$cluster_id.$cluster_domain."

        printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$BM_IP_BOOTSTRAP")" "$cluster_id-bootstrap.$cluster_id.$cluster_domain."

        printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$(get_master_bm_ip 0)")" "$cluster_id-master-0.$cluster_id.$cluster_domain."

        if [ "${HOSTS_FINAL_VALS[master_count]}" = 3 ] &&
            [ -n "$master1_mac" ] &&
            [ -n "$master2_mac" ]; then
            printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$(get_master_bm_ip 1)")" "$cluster_id-master-1.$cluster_id.$cluster_domain."
            printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$(get_master_bm_ip 2)")" "$cluster_id-master-2.$cluster_id.$cluster_domain."
        fi

        num_workers="${HOSTS_FINAL_VALS[worker_count]}"
        if [ "$num_workers" -gt 0 ]; then
            IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
            for worker in "${workers[@]}"; do
                index=${worker##*-}
                printf "%-7s             IN PTR %s\n" "$(get_bm_ip_offset "$(get_worker_bm_ip "$index")")" "$cluster_id-worker-$worker.$cluster_domain"
            done
        fi
    } >>"$cfg_file"

    echo "$cfg_file"
}

gen_config() {
    local out_dir="$1"

    ofile=$(gen_config_corefile "$out_dir")
    printf "Generated \"%s\"...\n" "$ofile"

    ofile=$(gen_config_db "$out_dir")
    printf "Generated \"%s\"...\n" "$ofile"

    ofile=$(gen_config_db_reverse "$out_dir")
    printf "Generated \"%s\"...\n" "$ofile"

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

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$COREDNS_DIR}
out_dir=$(realpath "$out_dir")

case "$COMMAND" in
all)
    gen_variables "$manifest_dir"
    gen_config "$out_dir"
    ;;
corefile)
    gen_variables "$manifest_dir"
    ofile=$(gen_config_corefile "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
db)
    gen_variables "$manifest_dir"
    ofile=$(gen_config_db "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
start)
    if [[ $PROVIDE_DNS =~ true ]]; then
        podman_exists "$CONTAINER_NAME" &&
            (podman_rm "$CONTAINER_NAME" ||
                printf "Could not remove %s!\n" "$CONTAINER_NAME")

        if ! cid=$(sudo podman run -d --expose=53/udp --name "$CONTAINER_NAME" \
            -p "$CLUSTER_DNS:53:53" -p "$CLUSTER_DNS:53:53/udp" \
            -v "$PROJECT_DIR/coredns:/etc/coredns:z" coredns/coredns:latest \
            -conf /etc/coredns/Corefile); then
            printf "Could not start coredns container!\n"
            exit 1
        fi
        podman_isrunning_logs "$CONTAINER_NAME" && printf "Started %s as %s...\n" "$CONTAINER_NAME" "$cid"
    fi
    ;;
restart)
    podman_restart "$CONTAINER_NAME" && printf "Restarted %s\n" "$CONTAINER_NAME" || exit 1 
    ;;
stop)
    podman_stop "$CONTAINER_NAME" && printf "Stopped %s\n" "$CONTAINER_NAME" || exit 1
    ;;
remove)
    status=$(podman_rm "$CONTAINER_NAME") && printf "%s %s\n" "$CONTAINER_NAME" "$status" || exit 1
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
