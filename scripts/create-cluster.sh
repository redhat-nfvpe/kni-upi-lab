#!/bin/bash
#  You will need to install yq
#     go get gopkg.in/mikefarah/yq.v2
#

KNI_VERSION=${KNI_VERSION:-4.1}

CLUSTER_DOMAIN=${CLUSTER_DOMAIN:-tt.testing}
CLUSTER_NAME=${CLUSTER_NAME:-test1}

usage() {
    cat <<EOM
    Usage:
    $(basename $0) [-e openshift_executable_path ] [-i install_config] build_directory
    Create a cluster using openshift-install.  The search order for the openshift-install program is:
       1. -l openshift_executable_path
       2. openshift-install in $PATH
       3. $GOPATH/src/github.com/openshift/installer/bin/openshift-install
    -i install_config -- use the indicated install-config.yaml file
    build_directory -- Directly to place openshift-install output
EOM
    exit 0
}

set_variable()
{
    local varname=$1
    shift
    if [ -z "${!varname}" ]; then
        eval "$varname=\"$@\""
    else
        echo "Error: $varname already set"
        usage
    fi
}

unset OSI_LOCATION CONFIG_FILE

while getopts 'l:i:' c
do
    case $c in
        l) set_variable OSI_LOCATION $OPTARG ;;
        i) set_variable CONFIG_FILE $OPTARG ;;
        h|?) usage ;;
    esac
done

# Shift to arguments
shift $((OPTIND-1))

if [ "$#" -ne 1 ]; then
    usage
fi

if [ -v "${OSI_LOCATION}" ]; then
    if [ ! -x "${OSI_LOCATION}" ]; then
        echo "${OSI_LOCATION} does not exist or is not executable..."
        exit 1
    fi
    echo "-l location ${OSI_LOCATION}"
    CMD=${OSI_LOCATION}
else
    CMD=$(command -v openshift-install)
    if [ $? != 0 ]; then
        CMD="${GOPATH}/src/github.com/openshift/installer/bin/openshift-install"
        if [ ! -x ${CMD} ]; then
            echo "Could not find openshift-installer... GOPATH not exported?"
            exit 1
        fi
    fi
fi

ODIR=$1

if [ -d "$ODIR" ]; then
    rm -rf $ODIR
fi

mkdir -p $ODIR

if [ -f "$CONFIG_FILE" ]; then
    cp $CONFIG_FILE $ODIR
else
    ${CMD} --dir $ODIR create install-config
fi

TF_VAR_libvirt_master_memory=8192

#BASE_DOMAIN=$(cat $ODIR/install-config.yaml | yq .baseDomain | tr -d \")
#CLUSTER_NAME=$(cat $ODIR/install-config.yaml | yq .metadata.name | tr -d \")

${CMD} --dir $ODIR create manifests 

# Fix cluster-ingress-02-config.yml
tfile=$(mktemp -p ./$ODIR fooo-XXX.yaml)
rep="$CLUSTER_NAME."
cat $ODIR/manifests/cluster-ingress-02-config.yml | yq --arg nm "$rep" '.spec.domain |= sub($nm;"")' > $tfile

mv -f $tfile $ODIR/manifests/cluster-ingress-02-config.yml

export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="registry.svc.ci.openshift.org/origin/release:$KNI_VERSION" 
echo "IMAGE: $KNI_VERSION"

${CMD} --dir $ODIR create cluster

