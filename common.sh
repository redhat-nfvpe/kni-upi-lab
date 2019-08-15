#!/bin/bash

OPENSHIFT_RHCOS_MAJOR_REL="4.1"
export OPENSHIFT_RHCOS_MAJOR_REL

OPENSHIFT_RHCOS_MINOR_REL="4.1.0"
export OPENSHIFT_RHCOS_MINOR_REL

OPENSHIFT_RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/$OPENSHIFT_RHCOS_MINOR_REL"
export OPENSHIFT_RHCOS_URL


PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

#function finish() {
#
#}
#trap finish EXIT
