#!/bin/bash

for csr in $(oc get csr --no-headers | grep Pending | cut -d " " -f1); do
  oc adm certificate approve "$csr"
done
