#!/bin/bash

CLUSTER_NAME=${1:-testing}

while true; do
    cluster_present=$(sudo virsh list --all | grep $CLUSTER_NAME)

    if [[ -z "$cluster_present" ]]; then
        echo "Cluster '$CLUSTER_NAME' VMs not detected; exiting..."
        break
    fi

    for i in $(sudo virsh list --all | grep $CLUSTER_NAME | grep "shut off" | awk '{print $2}'); do
        echo "Cluster '$CLUSTER_NAME' node '$i' is offline; booting..."
        virsh start $i
    done

    sleep 5
done