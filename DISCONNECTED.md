# Disconnected Install of a cluster

This document will guide you through the automated process of creating a local registry in an online environment, that will serve the container images for the deployment of the cluster in an offline environment.

## Summary of the process

The creation of a local registry requires a set of procedures that kni-upi-lab executes for you in an automated way. The whole process requires the creation of certificates, creating a podman container that will host the registry itself, configuring firewall if needed to allow the exposed port from the container, mirroring all the container images from the public registry to the local one, modifying the provided pull secret and injecting configuration to point to this new repository. Once this is done, the nodes without external connectivity will be able to pull the images from the bastion node and form a cluster.

## Steps

1. Change the flag called `DISCONNECTED_INSTALL` that is located in `common.sh` to True.
2. Modify if required the variables located in `scripts/gen_local_registry.sh`. These variables have default values that could be enough for a regular deployment.
3. The script `prep_bm_host.sh` will create the local registry in the bastion node.
4. Follow the general deployment documentation as the `install-config.yaml` will have the right registry to pull the images from.
