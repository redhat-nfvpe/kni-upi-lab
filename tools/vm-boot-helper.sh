#!/bin/bash

CLUSTER_NAME="kni-upi-lab"

while true; do
    vms_present=$(sudo virsh list --all | grep $CLUSTER_NAME)

    if [[ -z "$vms_present" ]]; then
        echo "$CLUSTER_NAME VMs not detected; exiting..."
        break
    fi

    for i in $(sudo virsh list --all | grep $CLUSTER_NAME | grep "shut off" | awk '{print $2}'); do
        echo "$CLUSTER_NAME node '$i' is offline; booting..."
        virsh start $i --force-boot
    done

    sleep 5
done