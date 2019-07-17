# Enroll worker

In order to enroll a worker node based on CentOS/RHEL, we need to execute some previous steps:
 - generate the kickstart file and place it on the assets directory as we described in previous section
 - download CentOS PXE images and place them on matchbox assets as well: [http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/initrd.img](http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/initrd.img), [http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/vmlinuz](http://mirror.centos.org/centos/7/os/x86_64/images/pxeboot/vmlinuz)

 To get PXE images for RHEL, you can download the RHEL ISO on
 [https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.6/x86_64/product-software](https://access.redhat.com/downloads/content/69/ver=/rhel---7/7.6/x86_64/product-software).
 The ISO can be mounted, then PXE images can be extracted from *images/pxeboot/*  directory.

After that, you need to use the automation on [https://github.com/redhat-nfvpe/upi-rt/tree/master/terraform/workers](https://github.com/redhat-nfvpe/upi-rt/tree/master/terraform/workers) and configure it properly to PXE boot the worker node, using CentOS images and kickstart config file, and enroll into the cluster.
The terraform configuration and procedure is similar to the master one, but with some specific configuration for worker. There is a **terraform.tfvars.example** file that needs to be renamed to terraform.tfvars and configured properly. The vars specific for the worker are:
 - worker_kernel (assets/centos.vmlinuz)
 - worker_initrd (assets/initrd.img)
 - worker_kickstart (http://PROVISIONING_IP:8080/assets/kickstart_file.cfg)
 - worker_count: number of worker nodes
 - worker_nodes: list of a map with: name, public_ipv4, ipmi_host, ipmi_user, ipmi_pass

After configuration, terraform can be applied with the same commands:

    terraform init
    terraform apply -auto-approve

This will start PXE boot of the worker node, with the right image and kickstart configuration. The worker will be installed with CentOS image, and kickstart will be used to add the additional bits for the node to be configured.

## Approving certificates
Once the worker starts the enroll process, it will expose a certificate request that needs to be approved. In order to do that, trusting by default on the nodes, this command can be executed periodically:

    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs oc adm certificate approve

Having that automated ensures that all CSRs coming to the cluster are automatically approved and nodes are joining without any blocker.

Once this procedure has completed, the worker node with CentOS (RT) joins the cluster successfully as a worker node.
