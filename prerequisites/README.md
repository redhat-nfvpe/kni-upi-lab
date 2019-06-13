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
This will configure a load balancer according to this diagram:
| Port | Machines | Internal | External | Description |
| ----- | ----------- | --------- | --------- | --------- |
| 6643 | Bootstrap and control plane. You remove the bootstrap machine from the load balancer after the bootstrap machine initializes the cluster control plane. | x | x | Kubernetes APIServer |
| 22623 | Bootstrap and control plane. You remove the bootstrap machine from the load balancer after the bootstrap machine initializes the cluster control plane. | | x | Machine Config server |
| 443 | The machines that run the Ingress router pods, compute, or worker, by default. | x | x | HTTPS traffic |
| 80 | The machines that run the Ingress router pods, compute, or worker by default. | x | x | HTTP traffic |

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
[https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/Corefile](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/Corefile), [https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/db.CLUSTER_DOMAIN](https://github.com/redhat-nfvpe/upi-rt/blob/master/prerequisites/db.CLUSTER_DOMAIN) . It will create an specific DNS configuration according to this table:
| Component | Record | Description |
|--|--|--|
| Kubernetes API |`api.<cluster_name>.<base_domain>`| This DNS record must point to the load balancer for the control plane machines. This record must be resolvable by both clients external to the cluster and from all the nodes within the cluster. |
| Kubernetes API | `api-int.<cluster_name>.<base_domain>`| This DNS record must point to the load balancer for the control plane machines. This record must be resolvable from all the nodes within the cluster. |
| Routes | `*.apps.<cluster_name>.<base_domain>` | A wildcard DNS record that points to the load balancer that targets the machines that run the Ingress router pods, which are the worker nodes by default. This record must be resolvable by both clients external to the cluster and from all the nodes within the cluster. |
| etcd | `etcd-<index>.<cluster_name>.<base_domain>` | OpenShift Container Platform requires DNS records for each etcd instance to point to the control plane machines that host the instances. The etcd instances are differentiated by `<index>` values, which start with `0` and end with `n-1`, where `n` is the number of control plane machines in the cluster. The DNS record must resolve to an unicast IPV4 address for the control plane machine, and the records must be resolvable from all the nodes in the cluster. |
| etcd | `_etcd-server-ssl._tcp.<cluster_name>.<base_domain>` | For each control plane machine, OpenShift Container Platform also requires a SRV DNS record for etcd server on that machine with priority `0`, weight `10` and port `2380`. A cluster that uses three control plane machines requires the following records: |

With those prerequisities we are able to start the installation of the cluster.
