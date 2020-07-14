#!/bin/bash

###------------------------------------------------###
### Need interface input from user via environment ###
###------------------------------------------------###

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/parse_site_config.sh"

parse_site_config "$PROJECT_DIR/cluster/site-config.yaml" "./cluster" || exit 1
map_site_config "true" || exit 1

# allow DNS/DHCP traffic to dnsmasq and coredns
sudo systemctl start firewalld
sudo firewall-cmd --add-interface="$BM_BRIDGE" --zone=public --permanent
sudo firewall-cmd --add-interface="$PROV_BRIDGE" --zone=public --permanent
sudo firewall-cmd --zone=public --permanent --add-service=ssh
sudo firewall-cmd --add-service=http --zone=public --permanent
sudo firewall-cmd --add-service=https --zone=public --permanent
sudo firewall-cmd --zone=public --permanent --add-port=67/udp
sudo firewall-cmd --zone=public --permanent --add-port=53/udp
sudo firewall-cmd --zone=public --permanent --add-port=67/tcp
sudo firewall-cmd --zone=public --permanent --add-port=53/tcp
sudo firewall-cmd --zone=public --permanent --add-port=6443/tcp
sudo firewall-cmd --zone=public --permanent --add-port=67/udp
sudo firewall-cmd --zone=public --permanent --add-port=69/udp
sudo firewall-cmd --zone=public --permanent --add-port=8080/tcp
sudo firewall-cmd --zone=public --permanent --add-port=22623/tcp

#Networking requirements for user-provisioned infrastructure
sudo firewall-cmd --zone-public --permanent --add-port=9000-9999/tcp
sudo firewall-cmd --zone-public --permanent --add-port=10250-10259/tcp
sudo firewall-cmd --zone-public --permanent --add-port=10256/tcp
sudo firewall-cmd --zone-public --permanent --add-port=9000-9999/udp
sudo firewall-cmd --zone-public --permanent --add-port=6081/udp
sudo firewall-cmd --zone-public --permanent --add-port=4689/udp
sudo firewall-cmd --zone-public --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --zone-public --permanent --add-port=30000-32767/udp

sudo firewall-cmd --zone=public --add-masquerade --permanent
sudo firewall-cmd --direct --permanent --add-rule ipv4 nat POSTROUTING 0 -o "$EXT_INTF" -j MASQUERADE
sudo firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 -i "$PROV_BRIDGE" -o "$EXT_INTF" -j ACCEPT 
sudo firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 -i "$EXT_INF" -o "$PROV_BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 -i "$BM_BRIDGE" -o "$EXT_INTF" -j ACCEPT 
sudo firewall-cmd --direct --permanent --add-rule ipv4 filter FORWARD 0 -i "$EXT_INTF" -o "$BM_BRIDGE" -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo systemctl stop firewalld
sudo systemctl start firewalld

# remove certain problematic REJECT rules

FILTER_INPUT_REJECT="$(sudo nft -a list chain inet firewalld filter_INPUT | grep "reject with icmpx type admin-prohibited" | cut -d '#' -f 2 | cut -d ' ' -f 3)"
FILTER_FORWARD_REJECT="$(sudo nft -a list chain inet firewalld filter_FORWARD | grep "reject with icmpx type admin-prohibited" | cut -d '#' -f 2 | cut -d ' ' -f 3)"

if [[ -n "$FILTER_INPUT_REJECT" ]]; then
    sudo nft delete rule inet firewalld filter_INPUT handle "$FILTER_INPUT_REJECT" > /dev/null
fi

if [[ -n "$FILTER_FORWARD_REJECT" ]]; then
    sudo nft delete rule inet firewalld filter_FORWARD handle "$FILTER_FORWARD_REJECT" > /dev/null
fi

# enable ipv4 forwarding
IP_FORWARD=$(sudo grep "net.ipv4.ip_forward = 1" /etc/sysctl.conf | grep -v "#")

if [[ -z "$IP_FORWARD" ]]; then
sudo tee -a /etc/sysctl.conf > /dev/null << EOF
net.ipv4.ip_forward = 1
EOF
fi
