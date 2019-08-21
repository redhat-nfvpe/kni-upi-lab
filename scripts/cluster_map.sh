#!/bin/bash


# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

DEFAULT_INITRD="assets/rhcos-4.1.0-x86_64-installer-initramfs.img"
DEFAULT_KERNEL="assets/rhcos-4.1.0-x86_64-installer-kernel"

declare -A NO_TERRAFORM_MAP=(
    [bootstrap_sdn_mac_address]="true"
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
    [pxe_initrd_url]="==$DEFAULT_INITRD"
    [pxe_kernel_url]="==$DEFAULT_KERNEL"
    [pxe_os_image_url]="==$PROV_IP_MATCHBOX_HTTP_URL/assets/rhcos-4.1.0-x86_64-metal-bios.raw.gz"
    [bootstrap_public_ipv4]="==${BM_IP_BOOTSTRAP}"
    [bootstrap_mac_address]="%bootstrap.spec.bootMACAddress"
    [bootstrap_sdn_mac_address]="%bootstrap.metadata.annotations.kni.io\/sdnNetworkMac"
    [bootstrap_memory_gb]="==12"
    [bootstrap_vcpu]="==6"
    [bootstrap_provisioning_bridge]="==$PROV_BRIDGE"
    [bootstrap_baremetal_bridge]="==$BM_BRIDGE"
    [bootstrap_provisioning_interface]="==ens3"
    [bootstrap_baremetal_interface]="==ens4"
    [bootstrap_install_dev]="==vda"
    [nameserver]="==${BM_IP_NS}"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [provisioning_interface]="==$PROV_INTF"
    [baremetal_interface]="==$BM_INTF"
    [master_count]="%install-config.controlPlane.replicas"
)
export CLUSTER_MAP

declare -A CLUSTER_MASTER_MAP=(
    [master-\\1.install_dev]="=master-([012]+).metadata.name=sda"    
    # Optional rule
    [master-\\1.spec.public_ipv4]="|%master-([012]+).metadata.annotations.kni.io\/sdnIPv4"
    [master-\\1.spec.public_mac]="%master-([012]+).metadata.annotations.kni.io\/sdnNetworkMac"
    # The following is an example of a rule that allows
    # a new entry to be generated that is a constant value
    [master-\\1.metadata.ns]="=master-([012]+).metadata.name=$BM_IP_NS"
    [master-\\1.metadata.name]="%master-([012]+).metadata.name"
    [master-\\1.spec.bmc.address]="%master-([012]+).spec.bmc.address"
    [master-\\1.spec.bmc.user]="%master-([012]+).spec.bmc.[credentialsName].stringdata.username@"
    [master-\\1.spec.bmc.password]="%master-([012]+).spec.bmc.[credentialsName].stringdata.password@"
    [master-\\1.spec.bootMACAddress]="%master-([012]+).spec.bootMACAddress"
)
export CLUSTER_MASTER_MAP

declare -A WORKER_MAP=(
    [matchbox_client_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.crt"
    [matchbox_client_key]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/client.key"
    [matchbox_trusted_ca_cert]="==$MATCHBOX_DATA_DIR/etc/matchbox/client/ca.crt"
    [matchbox_http_endpoint]="==$PROV_IP_MATCHBOX_HTTP_URL"
    [matchbox_rpc_endpoint]="==$PROV_IP_MATCHBOX_RPC"
    [worker_kickstart]="==$PROV_IP_MATCHBOX_HTTP_URL/assets/rhel8-worker-kickstart.cfg"
    [worker_kernel]="==assets/rhel8/images/pxeboot/vmlinuz"
    [worker_initrd]="==assets/rhel8/images/pxeboot/initrd.img"
    [cluster_id]="%install-config.metadata.name"
    [cluster_domain]="%install-config.baseDomain"
    [worker_count]="%install-config.compute.0.replicas"
)
export WORKER_MAP

declare -A CLUSTER_WORKER_MAP=(
    [worker-\\1.metadata.ns]="=worker-([012]+).metadata.name=$BM_IP_NS"
    [worker-\\1.metadata.name]="%worker-([012]+).metadata.name"
    [worker-\\1.public_ipv4]="|%worker-([012]+).metadata.annotations.kni.io\/sdnIPv4"
    [worker-\\1.spec.public_mac]="%worker-([012]+).metadata.annotations.kni.io\/sdnNetworkMac"
    [worker-\\1.spec.bmc.address]="%worker-([012]+).spec.bmc.address"
    [worker-\\1.spec.bmc.user]="%worker-([012]+).spec.bmc.[credentialsName].stringdata.username@"
    [worker-\\1.spec.bmc.password]="%worker-([012]+).spec.bmc.[credentialsName].stringdata.password@"
    [worker-\\1.spec.bootMACAddress]="%worker-([012]+).spec.bootMACAddress"
)
export CLUSTER_WORKER_MAP