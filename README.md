# Add real time kernel workers with OCP 4.x and UPI

The purpose of this repo is to describe the enroll of CentOS-RT nodes on an existing OCP 4.x cluster based on baremetal (using UPI workflow)

## Introduction
This procedure is based on the baremetal instructions for OCP 4.1 : [enter link description here](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html) . What is shown here is an implementation of those instructions based on matchbox for PXE and terraform for automation.

## How does it work
[Pre-requisites](https://github.com/redhat-nfvpe/upi-rt/tree/master/prerequisites)

[Initial cluster deployment](https://github.com/redhat-nfvpe/upi-rt/tree/master/terraform/cluster)

[Kickstart generation](https://github.com/redhat-nfvpe/upi-rt/tree/master/kickstart)

[Enroll worker](https://github.com/redhat-nfvpe/upi-rt/tree/master/terraform/workers)

## Credits
This is heavily based on:
[https://github.com/e-minguez/ocp4-upi-bm-pxeless-staticips](https://github.com/e-minguez/ocp4-upi-bm-pxeless-staticips)
[https://github.com/openshift/installer/tree/master/upi/metal](https://github.com/openshift/installer/tree/master/upi/metal)
