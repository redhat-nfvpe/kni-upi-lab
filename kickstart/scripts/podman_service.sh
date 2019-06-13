#!/bin/bash
if [ -e /tmp/runonce ]; then
    rm /tmp/runonce

    # run release image
    CLUSTER_VERSION=$(oc get clusterversion --config=/root/.kube/config --output=jsonpath='{.items[0].status.desired.image}')
    podman pull --tls-verify=false --authfile /tmp/pull.json $CLUSTER_VERSION
    RELEASE_IMAGE=$(podman run --rm $CLUSTER_VERSION image machine-config-daemon)

    # run MCD image
    podman pull --tls-verify=false --authfile /tmp/pull.json $RELEASE_IMAGE
    podman run -v /:/rootfs -v /var/run/dbus:/var/run/dbus -v /run/systemd:/run/systemd --privileged --rm -ti $RELEASE_IMAGE start --node-name $HOSTNAME --once-from /tmp/bootstrap.ign
fi
