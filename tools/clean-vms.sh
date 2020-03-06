#!/bin/bash

source "vbmc-funcs.sh"

CLUSTER_NAME=${1:-testing}

LIBVIRT_STORAGE_POOL="default"

for i in $(sudo virsh list --all | grep $CLUSTER_NAME | awk '{print $2}'); do
    delete_vbmc "$i"
    sudo virsh destroy $i > /dev/null 2>&1
    sudo virsh vol-delete $i.qcow2 --pool=$LIBVIRT_STORAGE_POOL
    sudo virsh undefine $i
done