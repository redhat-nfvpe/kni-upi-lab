#!/bin/bash

# RHCOS images

JSON="$(curl -sS https://raw.githubusercontent.com/openshift/installer/release-$OPENSHIFT_RHCOS_MAJOR_REL/data/data/rhcos.json)"

RHCOS_IMAGES_BASE_URI="$(echo "$JSON" | jq -r '.baseURI')"

echo "$RHCOS_IMAGES_BASE_URI"

declare -A RHCOS_SHA256_MAP

RHCOS_SHA256_MAP["$(echo "$JSON" | jq -r '.images.initramfs.path')"]="$(echo "$JSON" | jq -r '.images.initramfs.sha256')"
RHCOS_SHA256_MAP["$(echo "$JSON" | jq -r '.images.kernel.path')"]="$(echo "$JSON" | jq -r '.images.kernel.sha256')"

if [[ $OPENSHIFT_RHCOS_MAJOR_REL == "4.3" ]]; then
    # HACK: 4.3 currently has a different JSON structure than the rest
    RHCOS_SHA256_MAP["$(echo "$JSON" | jq -r '.images.metal.path')"]="$(echo "$JSON" | jq -r '.images.metal.sha256')"
else
    RHCOS_SHA256_MAP["$(echo "$JSON" | jq -r '.images["metal-bios"].path')"]="$(echo "$JSON" | jq -r '.images["metal-bios"].sha256')"
    RHCOS_SHA256_MAP["$(echo "$JSON" | jq -r '.images["metal-uefi"].path')"]="$(echo "$JSON" | jq -r '.images["metal-uefi"].sha256')"
fi

for K in "${!RHCOS_SHA256_MAP[@]}"; do echo "$K" --- "${RHCOS_SHA256_MAP[$K]}"; done

export RHCOS_SHA256_MAP

# OCP binaries

declare -A OCP_BINARIES=(
    [4.1]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    [4.2]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/"
    [4.3]="https://openshift-release-artifacts.svc.ci.openshift.org/4.3.0-0.ci-2019-10-08-092115/"
)
export OCP_BINARIES

OCP_CLIENT_BINARY_URL=""
OCP_INSTALL_BINARY_URL=""

FIELD_SELECTOR=8

if [[ $OPENSHIFT_RHCOS_MAJOR_REL == "4.3" ]]; then
    # HACK: 4.3 has a different HTML structure than the rest
    FIELD_SELECTOR=2
fi

OCP_CLIENT_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep client-linux | cut -d '"' -f $FIELD_SELECTOR)"
OCP_INSTALL_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep install-linux | cut -d '"' -f $FIELD_SELECTOR)"

echo $OCP_CLIENT_BINARY_URL
echo $OCP_INSTALL_BINARY_URL

export OCP_CLIENT_BINARY_URL
export OCP_INSTALL_BINARY_URL