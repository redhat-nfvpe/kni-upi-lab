#!/bin/bash

source "common.sh"
source "$PROJECT_DIR/tools/vbmc-funcs.sh"

CLUSTER_NAME="kni-upi-lab"

LIBVIRT_STORAGE_POOL="default"

# Disable vm-boot-helper 
sudo systemctl disable vmboot

for i in $(sudo virsh list --all | grep $CLUSTER_NAME | awk '{print $2}'); do
    delete_vbmc "$i"
    sudo virsh destroy $i > /dev/null 2>&1
    sudo virsh vol-delete $i.qcow2 --pool=$LIBVIRT_STORAGE_POOL
    sudo virsh undefine $i
done
