#!/bin/bash

# NOTE: only change the next line locally -- do not commit/push to the remote repo!
OPENSHIFT_RHCOS_MAJOR_REL=""
OPENSHIFT_RHCOS_MINOR_REL=""

# Option to choose GA or CI, by default - GA.
OPENSHIFT_RHCOS_REL=""

if [[ -z $OPENSHIFT_RHCOS_MAJOR_REL || (! $OPENSHIFT_RHCOS_MAJOR_REL =~ (4.1|4.2|4.3|4.4|4.5|latest)) ]]; then
    OPENSHIFT_RHCOS_MAJOR_REL="4.4"
    OPENSHIFT_RHCOS_MINOR_REL=""
elif [[ $OPENSHIFT_RHCOS_MAJOR_REL == "latest" ]]; then
    OPENSHIFT_RHCOS_MAJOR_REL="4.5"
    OPENSHIFT_RHCOS_MINOR_REL=""
fi

# Default to GA
if [[ -z $OPENSHIFT_RHCOS_REL ]]; then
    OPENSHIFT_RHCOS_REL="GA"
fi



export OPENSHIFT_RHCOS_MAJOR_REL
export OPENSHIFT_RHCOS_MINOR_REL

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR

PATCH_NM_WAIT=true
export PATCH_NM_WAIT

DISCONNECTED_INSTALL=false
export DISCONNECTED_INSTALL

VIRTUALIZED_INSTALL=false
export VIRTUALIZED_INSTALL
