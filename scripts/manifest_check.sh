#!/bin/bash

# must have at least on optional parameter for a kind
#
regex_filename="^([-_A-Za-z0-9]+)$"
regex_pos_int="^([0-9]+$)"
regex_mac_address="^(([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$)"
regex_ip_address="^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})$"

declare -A MANIFEST_CHECK
export MANIFEST_CHECK

MANIFEST_CHECK_init() {
    MANIFEST_CHECK[BareMetalHost.req.metadata.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
    MANIFEST_CHECK["BareMetalHost.opt.metadata.annotations.kni.io\/sdnNetworkMac"]="$regex_mac_address"
    MANIFEST_CHECK["BareMetalHost.opt.metadata.annotations.kni.io\/sdnIPv4"]="$regex_ip_address"
    MANIFEST_CHECK[BareMetalHost.req.spec.bootMACAddress]="$regex_mac_address"
    MANIFEST_CHECK[BareMetalHost.req.spec.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    MANIFEST_CHECK[BareMetalHost.req.spec.bmc.credentialsName]="$regex_filename"
    MANIFEST_CHECK[Secret.req.metadata.name]="$regex_filename"
    MANIFEST_CHECK[Secret.req.stringdata.username]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    MANIFEST_CHECK[Secret.req.stringdata.password]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    MANIFEST_CHECK[install-config.req.baseDomain]="^([-_A-Za-z0-9.]+)$"
    MANIFEST_CHECK[install-config.req.compute.0.replicas]="$regex_pos_int"
    MANIFEST_CHECK[install-config.req.controlPlane.replicas]="(1|3)"
    MANIFEST_CHECK[install-config.req.metadata.name]="$regex_filename"
    MANIFEST_CHECK[install-config.req.pullSecret]="(.*)"
    MANIFEST_CHECK[install-config.req.sshKey]="(.*)"

    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.role]="^(master|worker|nodeploy)$"
    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.sdnMacAddress]="$regex_mac_address"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.sdnIPAddress]="$regex_ip_address"
    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.bootMACAddress]="$regex_mac_address"    
    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    MANIFEST_CHECK[install-config.req.platform.hosts.[0-9]+.bmc.credentialsName]="$regex_filename"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.type]="(rhel|centos|rhcos)"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.pxe]="(bios|uefi)"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.pxe]="([a-zA-Z0-9]+)"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.initrd]="(.+)"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.kernel]="(.+)"
    MANIFEST_CHECK[install-config.opt.platform.hosts.[0-9]+.osProfile.kickstart]="(.+)"

}

MANIFEST_CHECK_init

# declare -A MANIFEST_CHECK=(
#     [BareMetalHost.req.metadata.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
#     ["BareMetalHost.opt.metadata.annotations.kni.io\/sdnNetworkMac"]="$regex_mac_address"
#     ["BareMetalHost.opt.metadata.annotations.kni.io\/sdnIPv4"]="$regex_ip_address"
#     [BareMetalHost.req.spec.bootMACAddress]="$regex_mac_address"
#     [BareMetalHost.req.spec.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
#     [BareMetalHost.req.spec.bmc.credentialsName]="$regex_filename"
#     [Secret.req.metadata.name]="$regex_filename"
#     [Secret.req.stringdata.username]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
#     [Secret.req.stringdata.password]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
#     ["install-config.req.baseDomain"]="^([-_A-Za-z0-9.]+)$"
#     ["install-config.req.compute.0.replicas"]="$regex_pos_int"
#     ["install-config.req.controlPlane.replicas"]="(1|3)"
#     ["install-config.req.metadata.name"]="$regex_filename"
#     ["install-config.req.pullSecret"]="(.*)"
#     ["install-config.req.sshKey"]="(.*)"

#     [install-config.req.platform.hosts.[0-9]+.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
#     [install-config.req.platform.hosts.[0-9]+.sdnMacAddress]="$regex_mac_address"
#     [install-config.opt.platform.hosts.[0-9]+.sdnIPAddress]="$regex_ip_address"
#     [install-config.req.platform.hosts.[0-9]+.bootMACAddress]="$regex_mac_address"    
#     [install-config.req.platform.hosts.[0-9]+.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
#     [install-config.req.platform.hosts.[0-9]+.bmc.credentialsName]="$regex_filename"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.type]="(rhel|centos|rhcos)"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.pxe]="(bios|uefi)"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.pxe]="([a-zA-Z0-9]+)"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.initrd]="(.+)"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.kernel]="(.+)"
#     [install-config.opt.platform.hosts.[0-9]+.osProfile.kickstart]="(.+)"

# )
