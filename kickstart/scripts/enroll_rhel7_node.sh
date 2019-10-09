#!/bin/bash
set -eux
dhclient eth1 || true

# create directories for cri-o before it gets started
mkdir -p {/var/lib/cni/bin,/etc/kubernetes/cni/net.d,/opt/cni/bin}
chown root:root /var/lib/cni/bin /etc/kubernetes/cni/net.d /opt/cni/bin
chmod 755 /var/lib/cni/bin /etc/kubernetes/cni/net.d /opt/cni/bin

# enable subscription
source /etc/profile.env
subscription-manager register --username $RH_USERNAME --password $RH_PASSWORD --force
subscription-manager attach --pool=$RH_POOL || true
subscription-manager repos --enable=rhel-7-server-rpms
subscription-manager repos --enable=rhel-7-server-extras-rpms
subscription-manager repos --enable=rhel-7-server-rh-common-rpms
subscription-manager repos --enable=rhel-7-server-ose-4.1-rpms

yum update -y

yum -y -t install git epel-release wget kernel irqbalance microcode_ctl systemd selinux-policy-targeted setools-console dracut-network passwd openssh-server openssh-clients podman skopeo runc containernetworking-plugins cri-tools nfs-utils NetworkManager dnsmasq lvm2 iscsi-initiator-utils sg3_utils device-mapper-multipath xfsprogs e2fsprogs mdadm cryptsetup chrony logrotate sssd shadow-utils sudo coreutils less tar xz gzip bzip2 rsync tmux nmap-ncat net-tools bind-utils strace bash-completion vim-minimal nano authconfig iptables-services biosdevname container-storage-setup cloud-utils-growpart glusterfs-fuse cri-o openshift-clients openshift-hyperkube

# enable cri-o
systemctl enable cri-o

# disable swap
swapoff -a

# maskin firewalld, iptables
systemctl mask firewalld iptables

# enable ip forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl --system

# set sebool container_manage_cgroup, disable selinux
setsebool -P container_manage_cgroup on || true
setenforce 0 || true

# create temporary directory and extract contents there
IGNITION_URL=$(cat /tmp/ignition_endpoint )
curl -k $IGNITION_URL -o /tmp/bootstrap.ign

cat <<EOL > /etc/systemd/system/runignition.service
[Unit]
Description=Run ignition commands
Requires=network-online.target
After=network-online.target

[Service]
ExecStart=/tmp/runignition.sh

[Install]
WantedBy=multi-user.target
EOL

chmod 664 /etc/systemd/system/runignition.service
systemctl enable runignition

sed -i '/^.*linux16.*/ s/$/ rd.neednet=1/' /boot/grub2/grub.cfg
