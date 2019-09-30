#!/bin/bash

#
# This function generates an IP address given as network CIDR and an offset
# nthhost(192.168.111.0/24,3) => 192.168.111.3
#
nthhost() {
    address="$1"
    nth="$2"

    mapfile -t ips < <(nmap -n -sL "$address" 2>&1 | awk '/Nmap scan report/{print $NF}')
    #ips=($(nmap -n -sL "$address" 2>&1 | awk '/Nmap scan report/{print $NF}'))
    ips_len="${#ips[@]}"

    if [ "$ips_len" -eq 0 ] || [ "$nth" -gt "$ips_len" ]; then
        echo "Invalid address: $address or offset $nth"
        exit 1
    fi

    echo "${ips[$nth]}"
}

get_ip_offset() {
    local addr=$1
    local offset=$2
    local prefix=$3

    ip_as_num=$(echo "$addr" | awk -F '.' '{printf "%d", ($1 * 2^24) + ($2 * 2^16) + ($3 * 2^8) + $4}')
    sh=$((32 - prefix))
    max=$(((1 << sh) - 1))
    rem=$((ip_as_num & max))

    if [ $((rem + offset)) -gt $max ]; then
        printf "Offset too large!\n"
    fi

    ip_as_num=$((ip_as_num + offset))

    ip=$(printf "%d.%d.%d.%d\n" $((ip_as_num >> 24)) $(((ip_as_num >> 16) & 255)) $(((ip_as_num >> 8) & 255)) $((ip_as_num & 255)))

    echo "$ip"
}

get_master_bm_ip() {
    id="$1"
    if [[ ! $id =~ 0|1|2 ]]; then
        printf "%s: Invalid master index %s" "${FUNCNAME[0]}" "$id"
        exit 1
    fi

    local hostname="master-$id"

    local res

    if ! res=$(get_host_var "$hostname" "sdnIPAddress"); then
        res=$(get_ip_offset "$BM_IP_RANGE_START" $(( id + BM_IP_MASTER_START_OFFSET )) 24)
    fi

    echo "$res"
}

get_worker_bm_ip() {
    id="$1"

    local hostname="worker-$id"

    local res

    if ! res=$(get_host_var "$hostname" "sdnIPAddress"); then
        res=$(get_ip_offset "$BM_IP_RANGE_START" $(( id + BM_IP_WORKER_START_OFFSET )) 24)
    fi

    echo "$res"
}

# DO NOT CHANGE BELOW THIS LINE

export PROV_IP_CIDR_DEFAULT="172.22.0.0/24"
export BM_IP_CIDR_DEFAULT="192.168.111.0/24"

export PROV_IP_CIDR="${PROV_IP_CIDR:-PROV_IP_CIDR_DEFAULT}"
export BM_IP_CIDR="${BM_IP_CIDR:-BM_IP_CIDR_DEFAULT}"

PROV_ETC_DIR="prov/etc/dnsmasq.d"
export PROV_ETC_DIR
PROV_VAR_DIR="prov/var/run/dnsmasq"
export PROV_VAR_DIR

BM_ETC_DIR="bm/etc/dnsmasq.d"
export BM_ETC_DIR
BM_VAR_DIR="bm/var/run/dnsmasq"
export BM_VAR_DIR

PROV_IP_MATCHBOX_IP=${PROV_INTF_IP}
export PROV_IP_MATCHBOX_IP

PROV_IP_MATCHBOX_HTTP_URL="http://$PROV_IP_MATCHBOX_IP:8080"
export PROV_IP_MATCHBOX_HTTP_URL

PROV_IP_MATCHBOX_RPC="$PROV_IP_MATCHBOX_IP:8081"
export PROV_IP_MATCHBOX_RPC

PROV_IP_RANGE_START=${PROV_IP_DHCP_START}
export PROV_IP_RANGE_START

PROV_IP_RANGE_END=${PROV_IP_DHCP_END}
export PROV_IP_RANGE_END

BM_IP_RANGE_START=${BM_IP_DHCP_START}
export BM_IP_RANGE_START
BM_IP_RANGE_END=${BM_IP_DHCP_END}
export BM_IP_RANGE_END

BM_IP_BOOTSTRAP=${BM_IP_RANGE_START}
export BM_IP_BOOTSTRAP

BM_IP_MASTER_START_OFFSET=1
export BM_IP_MASTER_START_OFFSET

BM_IP_WORKER_START_OFFSET=5
export BM_IP_WORKER_START_OFFSET

BM_IP_NS=${CLUSTER_DNS}
export BM_IP_NS
