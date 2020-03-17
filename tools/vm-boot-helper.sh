#!/bin/bash

CLUSTER_NAME="kni-upi-lab"

# THIS_PID="$(pgrep -f $0)"

# Kill all other instances of this script
# for i in $(ps ax | grep "$0" | grep -v grep | awk {'print $1'}); do
#     if [[ "$i" != "$THIS_PID" ]]; then
#         sudo kill -9 $i 2>/dev/null
#     fi
# done

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