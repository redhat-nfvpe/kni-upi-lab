#!/bin/bash

###------------------------------------------------###
### Need interface input from user via environment ###
###------------------------------------------------###
# shellcheck disable=SC1091
source scripts/parse_site_config.sh

parse_site_config "./cluster/site-config.yaml" "./cluster" || exit 1
map_site_config "true" || exit 1

###------------------------------###
### Source helper scripts first! ###
###------------------------------###

# shellcheck disable=SC1091
source "common.sh"
# shellcheck disable=SC1091
source "images_and_binaries.sh"
# shellcheck disable=SC1091
source "scripts/paths.sh"
# shellcheck disable=SC1091
source "scripts/network_conf.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

###--------------------------------------------------------------------###
### Bring down interfaces and bridges, and delete their network config ###
###--------------------------------------------------------------------###

printf "\nRemoving interface and bridges, and deleting network config...\n\n"

sudo ifdown "$PROV_INTF"
sudo ifdown "$PROV_BRIDGE"
sudo ifdown "$BM_INTF"
sudo ifdown "$BM_BRIDGE"

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$PROV_INTF" ]]; then
    sudo rm "/etc/sysconfig/network-scripts/ifcfg-$PROV_INTF"
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE" ]]; then
    sudo rm "/etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE"
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$BM_INTF" ]]; then
    sudo rm "/etc/sysconfig/network-scripts/ifcfg-$BM_INTF"
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE" ]]; then
    sudo rm "/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE"
fi

###------------------------------------###
### Remove HAProxy container and image ###
###------------------------------------###

printf "\nRemoving HAProxy container and image...\n\n"

./scripts/gen_haproxy.sh remove

###---------------------------------------###
### Remove provisioning dnsmasq container ###
###---------------------------------------###

printf "\nRemoving provisioning dnsmasq container...\n\n"

./scripts/gen_config_prov.sh remove

###------------------------------------###
### Remove baremetal dnsmasq container ###
###------------------------------------###

printf "\nRemoving baremetal dnsmasq container...\n\n"

./scripts/gen_config_bm.sh remove

###--------------------------------------###
### Remove matchbox container and assets ###
###--------------------------------------###

printf "\nRemoving matchbox container and assets...\n\n"

./scripts/gen_matchbox.sh remove

if [[ -d "$MATCHBOX_VAR_LIB/assets" && "$1" == "all" ]]; then
    sudo rm -rf "$MATCHBOX_VAR_LIB/assets"
fi

###--------------------------###
### Remove coredns container ###
###--------------------------###

printf "\nRemoving coredns container...\n\n"

./scripts/gen_coredns.sh remove

###-----------------------------------###
### Remove NetworkManager DNS overlay ###
###-----------------------------------###

printf "\nRemoving NetworkManager DNS overlay...\n\n"

if [[ -f "/etc/NetworkManager/conf.d/openshift.conf" ]]; then
    sudo rm /etc/NetworkManager/conf.d/openshift.conf
fi

if [[ -f "/etc/NetworkManager/dnsmasq.d/openshift.conf" ]]; then
    sudo rm /etc/NetworkManager/dnsmasq.d/openshift.conf
fi

sudo systemctl restart NetworkManager

###-----------------###
### Remove tftpboot ###
###-----------------###

printf "\nRemoving tftpboot...\n\n"

if [[ -d "/var/lib/tftpboot" ]]; then
    sudo rm -rf /var/lib/tftpboot
fi

###---------------###
### Remove golang ###
###---------------###

printf "\nRemoving golang...\n\n"

if [[ ! -d "/usr/local/go" ]]; then
    sudo rm -rf /usr/local/go
    sed -i '/GOPATH/d' ~/.bash_profile
    sed -i '/GOROOT/d' ~/.bash_profile
fi

###---------------------------###
### Remove OpenShift binaries ###
###---------------------------###

printf "\nRemoving OpenShift binaries...\n\n"

if [[ -f "/usr/local/bin/openshift-install" ]]; then
    sudo rm -f /usr/local/bin/openshift-install
fi

if [[ -f "/usr/local/bin/oc" ]]; then
    sudo rm -f /usr/local/bin/oc
fi

###------------------###
### Remove terraform ###
###------------------###

printf "\nRemoving Terraform...\n\n"

if [[ -f "/usr/bin/terraform" && "$1" == "all" ]]; then
    sudo rm -f /usr/bin/terraform
fi

if [[ -f ~/.terraform.d ]]; then
    sudo rm -rf ~/.terraform.d
    
    if [[ -d "/tmp/terraform-provider-matchbox" ]]; then
        rm -rf /tmp/terraform-provider-matchbox
    fi
fi

###------------------------------------------------------------------------------###
### Remove Git, Podman, Unzip, Ipmitool, Dnsmasq, Bridge-Utils, Epel, Pip and Jq ###
###------------------------------------------------------------------------------###

printf "\nRemoving dependencies via yum...\n\n"

OS_NAME="$(head -3 /etc/os-release | grep ID | cut -d '"' -f 2)"
OS_VERSION="$(grep "VERSION_ID" /etc/os-release | cut -d '"' -f 2 | cut -d '.' -f 1)"

PIP_PACKAGE="python-pip"
if [[ "$OS_NAME" == "rhel" ]]; then
    if [[ "$OS_VERSION" == "7" || "$OS_VERSION" == "8" ]]; then
        PIP_PACKAGE="python2-pip"
    else
        echo "RHEL version $OS_VERSION is not supported!"
        exit 1
    fi
else
    if [[ "$OS_VERSION" == "8" ]]; then
      PIP_PACKAGE="python2-pip"
    fi
fi


if [[ "$1" == "all" ]]; then
    sudo yum remove -y podman unzip ipmitool dnsmasq bridge-utils epel-release ${PIP_PACKAGE} jq
fi

printf "\nDONE\n"
