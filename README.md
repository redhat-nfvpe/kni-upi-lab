
# KNI UPI Automation Framework

The KNI UI AF provides a series of scripts that simply the deployment of an OCP 4.x cluster using the UPI method of installation.  KNI AF is designed to leverage a prescribed hardware / network setup in order to simplify the deployment process.

The prescribed infrastructure architecture is shown below.

![KNI AF](artifacts/KNI_AF.png)

The architecture requires:

* A provisioning/bastion server where several helper applications are run.  Either Centos 7.6 or greater can be used as well as RHEL.
* One or more hardware nodes for Master Nodes
* Zero or more hardware nodes for Worker Nodes
* All master/worker hosts require two physical interfaces and an Out-Of-Band management network connection (IPMI).
  * Interface #1 will be used for provisioning and must have pxeboot capability.  This interface is attached to the provisioning network.
  * Interface #2 will carry all API/Cluster and application traffic.  This interface is attached to the baremetal network.
  * The OOB management network must be accessible from the provisioning host
* Network
  * Provisioning network -- A private, non-routed network that carries pxeboot traffic
  * Baremetal network --This network carries all OpenShift SDN traffic.
    * DHCP -- By default, DHCP is provided by an instance of DNSMASQ running on the provisioning host.  An external DHCP server can be used instead.
    * DNS -- By default, DNS is provided by an instance of CoreDNS running on the provisioning host.  An external DNS server can be used instead (See OpenShift [UPI/baremetal](https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html) documentation for DNS requirements)
    * NTP -- An NTP server must be accessible from this network

# UPI Background

## Prerequistes

Review the OpenShift Container Platform 4.x Tested Integrations page before you create the supporting infrastructure for your cluster.

### SSH Private Key

For OpenShift Container Platform clusters on which you want to perform installation debugging or disaster recovery, you must provide an SSH key that your ssh-agent process uses to the installer.

You can use this key to SSH into the master nodes as the user core. When you deploy the cluster, the key is added to the core user’s ~/.ssh/authorized_keys list.

Most times, this key is the id_rsa.pub for the installation account.  This might need to be created on the provisioning host.

### PULL-SECRET

From the [OpenShift Infrastructure Providers] (https://cloud.redhat.com/openshift/install) page, download your installation pull secret. This pull secret allows you to authenticate with the services that are provided by the included authorities, including Quay.io, which serves the container images for OpenShift Container Platform components.

### Quick Start

1. Install a Centos7/RHEL provisioning host
2. Install git
3. For a fully-virtualized install, please see [Virtualized Install](tools/)
4. For a disconnected installation of the cluster, please see [Disconnected Install](DISCONNECTED.md)


#### Populate *cluster/site-config.yaml*

The site-config.yaml file describes the infrastructure environment for the cluster.
Fill in the fields to fit your environment.

```yaml
infrastructure:
  network:
    provisioningIpCidr: 172.22.0.0/24  # The provisioning network's CIDR
    baremetalIpCidr: 192.168.111.0/24  # The baremetal networks's CIDR
    # baremetal network default gateway, set to proper IP if provHost/services/baremetalGateway == false
    baremetalGWIP: 192.168.111.4
    dns:
      # cluster DNS, change to proper IP address if provHost/services/clusterDNS == false
      cluster: 192.168.111.3
      external1: 10.11.5.19 
#     external2: 10.11.5.19 
#     external3: 10.11.5.19 

  provHost:
    interfaces:
      provisioning: eno2                  # Prov host provisioning network intf
      provisioningIpAddress: 172.22.0.10  # Prov host provisioning network intf IP address
      baremetal: ens1f0                   # Prov host baremetal network intf
      baremetalIpAddress: 192.168.111.6   # Prov host baremetal network intf IP address
      external: eno1                      # Prov host external (internet) interface
    bridges:
      provisioning: provisioning          # Name to use for the prov host provisioning bridge
      baremetal: baremetal                # Name to use for the prov host baremetal bridge
    services:
      # Does the provsioning host provide DHCP services for the baremetal network?
      baremetalDHCP: true
      # Does the provisioning host provide DNS services for the cluster?
      clusterDNS: true
      # Does the provisioning host provide a default gateway for the baremetal network?
      baremetalGateway: true
```

#### Populate cluster/install-config.yaml

The *baseDomain* field sets the cluster domain.  The *metadata/name* field sets the name of the cluster.  The remaining fields (except for *hosts* defined below) should not be changed.

Populate the *hosts:* section with information about the hardware hosts you are going to use for the cluster.  

| Field       |  Default     | Definition                           |
| ---------   | ------------ | ------------------------------------ |
| name        | none         | Either master-N or worker-M          |
| role        | none         | Either master|worker|nodeploy        |
| bmc/address | none         | ipmi:/ipaddr                         |
| bmc/credentialsName | none | Name of yaml file containing user/password |
| bootMacAddress | none | MAC address of the provisioning MAC |
| sdnMacAddress  | none | MAC address of the baremetal MAC    |
| hardwareProfile | unused | |
| osProfile/ | | |
| type       | rhcos | OS Type rhcos, centos, or rhel |
| pxe        | bios | boot method, bios or uefi |
| install_dev | sda | DISK to install OS onto... |
| initrd | depends on type | location of initramfs (Should not be set)
| kernel | depends on type | location of boot kernel (Should not be set)
| kickstart | depends on type | kickstart file to use (Should not be set)

When role==**nodeploy**, the host is not provisioned.  **nodeploy** can be used to
temporarily remove / add nodes.

Example below:

```yaml
   hosts:
      # Master nodes are always RHCOS-based
      # You must define either 1 or 3 masters
      -  name: master-0 # Must be of the form master-N or worker-M
         role: master   # Can be either master|worker|nodeploy
         bmc:
            address: ipmi://10.19.110.12
            credentialsName: ha-lab-ipmi
         bootMACAddress: 0C:C4:7A:DB:A9:93  # provisioning network mac
         sdnMacAddress: 0c:c4:7a:19:6f:92   # baremetal network mac
         # sdnIPAddress: 192.168.111.11     # Optional -- Set static IP
         hardwareProfile: default           # NOT USED
         osProfile:
            # With role == master, the osType is always rhcos
            # And with type rhcos, the following are settings are available
            pxe: bios         # pxe boot type either bios (default if not specified) or                      # uefi
                              # all masters must have the same pxe value.  
                              # Either defaulting to bios
                              # or all masters with pxe: uefi
            install_dev: sda  # where to install the operating system (sda is the default)
      -  name: worker-2
         role: worker
         bmc:
            address: ipmi://110.19.110.8
            credentialsName: ha-lab-ipmi
         bootMACAddress: 0C:C4:7A:DB:AC:03
         sdnMacAddress: 0c:c4:7a:19:6f:7e
         hardwareProfile: default
         osProfile:
            type: rhel
            # Don't set the following unless you know what you are doing
            initrd: assets/rhel8/images/pxeboot/initrd.img # (default if not specified)
            kernel: assets/rhel8/images/pxeboot/vmlinuz # (default if not specified)

```

#### Select version

Edit common.sh file and either leave the current default values

```bash
OPENSHIFT_RHCOS_MAJOR_REL="4.2"
export OPENSHIFT_RHCOS_MAJOR_REL

OPENSHIFT_RHCOS_MINOR_REL="4.2.0"
export OPENSHIFT_RHCOS_MINOR_REL
```

or change to latest

```bash
OPENSHIFT_RHCOS_MAJOR_REL="latest"
export OPENSHIFT_RHCOS_MAJOR_REL

OPENSHIFT_RHCOS_MINOR_REL="latest"
export OPENSHIFT_RHCOS_MINOR_REL
```

#### Run prep_bm_host.sh script

The prep_bm_host.sh is located in the repo directory and prepares the host for provisioning.

```bash
./prep_bm_host.sh
```

#### Make Procedure

```bash
make clean
make all
make con-start
```

If there are no errors,

```bash
cd terraform/cluster
terraform init
terraform apply --auto-approve
cd ..
cd ..
openshift-install --dir ocp wait-for install-complete
```

Wait for master nodes to deploy

```bash
cd ../workers
terraform init
terraform apply --auto-aprove
```


#### Clean up procedure if you want to reinstall.

```bash
cd terraform/cluster
terraform destroy --auto-approve
cd ../..
make clean
./clean_bm_host.sh 
```

# Enjoy your Openshift cluster

## Automation Operation

### Procedure

1. Configure DHCP.  

2. Provision the required load balancers.

3. Configure the ports for your machines.

4. Configure DNS.

5. Ensure network connectivity.

#### DHCP

The KNI AF conditionally instantiates two dnsmasq to provide DHCP for the infrastructure.  The dnsmasq containers provide DHCP for the provisioning network and the network where the OCP SND network resides.  A CoreDNS server is also started to provide DNS services for the cluster.  

#### Load Balancers

The KNI AF conditionally instantiates haproxy as a load balancer for the cluster.  KNI AF can either provide the haproxy load balancer only during install or as a permanent part of the cluster setup.  A load balancer is required for installation.

#### DNS

The KNI AF condistionally instantiates a coredns container to provide mininal DNS support for the cluster.  The coredns server provides an authoritive and recursive DNS server required by OCP.

### Networking requirements for user-provisioned infrastructure

All the Red Hat Enterprise Linux CoreOS (RHCOS) machines require network in initramfs during boot to fetch Ignition config from the Machine Config Server.

During the initial boot, the machines require a DHCP server in order to establish a network connection to download their Ignition config files.

It is recommended to use the DHCP server to manage the machines for the cluster long-term. Ensure that the DHCP server is configured to provide persistent IP addresses and host names to the cluster machines.

The Kubernetes API server must be able to resolve the node names of the cluster machines. If the API servers and worker nodes are in different zones, you can configure a default DNS search zone to allow the API server to resolve the node names. Another acceptable approach is to always refer to hosts by their fully-qualified domain names in both the node objects and all DNS requests.

You must configure the network connectivity between machines to allow cluster components to communicate. Each machine must be able to resolve the host names of all other machines in the cluster.

## Kubernetes API

Host level services, including the node exporter on ports 9100-9101 and the Cluster Version Operator on port 9099.

The default ports that Kubernetes reserves

10256

openshift-sdn

30000-32767

Kubernetes NodePort

## NETWORK TOPOLOGY REQUIREMENTS

The infrastructure that you provision for your cluster must meet the following network topology requirements.

OpenShift Container Platform requires all nodes to have internet access to pull images for platform containers and provide telemetry data to Red Hat.

## Load balancers

Before you install OpenShift Container Platform, you must provision two layer-4 load balancers.

Bootstrap and control plane. You remove the bootstrap machine from the load balancer after the bootstrap machine initializes the cluster control plane.

# Kubernetes API server

22623

Bootstrap and control plane. You remove the bootstrap machine from the load balancer after the bootstrap machine initializes the cluster control plane.

## Machine Config server

443

The machines that run the Ingress router pods, compute, or worker, by default.

HTTPS traffic

80

The machines that run the Ingress router pods, compute, or worker by default.

HTTP traffic

A working configuration for the Ingress router is required for an OpenShift Container Platform cluster. You must configure the Ingress router after the control plane initializes.

# User-provisioned DNS requirements

The following DNS records are required for a OpenShift Container Platform cluster that uses user-provisioned infrastructure. In each record, <cluster_name> is the cluster name and <base_domain> is the cluster base domain that you specify in the install-config.yaml file.

api.<cluster_name>.<base_domain>

This DNS record must point to the load balancer for the control plane machines. This record must be resolvable by both clients external to the cluster and from all the nodes within the cluster.

api-int.<cluster_name>.<base_domain>

This DNS record must point to the load balancer for the control plane machines. This record must be resolvable from all the nodes within the cluster.

The API server must be able to resolve the worker nodes by the host names that are recorded in Kubernetes. If it cannot resolve the node names, proxied API calls can fail, and you cannot retrieve logs from Pods.

Routes

*.apps.<cluster_name>.<base_domain>

A wildcard DNS record that points to the load balancer that targets the machines that run the Ingress router pods, which are the worker nodes by default. This record must be resolvable by both clients external to the cluster and from all the nodes within the cluster.

etcd

etcd-<index>.<cluster_name>.<base_domain>

OpenShift Container Platform requires DNS records for each etcd instance to point to the control plane machines that host the instances. The etcd instances are differentiated by <index> values, which start with 0 and end with n-1, where n is the number of control plane machines in the cluster. The DNS record must resolve to an unicast IPV4 address for the control plane machine, and the records must be resolvable from all the nodes in the cluster.

_etcd-server-ssl._tcp.<cluster_name>.<base_domain>

For each control plane machine, OpenShift Container Platform also requires a SRV DNS record for etcd server on that machine with priority 0, weight 10 and port 2380. A cluster that uses three control plane machines requires the following records:

| _service._proto.name. | TTL | class | SRV | priority | weight | port | target |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 | etcd-0.<cluster_name>.<base_domain>.|
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 | etcd-1.<cluster_name>.<base_domain>. |
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 | etcd-2.<cluster_name>.<base_domain>.|

| _service._proto.name.                           | TTL  |  class | SRV  | priority  | weight | port  | target. |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 |etcd-0.<cluster_name>.<base_domain>. |
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 |etcd-1.<cluster_name>.<base_domain>. |
|_etcd-server-ssl._tcp.<cluster_name>.<base_domain> | 86400 | IN | SRV | 0 | 10 | 2380 |etcd-2.<cluster_name>.<base_domain>. |
