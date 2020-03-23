#!/bin/bash


# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

declare -A NO_TERRAFORM_MAP=(
    [bootstrap_sdn_mac_address]="true"
    [master_provisioning_interface]="true"
    [worker_provisioning_interface]="true"
    [master_baremetal_interface]="true"
    [worker_baremetal_interface]="true"
)
export NO_TERRAFORM_MAP

# The following arrays map values to key / value paris in the CLUSTER_FINAL_VALS array.
# The CLUSTER_MAP/ WORKER_MAP are used to generate terraform configuration files.
# Each entry in CLUSTER_MAP directly corresponds to a config line generated in 
# a terraform tfvarfs file.  If an entry in CLUSTER_MAP should not be included
# in terraform, add the key to the NO_TERRAFORM_MAP above.
# For example, bootstrap_sdn_mac_address is used to generate dnsmasq values but
# is not used in the terraform cluster tfvars file.
#
# The syntax of the rules are as follows...
#
#  1. "==<constant_string>"  -> terraform_key = "<constant_string"
#      <constant_string> can include env vars that are defined elsewhere
#      i.e. [bootstrap_ign_file]="==$OPENSHIFT_DIR/bootstrap.ign"
#            bootstrap_ign_file = "/home/user/project_dir/ocp/bootstrap.ign"
#
#  2. "%<yaml_reference>"    -> terraform_key = "MANIFEST_VALS[yaml_reference]"
#      <yaml_reference> should be of the form yaml_object_name.path...
#      i.e. [bootstrap_mac_address]="%bootstrap.spec.bootMACAddress"
#            bootstrap_mac_address = "contents of bootstrap.yaml(metadata.name==bootstrap)/spec.bootMACAddress"
#      yaml references can include an indirect reference to another
#      yaml object.  
#
#      i.e. bootstrap.spec.bmc.[credentialsName].password
#      In this instance [name].field references another manifest file
#      a yaml object of the name found in the credentialsName field 
#      will be used to lookup another value.  This feature can be used
#      to allow a BareMetalHost to contain the name of another Secret
#      manifest that contains IPMI crendtials
#
#  3. If a rule ends with an '@', the field will be decoded as base64
# 
#  4. Rules that start with | are optional


declare -A CLUSTER_MAP=(
    [bootstrap_ign_file]="==$OPENSHIFT_DIR/bootstrap.ign"
    [master_ign_file]="==$OPENSHIFT_DIR/master.ign"
    [matchbox_client_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.crt"
    [matchbox_client_key]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.key"
    [matchbox_trusted_ca_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/ca.crt"
    [matchbox_http_endpoint]="==$PROV_IP_MATCHBOX_HTTP_URL"
    [matchbox_rpc_endpoint]="==$PROV_IP_MATCHBOX_RPC"
# The following three need to be set after manifest processing
    [pxe_initrd_url]="==patch"
    [pxe_kernel_url]="==patch"
    [pxe_os_image_url]="==patch"
    [bootstrap_public_ipv4]="==${BM_IP_BOOTSTRAP}"
    # hardcoded as it is hardcoded in VM
    [bootstrap_mac_address]="==52:54:00:82:68:3f"
    [bootstrap_sdn_mac_address]="==52:54:00:82:68:3e"
    [bootstrap_memory_gb]="==12"
    [bootstrap_vcpu]="==6"
    [bootstrap_provisioning_bridge]="==$PROV_BRIDGE"
    [bootstrap_baremetal_bridge]="==$BM_BRIDGE"
    [bootstrap_provisioning_interface]="==ens3"
    [bootstrap_baremetal_interface]="==ens4"
    [bootstrap_install_dev]="==vda"
    [bootstrap_enable_boot_index]="==${ENABLE_BOOTSTRAP_BOOT_INDEX}"
    [nameserver]="==${BM_IP_NS}"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [master_provisioning_interface]="==$MASTER_PROV_INTF"
    [master_baremetal_interface]="==$MASTER_BM_INTF"
    [master_count]="%install-config.controlPlane.replicas"
    [virtual_masters]="==$VIRTUAL_MASTERS"
)
export CLUSTER_MAP

declare -A WORKER_MAP=(
    [matchbox_client_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.crt"
    [matchbox_client_key]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.key"
    [matchbox_trusted_ca_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/ca.crt"
    [matchbox_http_endpoint]="==$PROV_IP_MATCHBOX_HTTP_URL"
    [matchbox_rpc_endpoint]="==$PROV_IP_MATCHBOX_RPC"
    [worker_ign_file]="==$OPENSHIFT_DIR/worker.ign"
    [nameserver]="==${BM_IP_NS}"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [worker_count]="%install-config.compute.0.replicas"
    [worker_provisioning_interface]="==$WORKER_PROV_INTF"
    [worker_baremetal_interface]="==$WORKER_BM_INTF"
    [virtual_workers]="==$VIRTUAL_WORKERS"
)
export WORKER_MAP

declare -A HOSTS_MAP=(
    [\\1.name]="%install-config.platform.(hosts.[0-9]+).name"
    [\\1.role]="|%install-config.platform.(hosts.[0-9]+).role"
    [\\1.bmc.address]="%install-config.platform.(hosts.[0-9]+).bmc.address"    
    [\\1.bmc.user]="%install-config.platform.(hosts.[0-9]+).bmc.[credentialsName].stringdata.username@"
    [\\1.bmc.password]="%install-config.platform.(hosts.[0-9]+).bmc.[credentialsName].stringdata.password@"
    [\\1.bootMACAddress]="%install-config.platform.(hosts.[0-9]+).bootMACAddress"
    [\\1.sdnIPAddress]="|%install-config.platform.(hosts.[0-9]+).sdnIPAddress"
    [\\1.sdnMacAddress]="%install-config.platform.(hosts.[0-9]+).sdnMacAddress"
    [\\1.provisioning_interface]="|%install-config.platform.(hosts.[0-9]+).bootInterface"
    [\\1.baremetal_interface]="|%install-config.platform.(hosts.[0-9]+).sdnInterface"

    [\\1.osProfile.install_dev]="|%install-config.platform.(hosts.[0-9]+).osProfile.install_dev"    
    [\\1.osProfile.pxe]="|%install-config.platform.(hosts.[0-9]+).osProfile.pxe"    
    [\\1.osProfile.type]="|%install-config.platform.(hosts.[0-9]+).osProfile.type"    
    [\\1.osProfile.initrd]="|%install-config.platform.(hosts.[0-9]+).osProfile.initrd"    
    [\\1.osProfile.kernel]="|%install-config.platform.(hosts.[0-9]+).osProfile.kernel"    
    [\\1.osProfile.kickstart]="|%install-config.platform.(hosts.[0-9]+).osProfile.kickstart"    

)
export HOSTS_MAP
