#!/bin/bash

# must have at least on optional parameter for a kind
#
regex_filename="^([-_A-Za-z0-9]+)$"
regex_pos_int="^([0-9]+$)"
regex_mac_address="^(([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$)"
regex_ip_address="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"

declare -A MANIFEST_CHECK=(
    [BareMetalHost.req.metadata.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
    [BareMetalHost.opt.metadata.annotations.kni.io / sdnNetworkMac]="$regex_mac_address"
    [BareMetalHost.opt.metadata.annotations.kni.io / sdnIPv4]="$regex_ip_address"
    [BareMetalHost.req.spec.bootMACAddress]="$regex_mac_address"
    [BareMetalHost.req.spec.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    [BareMetalHost.req.spec.bmc.credentialsName]="$regex_filename"
    [Secret.req.metadata.name]="$regex_filename"
    [Secret.req.stringdata.username]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    [Secret.req.stringdata.password]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    [install - config.req.baseDomain]="^([-_A-Za-z0-9.]+)$"
    [install - config.req.compute.0.replicas]="$regex_pos_int"
    [install - config.req.controlPlane.replicas]="$regex_pos_int"
    [install - config.req.metadata.name]="$regex_filename"
    #   [install-config.req.platform.none]="\s*\{\s*\}\s*"
    [install - config.req.pullSecret]="(.*)"
    [install - config.req.sshKey]="(.*)"
)

export MANIFEST_CHECK