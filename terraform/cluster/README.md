# Initial cluster deployment

The cluster deployment is based in the openshift-install binary, and this sample relies on terraform and matchbox to automate the power management and provisioning. We are going to describe the workflow that needs to be followed to seutp an OCP cluster based on baremetal.

## Cluster installation steps

- Create `provisioning` and `baremetal` bridges attached to provisioning and baremetal networks on the installer host:

        # brctl show
        bridge name	    bridge id		    STP enabled	 interfaces
        baremetal		8000.ac1f6b7bea17	yes		     eno2
        provisioning	8000.ac1f6b7bea16	yes		     eno1
- As the bootstrap host will be a VM, download the specific packages for installer being a virthost:

        yum -y install qemu-kvm libvirt virt-install qemu-utils
        systemctl enable libvirtd
        systemctl start libvirtd

 - Download installer binary following those instructions: [https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html#installation-obtaining-installer_installing-bare-metal](https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html#installation-obtaining-installer_installing-bare-metal)
 - Download the client binary following those instructions: [https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html#cli-install_installing-bare-metal](https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html#cli-install_installing-bare-metal)
 - Create a cluster working directory, for example /tmp/baremetal. Generate a sample install-config.yaml file for the initial cluster deployment. For our sample, it can be something similar to:

		apiVersion: v1
		baseDomain: ${CLUSTER_DOMAIN}
		compute:
		- name: worker
		  replicas: 1
		controlPlane:
		  name: master
		  platform: {}
		  replicas: 1
		metadata:
		  name: ${CLUSTER_NAME}
		platform:
		  none: {}
		pullSecret: '${PULL_SECRET}'
		sshKey: |
		  ${SSH_KEY}
Place that file on /tmp/baremetal, and execute openshift-installer pointing there:

    ./openshift-install create ignition-configs --dir=<installation_directory>

This will generate [bootstrap|master|worker].ign , that are the ignition files used for cluster generation. There is also an auth/kubeconfig file that will be used later for enrolling the worker nodes. The ignition file generation must be performed everytime you redeploy the cluster, otherwise, certificates might expire and the user shall not be able to interact with the running cluster.

- Download the RHCOS images and place them in /var/lib/matchbox/assets directory. The images can be downloaded from [https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/) . You will need to download the *-installer-initramfs.img , *-installer-kernel  and the *-[metal-bios|metal-uefi]\* ones (this one depending on your BIOS/UEFI config). These three images need to be stored in the following path:

    /var/lib/matchbox/assets/

## Terraform configuration
In order to automate the deployment of the cluster, a terraform.tfvars.example file is provided on [https://github.com/redhat-nfvpe/upi-rt/blob/master/terraform/cluster/terraform.tfvars.example](https://github.com/redhat-nfvpe/upi-rt/blob/master/terraform/cluster/terraform.tfvars.example) . This needs to be configured according to your needs. The main vars are:
- bootstrap_ign_file (/tmp/baremetal/bootstrap.ign)
- cluster_domain
- cluster_id (same as cluster_name)
- master_count (1 on this example)
- master_ign_file (/tmp/baremetal/master.ign)
- matchbox_client_cert, matchbox_client_key, matchbox_trusted_ca_cert (path of the pre-generated matchbox certs)
- matchbox_http_endpoint (http://provisioning_ip:8080"
- matchbox_rpc_endpoint (http://provisioning_ip:8081"
- pxe_initrd_url (assets/name_to_installer-initramfs.img)
- pxe_kernel_url (assets/name_to_installer-kernel)
- pxe_os_image_url (http://${PROVISIONING_IP}:8080/name_[uefi|bios]_image
- bootstrap_public_ipv4, master_public_ipv4 (public ips for bootstrap and master nodes)
- bootstrap_mac_address, master_mac_address (MAC addresses of the NICs used for pxe booting)
- master_nodes: list of a map with: name, public_ipv4, ipmi_host, ipmi_user, ipmi_pass, mac_address (pxe mac), install_dev
- bootstrap_public_ipv4
- bootstrap_memory_gb, bootstrap_vcpu, bootstrap_install_dev (vda)
- bootstrap_provisioning_bridge (provisioning), bootstrap_baremetal_bridge (baremetal)
- bootstrap_mac_address (random mac address that will be set on bootstrap pxe interface)
- nameserver (coredns_ip)

As a side note, we strongly recommend to read carefully the terraform.tfvars.example comments to set the parameters correctly. For instance, the PXE image URLs can be http endpoints, or a relative path to the matchbox directory (/var/lib/matchbox).

Once this file is generated, you can run terraform with the following commands:

    terraform init
    terraform apply -auto-approve

These commands have to be executed inside the path where all the Terraform configs are. In the case of this repo, it is under [https://github.com/redhat-nfvpe/upi-rt/blob/master/terraform/cluster/](https://github.com/redhat-nfvpe/upi-rt/blob/master/terraform/cluster/) for the deployment of the bootstrap and the master. The worker will be explained in another section later on.

This will execute the following workflow:

 - create a bootstrap VM with an empty image, capable of booting by PXE. Start the VM
 - set next boot to PXE for master, reset power cycle
 - configure matchbox properly, moving the ignition files to the right profiles
 - starting the PXE boot of bootstrap and master, using the matching ignition files
 - machines start communicated and cluster is created

In order to watch for cluster deployment status, following command can be used:

    ./openshift-install --dir=<installation_directory> wait-for bootstrap-complete \
    --log-level debug

If something has gone wrong, we recommend you to destroy the terraform resources by executing:

    terraform destroy

This command will erase the config of the terraform resources and also will power off the nodes and destroy the bootstrap VM.

After this finishes there will be a functional cluster with 1 master running. Next step will be to enroll the worker.
