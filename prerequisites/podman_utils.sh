#!/bin/bash

podman run -d --net=host --rm -v /var/lib/matchbox:/var/lib/matchbox:Z -v /etc/matchbox:/etc/matchbox:Z,ro quay.io/poseidon/matchbox:latest -address=0.0.0.0:8080 -rpc-address=0.0.0.0:8081 -log-level=debug

sudo podman run -d \
  --expose=53 --expose=53/udp \
  -p ${BAREMETAL_IP}:53:53 -p ${BAREMETAL_IP}:53:53/udp \
  -v ${COREDNS_DIRECTORY}:/etc/coredns:z \
  --name coredns \
  coredns/coredns:latest -conf /etc/coredns/Corefile
