#!/bin/bash

CLUSTER_NAME=${1:-testing}

NUM_MASTERS=${2:-1}
NUM_WORKERS=${3:-1}

MASTER_PROV_MAC_PREFIX="52:54:00:82:68:4"
MASTER_BM_MAC_PREFIX="52:54:00:82:69:4"

WORKER_PROV_MAC_PREFIX="52:54:00:82:68:5"
WORKER_BM_MAC_PREFIX="52:54:00:82:69:5"

LIBVIRT_STORAGE_POOL="default"

MASTER_VBMC_PORT_START=623
WORKER_VBMC_PORT_START=624

delete_vbmc() {
    local name="$1"

    if vbmc show "$name" > /dev/null 2>&1; then
        vbmc stop "$name" > /dev/null 2>&1
        vbmc delete "$name" > /dev/null 2>&1
    fi
}

create_vbmc() {
    local name="$1"
    local port="$2"

    vbmc add "$name" --port "$port" --username admin --password admin
    vbmc start "$name" > /dev/null 2>&1
}

for i in $(sudo virsh list --all | grep $CLUSTER_NAME | awk '{print $2}'); do
    delete_vbmc "$i"
    sudo virsh destroy $i
    sudo virsh vol-delete $i.qcow2 --pool=$LIBVIRT_STORAGE_POOL
    sudo virsh undefine $i
done

for i in $(seq 1 "$NUM_MASTERS"); do
    name="$CLUSTER_NAME-master-$i"

    sudo virt-install --ram 16384 --vcpus 4 --os-variant rhel7 --cpu host-passthrough --disk size=40,pool=$LIBVIRT_STORAGE_POOL,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network=bridge:provisioning,mac="$MASTER_PROV_MAC_PREFIX$i" --network=bridge:baremetal,mac="$MASTER_BM_MAC_PREFIX$i" --name "$name" --os-type=linux --events on_reboot=restart --boot hd,network

    vm_ready=false
    for k in {1..10}; do 
        if [[ -n "$(virsh list | grep $name | grep running)" ]]; then 
            vm_ready=true
            break; 
        else 
            echo "wait $k"; 
            sleep 1; 
        fi;  
    done
    if [ $vm_ready = true ]; then 
        create_vbmc "$name" "$MASTER_VBMC_PORT_START$i"

        sleep 2

        ipmi_output=$(ipmitool -I lanplus -U admin -P admin -H 127.0.0.1 -p "$MASTER_VBMC_PORT_START$i" power off)

        if [[ "$ipmi_output" != "Chassis Power Control: Down/Off" ]]; then
            echo "IPMI failure detected -- trying to start $name vBMC again..."
            vbmc start "$name" > /dev/null 2>&1
            sleep 1
            ipmi_output=$(ipmitool -I lanplus -U admin -P admin -H 127.0.0.1 -p "$MASTER_VBMC_PORT_START$i" power off)
        fi

        echo "$name vBMC started and IPMI command succeeded!"
    fi
done

for i in $(seq 1 "$NUM_WORKERS"); do
    name="$CLUSTER_NAME-worker-$i"

    sudo virt-install --ram 16384 --vcpus 4 --os-variant rhel7 --cpu host-passthrough --disk size=40,pool=$LIBVIRT_STORAGE_POOL,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network=bridge:provisioning,mac="$WORKER_PROV_MAC_PREFIX$i" --network=bridge:baremetal,mac="$WORKER_BM_MAC_PREFIX$i" --name "$name" --os-type=linux --events on_reboot=restart --boot hd,network

    vm_ready=false
    for k in {1..10}; do 
        if [[ -n "$(virsh list | grep $name | grep running)" ]]; then 
            vm_ready=true
            break; 
        else 
            echo "wait $k"; 
            sleep 1; 
        fi;  
    done
    if [ $vm_ready = true ]; then 
        create_vbmc "$name" "$WORKER_VBMC_PORT_START$i"

        sleep 2

        ipmi_output=$(ipmitool -I lanplus -U admin -P admin -H 127.0.0.1 -p "$WORKER_VBMC_PORT_START$i" power off)

        if [[ "$ipmi_output" != "Chassis Power Control: Down/Off" ]]; then
            echo "IPMI failure detected -- trying to start $name vBMC again..."
            vbmc start "$name" > /dev/null 2>&1
            sleep 1
            ipmi_output=$(ipmitool -I lanplus -U admin -P admin -H 127.0.0.1 -p "$WORKER_VBMC_PORT_START$i" power off)
        fi

        echo "$name vBMC started and IPMI command succeeded!"
    fi
done

echo "Put the following in your install-config.yaml..."

for i in $(seq 1 "$NUM_MASTERS"); do
echo "
  - bmc:
      address: ipmi://127.0.0.1:$MASTER_VBMC_PORT_START$i
      username: admin
      password: admin
    bootMACAddress: $MASTER_PROV_MAC_PREFIX$i
    hardwareProfile: default
    name: master-$i
    osProfile:
      install_dev: vda
      pxe: bios
    role: master
    sdnMacAddress: $MASTER_BM_MAC_PREFIX$i"
done

# for i in $(seq 1 "$NUM_WORKERS"); do
# done