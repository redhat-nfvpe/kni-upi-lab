#!/bin/bash
set -eux
# enable subscription
source /etc/profile.env
subscription-manager register --username $RH_USERNAME --password $RH_PASSWORD --force
subscription-manager attach --pool=$RH_POOL
subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms
subscription-manager repos --enable=rhel-8-for-x86_64-appstream-rpms

# install packages
subscription-manager repos --enable=rhocp-4.1-for-rhel-8-x86_64-rpms

dnf update -y

dnf -y install git wget kernel irqbalance microcode_ctl systemd selinux-policy-targeted setools-console dracut-network passwd openssh-server openssh-clients podman skopeo runc containernetworking-plugins nfs-utils NetworkManager dnsmasq lvm2 iscsi-initiator-utils sg3_utils device-mapper-multipath xfsprogs e2fsprogs mdadm cryptsetup chrony logrotate sssd shadow-utils sudo coreutils less tar xz gzip bzip2 rsync tmux nmap-ncat net-tools bind-utils strace bash-completion vim-minimal nano authconfig iptables-services biosdevname cloud-utils-growpart glusterfs-fuse cri-o cri-tools openshift-clients openshift-hyperkube

# enable cri-o
systemctl enable cri-o

# disable swap
swapoff -a

# maskin firewalld, iptables and nftables (required by OCP in RHEL8)
systemctl mask firewalld iptables nftables

# enable ip forwarding
sysctl -w net.ipv4.ip_forward=1
sysctl --system

# set sebool container_manage_cgroup, disable selinux
setsebool -P container_manage_cgroup on || true
setenforce 0

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

# Inject NM Workaround (required for OCP with multiple physical NICs)
sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/nm-online -s -q --timeout=300|" /usr/lib/systemd/system/NetworkManager-wait-online.service

sed -i '/^.*linux16.*/ s/$/ ip=eno1:dhcp ip=eno2:dhcp rd.neednet=1/' /boot/grub2/grub.cfg
