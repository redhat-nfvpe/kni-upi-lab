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

get_master_bm_ip() {
    id="$1"

    if [[ ! $id =~ 0|1|2 ]]; then
        printf "%s: Invalid master index %s" "${FUNCNAME[0]}" "$id"
        exit 1
    fi
    id=$((id + BM_IP_MASTER_START_OFFSET))
    res="$(nthhost "$BM_IP_CIDR" "$id")"

    echo "$res"
}

get_worker_bm_ip() {
    id="$1"

    id=$((id + BM_IP_WORKER_START_OFFSET))
    res="$(nthhost "$BM_IP_CIDR" "$id")"

    echo "$res"
}

# DO NOT CHANGE BELOW THIS LINE

export PROV_IP_CIDR_DEFAULT="172.22.0.0/24"
export BM_IP_CIDR_DEFAULT="192.168.111.0/24"

PROV_ETC_DIR="prov/etc/dnsmasq.d"
export PROV_ETC_DIR
PROV_VAR_DIR="prov/var/run/dnsmasq"
export PROV_VAR_DIR

BM_ETC_DIR="bm/etc/dnsmasq.d"
export BM_ETC_DIR
BM_VAR_DIR="bm/var/run/dnsmasq"
export BM_VAR_DIR

PROV_IP_MATCHBOX_IP=$(nthhost "${PROV_IP_CIDR:-PROV_IP_CIDR_DEFAULT}" 10) # 172.22.0.10
export PROV_IP_MATCHBOX_IP
PROV_IP_MATCHBOX_HTTP_URL="http://$PROV_IP_MATCHBOX_IP:8080" # 172.22.0.10
export PROV_IP_MATCHBOX_HTTP_URL
PROV_IP_MATCHBOX_RPC="$PROV_IP_MATCHBOX_IP:8081" # 172.22.0.10
export PROV_IP_MATCHBOX_RPC
PROV_IP_RANGE_START=$(nthhost "${PROV_IP_CIDR:-PROV_IP_CIDR_DEFAULT}" 11) # 172.22.0.11
export PROV_IP_RANGE_START
PROV_IP_RANGE_END=$(nthhost "${PROV_IP_CIDR:-PROV_IP_CIDR_DEFAULT}" 30) # 172.22.0.30
export PROV_IP_RANGE_END

export BM_IP_CIDR
BM_IP_RANGE_START=$(nthhost "${BM_IP_CIDR:-BM_IP_CIDR_DEFAULT}" 10) # 192.168.111.10
export BM_IP_RANGE_START
BM_IP_RANGE_END=$(nthhost "${BM_IP_CIDR:-BM_IP_CIDR_DEFAULT}" 60) # 192.168.111.60
export BM_IP_RANGE_END
BM_IP_BOOTSTRAP=$(nthhost "${BM_IP_CIDR:-BM_IP_CIDR_DEFAULT}" 10) # 192.168.111.10
export BM_IP_BOOTSTRAP

BM_IP_NS=$(nthhost "${BM_IP_CIDR:-BM_IP_CIDR_DEFAULT}" 1) # 192.168.111.1
export BM_IP_NS

BM_IP_MASTER_START_OFFSET=11
export BM_IP_MASTER_START_OFFSET

BM_IP_WORKER_START_OFFSET=20
export BM_IP_WORKER_START_OFFSET
