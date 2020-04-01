#!/bin/bash

source "common.sh"
source "$PROJECT_DIR/tools/vbmc-funcs.sh"

CLUSTER_NAME="kni-upi-lab"

NUM_MASTERS=$(yq -r '.controlPlane.replicas' $PROJECT_DIR/cluster/install-config.yaml)
NUM_WORKERS=$(yq -r '.compute[0].replicas' $PROJECT_DIR/cluster/install-config.yaml)

MASTER_PROV_MAC_PREFIX="52:54:00:82:68:4"
MASTER_BM_MAC_PREFIX="52:54:00:82:69:4"

WORKER_PROV_MAC_PREFIX="52:54:00:82:68:5"
WORKER_BM_MAC_PREFIX="52:54:00:82:69:5"

MASTER_VBMC_PORT_START=624
WORKER_VBMC_PORT_START=625

LIBVIRT_STORAGE_POOL="default"

(
    $PROJECT_DIR/tools/clean-vms.sh
) || exit 1

for i in $(seq 0 $((NUM_MASTERS - 1))); do
    name="$CLUSTER_NAME-master-$i"

    sudo virt-install --ram 16384 --vcpus 4 --os-variant rhel7 --cpu host-passthrough --disk size=40,pool=$LIBVIRT_STORAGE_POOL,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network=bridge:provisioning,mac="$MASTER_PROV_MAC_PREFIX$i" --network=bridge:baremetal,mac="$MASTER_BM_MAC_PREFIX$i" --name "$name" --os-type=linux --events on_reboot=destroy,on_lockfailure=poweroff --boot hd,network

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

        ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "$MASTER_VBMC_PORT_START$i" power off)

        RETRIES=0

        while [[ "$ipmi_output" != "Chassis Power Control: Down/Off" ]]; do
            if [[ $RETRIES -ge 2 ]]; then
                echo "FAIL: Unable to start $name vBMC!"
                exit 1
            fi

            echo "IPMI failure detected -- trying to start $name vBMC again..."
            vbmc start "$name" > /dev/null 2>&1
            sleep 1
            ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "$MASTER_VBMC_PORT_START$i" power off)
            RETRIES=$((RETRIES+1))
        done

        echo "$name vBMC started and IPMI command succeeded!"
    fi
done

for i in $(seq 0 $((NUM_WORKERS - 1))); do
    name="$CLUSTER_NAME-worker-$i"

    sudo virt-install --ram 16384 --vcpus 4 --os-variant rhel7 --cpu host-passthrough --disk size=40,pool=$LIBVIRT_STORAGE_POOL,device=disk,bus=virtio,format=qcow2 --import --noautoconsole --vnc --network=bridge:provisioning,mac="$WORKER_PROV_MAC_PREFIX$i" --network=bridge:baremetal,mac="$WORKER_BM_MAC_PREFIX$i" --name "$name" --os-type=linux --events on_reboot=destroy,on_lockfailure=poweroff --boot hd,network

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

        ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "$WORKER_VBMC_PORT_START$i" power off)

        RETRIES=0

        while [[ "$ipmi_output" != "Chassis Power Control: Down/Off" ]]; do
            if [[ $RETRIES -ge 2 ]]; then
                echo "FAIL: Unable to start $name vBMC!"
                exit 1
            fi

            echo "IPMI failure detected -- trying to start $name vBMC again..."
            vbmc start "$name" > /dev/null 2>&1
            sleep 1
            ipmi_output=$(ipmitool -I lanplus -U ADMIN -P ADMIN -H 127.0.0.1 -p "$WORKER_VBMC_PORT_START$i" power off)
            RETRIES=$((RETRIES+1))
        done

        echo "$name vBMC started and IPMI command succeeded!"
    fi
done

#
# Update cluster/install-config.yaml
#

PLATFORM_HOSTS=""

for i in $(seq 0 $((NUM_MASTERS - 1))); do
    PLATFORM_HOSTS="$PLATFORM_HOSTS{\"bmc\": {\"address\": \"ipmi://127.0.0.1:$MASTER_VBMC_PORT_START$i\", \"credentialsName\": \"ha-lab-ipmi\"}, \"bootMACAddress\": \"$MASTER_PROV_MAC_PREFIX$i\", \"hardwareProfile\": \"default\", \"name\": \"master-$i\", \"osProfile\": {\"install_dev\": \"vda\", \"pxe\": \"bios\"}, \"role\": \"master\", \"sdnMacAddress\": \"$MASTER_BM_MAC_PREFIX$i\"},"
done

for i in $(seq 0 $((NUM_WORKERS - 1))); do
    PLATFORM_HOSTS="$PLATFORM_HOSTS{\"bmc\": {\"address\": \"ipmi://127.0.0.1:$WORKER_VBMC_PORT_START$i\", \"credentialsName\": \"ha-lab-ipmi\"}, \"bootMACAddress\": \"$WORKER_PROV_MAC_PREFIX$i\", \"hardwareProfile\": \"default\", \"name\": \"worker-$i\", \"osProfile\": {\"install_dev\": \"vda\", \"pxe\": \"bios\"}, \"role\": \"worker\", \"sdnMacAddress\": \"$WORKER_BM_MAC_PREFIX$i\"},"
done

PLATFORM_HOSTS=$(echo $PLATFORM_HOSTS | sed 's/.$//')

TJQ=$(yq -y ".platform.hosts = [$PLATFORM_HOSTS]" < $PROJECT_DIR/cluster/install-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/install-config.yaml

echo "$PROJECT_DIR/cluster/install-config.yaml updated with virtualization data!"

#
# Update cluster/site-config.yaml
#

TJQ=$(yq -y '.provisioningInfrastructure.hosts.masterBootInterface="ens3"' < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml
TJQ=$(yq -y '.provisioningInfrastructure.hosts.masterSdnInterface="ens4"' < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml
TJQ=$(yq -y '.provisioningInfrastructure.hosts.workerBootInterface="ens3"' < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml
TJQ=$(yq -y '.provisioningInfrastructure.hosts.workerSdnInterface="ens4"' < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml

TJQ=$(yq -y ".provisioningInfrastructure.virtualMasters = true" < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml
TJQ=$(yq -y ".provisioningInfrastructure.virtualWorkers = true" < $PROJECT_DIR/cluster/site-config.yaml) 
[[ $? == 0 ]] && echo "${TJQ}" >| $PROJECT_DIR/cluster/site-config.yaml

echo "$PROJECT_DIR/cluster/site-config.yaml updated with virtualization data!"

#
# Start the VM boot helper script
#

$PROJECT_DIR/tools/vm-boot-helper.sh &
