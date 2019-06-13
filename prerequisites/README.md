# Prerequisites

This procedure is based in baremetal. So in order to reproduce it , you will need to have at least 3 baremetal machines + an extra one from where to run the deployment and the utilities. You will also need some specific network configuration.

## Network requirements
In order to automate the UPI deployment, this procedure has the following needs:

- Access to IPMI on the bootstrap, master and worker nodes (from the installer machine)
- A PXE network with isolated traffic
- General baremetal network
- A router capable of giving DHCP to the baremetal network . It is recommended to have static mapping, for predictable IPs and to set the hostname depending on mac address.
- The DHCP server needs to forward the DNS to a local CoreDNS instance that we are going to setup later

## Utilities
To assist with baremetal deployment, several utilities need to be deployed on the installer machine. Those are:

**Load balancer**
A load balancer is needed to alternate traffic between bootstrap and master nodes (and between masters when using HA). In order to achieve it, we are going to install haproxy on the installer laptop, and configure it with those settings: [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/haproxy.cfg](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/haproxy.cfg)
This will configure a load balancer according to the table shown at:
[https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#network-connectivity_installing-bare-metal](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#network-connectivity_installing-bare-metal)
- Load balancers section.

For this sample we are going to use the installer laptop as the load balancer, but in production there will be external load balancers managing it.

**Provisioning system**
The provisioning of the machines is relying on PXE (using matchbox). In order to achieve that, a dnsmasq instance needs to be running on the installer laptop, serving on the provisioning network. Again this is for testing purposes and more reliable methods need to be used in production.
In order to setup the dnsmasq please use the following configuration file: [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/dnsmasq-provisioning.conf](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/dnsmasq-provisioning.conf)
You will also need to create the /var/lib/tftpboot directory, and download the ipxe files there:

    mkdir -p /var/lib/tftpboot
    pushd /var/lib/tftpboot
    wget http://boot.ipxe.org/ipxe.efi
    wget http://boot.ipxe.org/undionly.kpxe
    popd

As part of the provision, a matchbox instance needs to be up and running . This can be setup in a container: [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/podman_utils.sh#L3](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/podman_utils.sh#L3)
Matchbox certificates need to be configured as well. In order to do it, please
follow this link:
[https://github.com/poseidon/matchbox/tree/master/scripts/tls](https://github.com/poseidon/matchbox/tree/master/scripts/tls)

BIOS on all machines need to be configured to be capable of booting by PXE on this network.

**DNS setup**
Next step is to setup some specific DNS configuration. This depends on cluster name and domain, so it is more flexible to run it on a configurable CoreDNS instance. So the first step is to run CoreDNS, this can be run on a container: [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/podman_utils.sh#L5](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/podman_utils.sh#L5)
Ensure that the router giving DHCP on the baremetal network sets the nameserver to the IP of that CoreDNS.
A sample configuration on a router can be seen like:

    service {
            shared-network-name baremetal {
            authoritative disable
            subnet ${BAREMETAL_CIDR}/24 {
                default-router ${ROUTER_IP}
                dns-server ${COREDNS_IP}
                domain-name ${CLUSTER_DOMAIN}
                lease 86400
                start ${BAREMETAL_IP_START} {
                    stop ${BAREMETAL_IP_END}
                }
                static-mapping ${CLUSTER_NAME}-bootstrap {
                    ip-address ${BOOTSTRAP_IP}
                    mac-address ${BOOTSTRAP_MAC}
                }
                static-mapping ${CLUSTER_NAME}-master-0 {
                    ip-address ${MASTER_IP}
                    mac-address ${MASTER_MAC}
                }
                static-mapping ${CLUSTER_NAME}-worker-0 {
                    ip-address ${WORKER_IP}
                    mac-address ${WORKER_MAC}
                }
            }
        }
        use-dnsmasq enable
    }
The CoreDNS directory needs to contain those files, configured properly:
[https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/Corefile](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/Corefile), [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/db.CLUSTER_DOMAIN](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/db.CLUSTER_DOMAIN) . It will create an specific DNS configuration according to the table shown at [https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#network-connectivity_installing-bare-metal](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#network-connectivity_installing-bare-metal) - User-provisioned DNS requirements section.

With those prerequisities we are able to start the installation of the cluster.
