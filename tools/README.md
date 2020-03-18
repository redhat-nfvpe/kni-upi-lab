# Virtualized Install

If you would like to use kni-upi-lab with virtual masters and workers instead of baremetal, follow these steps.

## Steps

1. Ensure that `libvirt` is installed on your provisioning host and that the `default` storage pool is created and started.
2. Ensure that `virt-install` is installed on your provisioning host.
3. Edit `common.sh` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but set the `VIRTUALIZED_INSTALL` variable to `true`.
4. Edit your `cluster/install-config.yaml` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but do not worry about `platform.hosts`, as it will be automatically populated for you.
5. Edit your `cluster/site-config.yaml` as described in the [README](https://github.com/redhat-nfvpe/kni-upi-lab/blob/master/README.md), but do not worry about `provisioningInfrastructure.hosts`, `provisioningInfrastructure.virtualMasters` nor `provisioningInfrastructure.virtualWorkers`, as these will be automatically populated for you.
6. Now execute:
    ~~~sh
    ./prep_bm_host.sh
    make all
    make con-start
    ./scripts/manage.sh deploy cluster
    ~~~
7. Monitor `oc get nodes` until you see your masters in the `Ready` state.  If this step seems to be taking a long time, please see troubleshooting below.
8. Once the masters are in the `Ready` state, execute `./scripts/manage.sh deploy workers`.
9. Monitor `oc get nodes` until you see your workers in the `Ready` state.  If this step seems to be taking a long time, please see troubleshooting below.

## Troubleshooting

* Sometimes the libvirt VMs get stuck when the guest OS attempts to reboot during the installation process.  If you are interactively deploying, simply executing `virsh destroy <VM name>` on a stuck node should fix the problem.  The easiest way to detect if this problem is indeed happening is to connect to the VM with `vncviewer` and check if the console is just a persistent blinking cursor.  We have found that this issue usually resolves itself, but it takes around 30 minutes to do so.
* Sometimes the auto-approval process fails when attempting to add worker nodes to the cluster.  We are currently investigating this issue.  As a workaround, you can simply execute `./scripts/auto_approver.sh` to manually approve the workers.