#!/bin/bash

OPENSHIFT_RHCOS_MAJOR_REL="4.1"
export OPENSHIFT_RHCOS_MAJOR_REL

OPENSHIFT_RHCOS_MINOR_REL="4.1.0"
export OPENSHIFT_RHCOS_MINOR_REL

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" != "latest" ]]; then
    OPENSHIFT_RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/$OPENSHIFT_RHCOS_MINOR_REL"
else
    if [[ "$OPENSHIFT_RHCOS_URL" != "https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/latest" ]]; then
        OPENSHIFT_RHCOS_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/pre-release/latest"
        # Set minor version to whatever happens to be in the pre-release latest directory
        OPENSHIFT_RHCOS_MINOR_REL=$(curl -sS $OPENSHIFT_RHCOS_URL/ | grep metal-bios | cut -d '"' -f 8 | cut -d '-' -f 2)
        export OPENSHIFT_RHCOS_MINOR_REL
    fi
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
