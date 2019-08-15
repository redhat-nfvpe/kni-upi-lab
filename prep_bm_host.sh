#!/bin/bash

#set -e

###------------------------------------------------###
### Need interface input from user via environment ###
###------------------------------------------------###

# shellcheck disable=SC1091
source cluster/prep_bm_host.src

printf "\nChecking parameters...\n\n"

for i in PROV_INTF PROV_BRIDGE BM_INTF BM_BRIDGE EXT_INTF PROV_IP_CIDR BM_IP_CIDR; do
    if [[ -z "${!i}" ]]; then
        echo "You must set PROV_INTF, PROV_BRIDGE, BM_INTF, BM_BRIDGE, EXT_INTF, PROV_IP_CIDR and BM_IP_CIDR as environment variables!"
        echo "Edit prep_bm_host.src to set these values."
        exit 1
    else
        echo $i": "${!i}
    fi
done

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

###-------------------------------###
### Call gen_*.sh scripts second! ###
###-------------------------------###

# ?

###-------------------------------------------###
### Install virt repo and get latest libvirtd ###
###-------------------------------------------###

printf "\nInstalling latest libvirtd via yum...\n\n"

cat <<EOF >/etc/yum.repos.d/virt.repo
[virt]
name=virt
baseurl=http://mirror.centos.org/centos/7/virt/x86_64/libvirt-latest/
enabled=1
gpgcheck=0
EOF

sudo yum install -y qemu-kvm
sudo yum update -y qemu-kvm

###--------------###
### Install Epel ###
###--------------###

printf "\nInstalling epel-release via yum...\n\n"

sudo yum install -y epel-release

###------------------------------###
### Install dependencies via yum ###
###------------------------------###

printf "\nInstalling dependencies via yum...\n\n"

sudo yum install -y git podman unzip ipmitool dnsmasq bridge-utils python-pip jq nmap

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
IPADDR=$(nthhost "$PROV_IP_CIDR" 10)
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
IPADDR=$(nthhost "$BM_IP_CIDR" 1)
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

ifdown "$BM_BRIDGE"
ifup "$BM_BRIDGE"

ifdown "$BM_INTF"
ifup "$BM_INTF"

###--------------------------------------------------###
### Configure iptables to allow for external traffic ###
###--------------------------------------------------###

printf "\nConfiguring iptables to allow for external traffic...\n\n"

cat <<EOF >scripts/iptables.sh
#!/bin/bash

ins_del_rule()
{
    operation=\$1
    table=\$2
    rule=\$3
   
    if [ "\$operation" == "INSERT" ]; then
        if ! sudo iptables -t "\$table" -C \$rule > /dev/null 2>&1; then
            sudo iptables -t "\$table" -I \$rule
        fi
    elif [ "\$operation" == "DELETE" ]; then
        sudo iptables -t "\$table" -D \$rule
    else
        echo "\${FUNCNAME[0]}: Invalid operation: \$operation"
        exit 1
    fi
}

    #allow DNS/DHCP traffic to dnsmasq and coredns
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p udp -m udp --dport 67 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p udp -m udp --dport 53 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p tcp -m tcp --dport 67 -j ACCEPT"
    ins_del_rule "INSERT" "filter" "INPUT -i $BM_BRIDGE -p tcp -m tcp --dport 53 -j ACCEPT"
   
    #enable routing from provisioning and cluster network to external
    ins_del_rule "INSERT" "nat" "POSTROUTING -o $EXT_INTF -j MASQUERADE"
    ins_del_rule "INSERT" "filter" "FORWARD -i $PROV_BRIDGE -o $EXT_INTF -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -o $PROV_BRIDGE -i $EXT_INTF -m state --state RELATED,ESTABLISHED -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -i $BM_BRIDGE -o $EXT_INTF -j ACCEPT"
    ins_del_rule "INSERT" "filter" "FORWARD -o $BM_BRIDGE -i $EXT_INTF -m state --state RELATED,ESTABLISHED -j ACCEPT"

    #remove certain problematic REJECT rules
    REJECT_RULE=\`iptables -S | grep "INPUT -j REJECT --reject-with icmp-host-prohibited"\`

    if [[ ! -z "\$REJECT_RULE" ]]; then
        iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited
    fi

    REJECT_RULE2=\`iptables -S | grep "FORWARD -j REJECT --reject-with icmp-host-prohibited"\`

    if [[ ! -z "\$REJECT_RULE2" ]]; then
        iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited
    fi
EOF

(
    cd scripts
    chmod 755 iptables.sh
    ./iptables.sh
) || exit 1

###--------------------###
### Install Yq via pip ###
###--------------------###

sudo pip install yq

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

DNSCONF=/etc/NetworkManager/conf.d/openshift.conf
DNSCHANGED=""
if ! [ -f "${DNSCONF}" ]; then
    echo -e "[main]\ndns=dnsmasq" | sudo tee "${DNSCONF}"
    DNSCHANGED=1
fi
DNSMASQCONF=/etc/NetworkManager/dnsmasq.d/openshift.conf
if ! [ -f "${DNSMASQCONF}" ]; then
    echo server=/tt.testing/192.168.111.1 | sudo tee "${DNSMASQCONF}"
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
    mkdir -p /var/lib/tftpboot
    (
        cd /var/lib/tftpboot
        curl -O http://boot.ipxe.org/ipxe.efi
        curl -O http://boot.ipxe.org/undionly.kpxe
    ) || exit 1
fi

###-------------------------###
### Start HAProxy container ###
###-------------------------###

printf "\nStarting haproxy container...\n\n"

if ! ./scripts/gen_haproxy.sh build; then
    echo "HAProxy container build error.  Exiting!"
    exit 1
fi

if ! ./scripts/gen_haproxy.sh start; then
    echo "HAProxy container start error.  Exiting!"
    exit 1
fi

###--------------------------------------###
### Start provisioning dnsmasq container ###
###--------------------------------------###

printf "\nStarting provisioning dnsmasq container...\n\n"

if ! ./scripts/gen_config_prov.sh; then
    echo "Provisioning dnsmasq container config generation error.  Exiting!"
    exit 1
fi

DNSMASQ_PROV_CONTAINER=$(podman ps | grep dnsmasq-prov)

if [[ -z "$DNSMASQ_PROV_CONTAINER" ]]; then
    podman run -d --name dnsmasq-prov --net=host -v "$PROJECT_DIR/dnsmasq/prov/var/run:/var/run/dnsmasq:Z" \
        -v "$PROJECT_DIR/dnsmasq/prov/etc/dnsmasq.d:/etc/dnsmasq.d:Z" \
        --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \
        --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q
fi

###-----------------------------------###
### Start baremetal dnsmasq container ###
###-----------------------------------###

printf "\nStarting baremetal dnsmasq container...\n\n"

if ! ./scripts/gen_config_bm.sh; then
    echo "Baremetal dnsmasq container config generation error.  Exiting!"
    exit 1
fi

DNSMASQ_BM_CONTAINER=$(podman ps | grep dnsmasq-bm)

if [[ -z "$DNSMASQ_BM_CONTAINER" ]]; then
    podman run -d --name dnsmasq-bm --net=host -v "$PROJECT_DIR/dnsmasq/bm/var/run:/var/run/dnsmasq:Z" \
        -v "$PROJECT_DIR/dnsmasq/bm/etc/dnsmasq.d:/etc/dnsmasq.d:Z" \
        --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \
        --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q
fi

###----------------------------------------###
### Configure and start matchbox container ###
###----------------------------------------###

printf "\nConfiguring and starting matchbox container...\n\n"

if ! ./scripts/gen_matchbox.sh all; then
    echo "Matchbox install failed.  Exiting!"
    exit 1
fi

###----------------------------------------###
### Configure coredns Corefile and db file ###
###----------------------------------------###

printf "\nConfiguring CoreDNS...\n\n"

if ! ./scripts/gen_coredns.sh; then
    echo "CoreDNS config generation error.  Exiting!"
    exit 1
fi

###-------------------------###
### Start coredns container ###
###-------------------------###

printf "\nStarting CoreDNS container...\n\n"

if ! ./scripts/gen_coredns.sh start; then
    echo "CoreDNS container start error.  Exiting!"
    exit 1
fi

###----------------------------###
### Prepare OpenShift binaries ###
###----------------------------###

printf "\nInstalling OpenShift binaries...\n\n"

(
    cd /tmp

    if [[ ! -f "/usr/local/bin/openshift-install" ]]; then
        # FIXME: This is a cheap hack to get the latest version, but will fail if the
        # target index page's HTML fields change
        LATEST_OCP_INSTALLER=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ | grep openshift-install-linux | cut -d '"' -f 8)
        curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/$LATEST_OCP_INSTALLER"
        tar xvf "$LATEST_OCP_INSTALLER"
        sudo mv openshift-install /usr/local/bin/
    fi

    if [[ ! -f "/usr/local/bin/oc" ]]; then
        LATEST_OCP_CLIENT=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ | grep openshift-client-linux | cut -d '"' -f 8)
        curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/$LATEST_OCP_CLIENT"
        tar xvf "$LATEST_OCP_CLIENT"
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

    if [[ ! -d "/tmp/terraform-provider-matchbox" ]]; then
        git clone https://github.com/poseidon/terraform-provider-matchbox.git
        cd terraform-provider-matchbox
        go build
        mkdir -p ~/.terraform.d/plugins
        cp terraform-provider-matchbox ~/.terraform.d/plugins/.
    fi
) || exit 1

if ! ./gen_terraform.sh all; then
    echo "Terraform config generation error.  Exiting!"
    exit 1
fi

###-------------------###
### Prepare ignitions ###
###-------------------###

printf "\nGenerating ignition config...\n\n"

if ! ./scripts/gen_ignition.sh; then
    echo "Ignition config generation error.  Exiting!"
    exit 1
fi

###-----------------------------------------------------###
### Clone upi-rt repo and copy generated config into it ###
###-----------------------------------------------------###

printf "\nCloning upi-rt repo and applying generated config...\n\n"

mkdir -p upi-rt

(
    cd upi-rt

    if [[ ! -f "README.md" ]]; then
        git clone https://github.com/redhat-nfvpe/upi-rt.git .
    fi

    cp -f "$PROJECT_DIR/terraform/cluster/terraform.tfvars" terraform/cluster/.
    cp -f "$PROJECT_DIR/terraform/workers/terraform.tfvars" terraform/workers/.
) || exit 1

printf "\nDONE\n"
