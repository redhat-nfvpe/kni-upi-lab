# Virtualized Install

If you would like to use kni-upi-lab with virtual masters and workers instead of baremetal, follow these steps.

## Overview

When a virtualized install is requested, we will create VMs for your master and workers nodes based on the replica counts set in your `cluster/install-config.yaml`.  We also create vBMC controllers for each VM.  After creating those VMs, we inject their data (IPMI details, interface names, MAC addresses, etc) back into `cluster/install-config.yaml` as well as into `cluster/site-config.yaml`.  

The VMs are created with reboot behavior set to destroy the VM rather than to actually reboot it.  This is due to peculiar behavior of vBMC and its interaction with libvirt.  When a VM is set to PXE boot via IPMI operating through vBMC, the VM definition loses its disk boot option.  The VM must then be destroyed, set to disk boot via IPMI/vBMC, and then started again to be able to boot from the disk.  Leaving the VM reboot behavior as the default (which is to just restart the guest OS) results in the VM looping in PXE boot mode (because it re-uses its modified VM definition that lacks the disk boot option).  Since we want to PXE boot just once, our approach is there:

1. Run a helper script that `virsh start`s any VM belonging to the cluster that is currently powered-off.
2. Set the VMs to be destroyed on reboot. 
3. Use vBMC to PXE boot the VMs (and start them), sleep a few seconds, and then set the VMs to disk boot.
4. Since the VMs are already booting, the disk-boot command does not affect the current boot.  It just modifies the VM definitions.
5. VMs finish PXE booting and attempt to reboot, but are powered-off instead due to our settings.
6. Our helper script sees the VMs powered-off and starts them.
7. Since our disk-boot command modified the VM definitions to boot from disk, they now boot from disk as they're started.

## Steps

1. Ensure that `libvirt` is installed on your provisioning host and that the `default` storage pool is created and started.
2. Ensure that `virt-install` is installed on your provisioning host.
3. Ensure that `virtualbmc` is installed on your provisioning host.
4. Edit `common.sh` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but set the `VIRTUALIZED_INSTALL` variable to `true`.
5. Edit your `cluster/install-config.yaml` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but do not worry about `platform.hosts`, as it will be automatically populated for you.
6. Edit your `cluster/site-config.yaml` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but do not worry about `provisioningInfrastructure.hosts`, `provisioningInfrastructure.virtualMasters` nor `provisioningInfrastructure.virtualWorkers`, as these will be automatically populated for you.
7. Now execute:
    ~~~sh
    ./prep_bm_host.sh
    make all
    make con-start
    ./scripts/manage.sh deploy cluster
    ~~~
8. Monitor `oc get nodes` until you see your masters in the `Ready` state.  If this step seems to be taking a long time, please see troubleshooting below.
9. Once the masters are in the `Ready` state, execute `./scripts/manage.sh deploy workers`.
10. Monitor `oc get nodes` until you see your workers in the `Ready` state.  If this step seems to be taking a long time, please see troubleshooting below.

## Troubleshooting

* Sometimes the libvirt VMs get stuck when the guest OS attempts to reboot during the installation process.  If you are interactively deploying, simply executing `virsh destroy <VM name>` on a stuck node should fix the problem.  The easiest way to detect if this problem is indeed happening is to connect to the VM with `vncviewer` and check if the console is just a persistent blinking cursor.  We have found that this issue usually resolves itself, but it takes around 30 minutes to do so.
* Sometimes the auto-approval process fails when attempting to add worker nodes to the cluster.  We are currently investigating this issue.  As a workaround, you can simply execute `./scripts/auto_approver.sh` to manually approve the workers (once their CSRs appear in `oc get csr`).