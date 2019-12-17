#!/bin/bash
if [ -e /opt/runonce ]; then
    rm /opt/runonce

    # create registries entry
    echo "unqualified-search-registries = ['registry.access.redhat.com', 'docker.io']" > /etc/containers/registries.conf
    systemctl restart cri-o

    # check cluster version to apply the right procedure
    VERSION_NUMBER=$(oc get clusterversion --config=/root/.kube/config  --output=jsonpath='{.items[0].status.desired.version}')
    if [[ $VERSION_NUMBER == "4.1"* ]]; then	    
        # run release image
        CLUSTER_VERSION=$(oc get clusterversion --config=/root/.kube/config --output=jsonpath='{.items[0].status.desired.image}')
        podman pull --tls-verify=false --authfile /opt/pull.json $CLUSTER_VERSION
        RELEASE_IMAGE=$(podman run --rm $CLUSTER_VERSION image machine-config-daemon)

        # run MCD image
        podman pull --tls-verify=false --authfile /opt/pull.json $RELEASE_IMAGE
        podman run -v /:/rootfs -v /var/run/dbus:/var/run/dbus -v /run/systemd:/run/systemd --privileged --rm -ti $RELEASE_IMAGE start --node-name $HOSTNAME --once-from /opt/bootstrap.ign --skip-reboot
        reboot
    elif [[ $VERSION_NUMBER == "4.2"* ]] || [[ $VERSION_NUMBER == "4.3"* ]]; then
        # run release image
	CLUSTER_VERSION=$(oc get clusterversion --config=/root/.kube/config --output=jsonpath='{.items[0].status.desired.image}')
	RELEASE_IMAGE=$(podman pull --tls-verify=false --authfile /opt/pull.json $CLUSTER_VERSION)
	RELEASE_IMAGE_MCD=$(podman run --rm $RELEASE_IMAGE image machine-config-operator)

	# run MCD image
	MCD_IMAGE=$(podman pull --tls-verify=false --authfile /opt/pull.json $RELEASE_IMAGE_MCD)
	podman run -v /:/rootfs -v /var/run/dbus:/var/run/dbus -v /run/systemd:/run/systemd --privileged --rm --entrypoint=/usr/bin/machine-config-daemon -ti $MCD_IMAGE start --node-name $HOSTNAME --once-from /opt/bootstrap.ign --skip-reboot
    else
        echo "Openshift version not supported, exiting"
	exit 1
    fi

    # fix for machine-config: enable persistent storage for journal
    mkdir -p /var/log/journal || true
    sed -i 's/#Storage=auto/Storage=persistent/' /etc/systemd/journald.conf

    reboot
fi
