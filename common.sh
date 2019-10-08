#!/bin/bash

# Select
#OPENSHIFT_RHCOS_MAJOR_REL="4.1"
#or
OPENSHIFT_RHCOS_MAJOR_REL="latest"

export OPENSHIFT_RHCOS_MAJOR_REL

# Select
#OPENSHIFT_RHCOS_MINOR_REL="4.1.0"
# or
OPENSHIFT_RHCOS_MINOR_REL="latest"

export OPENSHIFT_RHCOS_MINOR_REL

if [[ $OPENSHIFT_RHCOS_MAJOR_REL =~ latest ]]; then
        OPENSHIFT_RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/latest"
        OPENSHIFT_RHCOS_MINOR_REL=$(curl -sS $OPENSHIFT_RHCOS_URL/ | grep metal-bios | cut -d '"' -f 8 | cut -d '-' -f 2)
        export OPENSHIFT_RHCOS_MINOR_REL
else
    OPENSHIFT_RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/$OPENSHIFT_RHCOS_MINOR_REL"
fi

# OCP minor release should always match RHCOS
OPENSHIFT_OCP_MINOR_REL="${OPENSHIFT_RHCOS_MINOR_REL}"
export OPENSHIFT_OCP_MINOR_REL

export OPENSHIFT_RHCOS_URL

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

PATCH_NM_WAIT=true
export PATCH_NM_WAIT

#function finish() {
#
#}
#trap finish EXIT
