#!/bin/bash

#set -e

###------------------###
### RHEL preparation ###
###------------------###

printf "\nChecking OS...\n\n"

EPEL_PACKAGE="epel-release"
PIP_PACKAGE="python-pip"
OS_NAME="$(head -3 /etc/os-release | grep ID | cut -d '"' -f 2)"
OS_VERSION="$(grep "VERSION_ID" /etc/os-release | cut -d '"' -f 2 | cut -d '.' -f 1)"

if [[ "$OS_NAME" == "rhel" ]]; then
    if [[ "$(subscription-manager status | grep "Overall Status" | cut -d ":" -f 2 | awk '{$1=$1};1')" != "Current" ]]; then
        echo "RHEL OS requires an active subscription to continue!"
        exit 1
    fi

    if [[ "$OS_VERSION" == "7" || "$OS_VERSION" == "8" ]]; then
        PIP_PACKAGE="python2-pip"
    else
        echo "RHEL version $OS_VERSION is not supported!"
        exit 1
    fi

    curl -o /tmp/epel-release.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_VERSION.noarch.rpm
    EPEL_PACKAGE="/tmp/epel-release.rpm"

    # Enable other needed RPMs
    subscription-manager repos --enable "rhel-*-optional-rpms" --enable "rhel-*-extras-rpms"  --enable "rhel-ha-for-rhel-*-server-rpms"
fi

###--------------###
### Install Epel ###
###--------------###

printf "\nInstalling epel-release via yum...\n\n"

sudo yum install -y $EPEL_PACKAGE

###------------------------------###
### Install dependencies via yum ###
###------------------------------###

printf "\nInstalling dependencies via yum...\n\n"

sudo yum install -y git podman unzip ipmitool dnsmasq bridge-utils jq nmap libvirt $PIP_PACKAGE

###--------------------###
### Install Yq via pip ###
###--------------------###

sudo pip install yq

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
source "scripts/paths.sh"
# shellcheck disable=SC1091
source "scripts/network_conf.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

###-------------------------------------------###
### Install virt repo and get latest libvirtd ###
###-------------------------------------------###

printf "\nInstalling latest libvirtd via yum...\n\n"

if [[ "$OS_NAME" == "centos" ]]; then
cat <<EOF >/etc/yum.repos.d/virt.repo
[virt]
name=virt
baseurl=http://mirror.centos.org/centos/7/virt/x86_64/libvirt-latest/
enabled=1
gpgcheck=0
EOF
fi

sudo yum install -y qemu-kvm
sudo yum update -y qemu-kvm

###---------------------------###
### Enable and start libvirtd ###
###---------------------------###

printf "\nEnabling and starting libvirtd...\n\n"

sudo systemctl enable libvirtd
sudo systemctl start libvirtd

###---------------------------------------------###
### Configure provisioning interface and bridge ###
###---------------------------------------------###

printf "\nConfiguring provisioning interface (%s) and bridge (%s)...\n\n" "$PROV_INTF" "$PROV_BRIDGE"

cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE"
TYPE=Bridge
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$PROV_BRIDGE
DEVICE=$PROV_BRIDGE
ONBOOT=yes
IPADDR=$PROV_INTF_IP
NETMASK=255.255.255.0
ZONE=public
EOF

cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$PROV_INTF"
TYPE=Ethernet
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$PROV_INTF
DEVICE=$PROV_INTF
ONBOOT=yes
BRIDGE=$PROV_BRIDGE
EOF

ifdown "$PROV_BRIDGE"
ifup "$PROV_BRIDGE"

ifdown "$PROV_INTF"
ifup "$PROV_INTF"

###-------------------------------###
### Configure baremetal interface ###
###-------------------------------###

printf "\nConfiguring baremetal interface (%s) and bridge (%s)...\n\n" "$BM_INTF" "$BM_BRIDGE"

cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE"
TYPE=Bridge
NM_CONTROLLED=no
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=no
IPV4_FAILURE_FATAL=no
IPV6INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
NAME=$BM_BRIDGE
DEVICE=$BM_BRIDGE
IPADDR=$BM_INTF_IP
NETMASK=255.255.255.0
ONBOOT=yes
EOF

cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$BM_INTF"
TYPE=Ethernet
NM_CONTROLLED=no
PROXY_METHOD=none
BROWSER_ONLY=no
BOOTPROTO=static
DEFROUTE=yes
IPV4_FAILURE_FATAL=no
NAME=$BM_INTF
DEVICE=$BM_INTF
ONBOOT=yes
BRIDGE=$BM_BRIDGE
EOF

if [[ $PROVIDE_DNS =~ true ]]; then
    cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE:1"
DEVICE=$BM_BRIDGE:1
Type=Ethernet
ONBOOT=yes
NM_CONTROLLED=no
BOOTPROTO=none
IPADDR=$CLUSTER_DNS
PREFIX=24
EOF
fi

if [[ $PROVIDE_GW =~ true ]]; then
    cat <<EOF >"/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE:2"
DEVICE=$BM_BRIDGE:2
Type=Ethernet
ONBOOT=yes
NM_CONTROLLED=no
BOOTPROTO=none
IPADDR=$CLUSTER_DEFAULT_GW
PREFIX=24
EOF
fi

ifdown "$BM_BRIDGE"
ifup "$BM_BRIDGE"

ifdown "$BM_INTF"
ifup "$BM_INTF"

###--------------------------------------------------###
### Configure iptables to allow for external traffic ###
###--------------------------------------------------###

printf "\nConfiguring iptables to allow for external traffic...\n\n"

(
    ./scripts/gen_iptables.sh
) || exit 1

###----------------###
### Install Golang ###
###----------------###

printf "\nInstalling Golang...\n\n"

export GOROOT=/usr/local/go
export GOPATH=$HOME/go/src
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH

if [[ ! -d "/usr/local/go" ]]; then
    (
        cd /tmp

        curl -O https://dl.google.com/go/go1.12.6.linux-amd64.tar.gz
        tar -xzf go1.12.6.linux-amd64.tar.gz
        sudo mv go /usr/local

        GOINSTALLED=$(grep GOROOT ~/.bash_profile)

        if [[ -z "$GOINSTALLED" ]]; then
            {
                echo "export GOROOT=/usr/local/go"
                echo "export GOPATH=$HOME/go/src"
                echo "export PATH=$GOPATH/bin:$GOROOT/bin:$PATH"
            } >>~/.bash_profile
        fi
    ) || exit 1
fi

###-----------------------------------###
### Set up NetworkManager DNS overlay ###
###-----------------------------------###

printf "\nSetting up NetworkManager DNS overlay...\n\n"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

gen_variables "$manifest_dir"

DNSCONF=/etc/NetworkManager/conf.d/openshift.conf
DNSCHANGED=""
if ! [ -f "${DNSCONF}" ]; then
    echo -e "[main]\ndns=dnsmasq" | sudo tee "${DNSCONF}"
    DNSCHANGED=1
fi
DNSMASQCONF=/etc/NetworkManager/dnsmasq.d/openshift.conf
if ! [ -f "${DNSMASQCONF}" ]; then
    echo server=/"${CLUSTER_FINAL_VALS[cluster_domain]}"/"$CLUSTER_DNS" | sudo tee "${DNSMASQCONF}"
    DNSCHANGED=1
fi
if [ -n "$DNSCHANGED" ]; then
    sudo systemctl restart NetworkManager
fi

###-----------------###
### Set up tftpboot ###
###-----------------###

# TODO: This might be unnecessary, as the dnsmasq container images we
#       are using are rumored to self-contain this
printf "\nSetting up tftpboot...\n\n"

if [[ ! -d "/var/lib/tftpboot" ]]; then
    sudo mkdir -p /var/lib/tftpboot
    sudo restorecon /var/lib/tftpboot
    (
        cd /var/lib/tftpboot
        sudo curl -O http://boot.ipxe.org/ipxe.efi
        sudo curl -O http://boot.ipxe.org/undionly.kpxe
    ) || echo "Failed!"
fi

###----------------------------###
### Prepare OpenShift binaries ###
###----------------------------###

printf "\nInstalling OpenShift binaries...\n\n"

(
    cd /tmp

    if [[ ! -f "/usr/local/bin/openshift-install" ]]; then
        if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" != "latest" ]]; then
            curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_OCP_MINOR_REL/openshift-install-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
            tar xvf "openshift-install-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
        else
            LATEST_OCP_INSTALLER=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/ | grep install-linux | cut -d '"' -f 8)
            curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/$LATEST_OCP_INSTALLER"
            tar xvf "$LATEST_OCP_INSTALLER"
        fi
        sudo mv openshift-install /usr/local/bin/
    fi

    if [[ ! -f "/usr/local/bin/oc" ]]; then
        if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" != "latest" ]]; then
            curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_OCP_MINOR_REL/openshift-client-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
            tar xvf "openshift-client-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
        else
            LATEST_OCP_CLIENT=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/ | grep client-linux | cut -d '"' -f 8)
            curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/$LATEST_OCP_CLIENT"
            tar xvf "$LATEST_OCP_CLIENT"
        fi
        sudo mv oc /usr/local/bin/
    fi

    ###-------------------###
    ### Prepare terraform ###
    ###-------------------###

    printf "\nInstalling Terraform and generating config...\n\n"

    if [[ ! -f "/usr/bin/terraform" ]]; then
        curl -O "https://releases.hashicorp.com/terraform/0.12.2/terraform_0.12.2_linux_amd64.zip"
        unzip terraform_0.12.2_linux_amd64.zip
        sudo mv terraform /usr/bin/.
    fi

    if [[ ! -f "$HOME/.terraform.d/plugins/terraform-provider-matchbox)" ]]; then
        if [[ -d "/tmp/terraform-provider-matchbox" ]]; then
            rm -rf /tmp/terraform-provider-matchbox
        fi

        git clone https://github.com/poseidon/terraform-provider-matchbox.git
        cd terraform-provider-matchbox
        go build -mod=vendor
        mkdir -p ~/.terraform.d/plugins
        cp terraform-provider-matchbox ~/.terraform.d/plugins/.
    fi
) || exit 1

printf "\nDONE\n"
