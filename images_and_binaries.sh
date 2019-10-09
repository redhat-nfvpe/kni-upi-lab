#!/bin/bash

# RHCOS images

BUILDS_JSON="$(curl -sS https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-$OPENSHIFT_RHCOS_MAJOR_REL/builds.json)"

if [[ -z "$OPENSHIFT_RHCOS_MINOR_REL" ]]; then
    # If a minor release wasn't set, get latest
    LATEST=$(jq -r '.builds[0] | if type=="object" then .id else . end' <<<"$BUILDS_JSON")
    #LATEST="${LATEST//\"/}"
    OPENSHIFT_RHCOS_MINOR_REL="$LATEST"
fi

# TODO: remove debug
echo "OPENSHIFT_RHCOS_MAJOR_REL: $OPENSHIFT_RHCOS_MAJOR_REL"
echo "OPENSHIFT_RHCOS_MINOR_REL: $OPENSHIFT_RHCOS_MINOR_REL"

export OPENSHIFT_RHCOS_MINOR_REL

META_JSON=""
EXTRA_FILENAME=""

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.3" ]]; then
    EXTRA_FILENAME="x86_64/"
fi

RHCOS_IMAGES_BASE_URI="https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-$OPENSHIFT_RHCOS_MAJOR_REL/$OPENSHIFT_RHCOS_MINOR_REL/$EXTRA_FILENAME"

# TODO: remove debug
echo "RHCOS_IMAGES_BASE_URI: $RHCOS_IMAGES_BASE_URI"

export RHCOS_IMAGES_BASE_URI

META_JSON="$(curl -sS "$RHCOS_IMAGES_BASE_URI"meta.json)"

# Map of image name to sha256
declare -A RHCOS_IMAGES

# Map of boot type to image
declare -A RHCOS_METAL_IMAGES

RHCOS_IMAGES["$(echo "$META_JSON" | jq -r '.images.initramfs.path')"]="$(echo "$META_JSON" | jq -r '.images.initramfs.sha256')"
RHCOS_IMAGES["$(echo "$META_JSON" | jq -r '.images.kernel.path')"]="$(echo "$META_JSON" | jq -r '.images.kernel.sha256')"

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.3" ]]; then
    # HACK: 4.3 currently has a different META_JSON structure than the rest
    FILENAME="$(echo "$META_JSON" | jq -r '.images.metal.path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images.metal.sha256')"
    RHCOS_METAL_IMAGES["bios"]="$FILENAME"
    RHCOS_METAL_IMAGES["uefi"]="$FILENAME"
else
    FILENAME="$(echo "$META_JSON" | jq -r '.images["metal-bios"].path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images["metal-bios"].sha256')"
    RHCOS_METAL_IMAGES["bios"]="$FILENAME"

    FILENAME="$(echo "$META_JSON" | jq -r '.images["metal-uefi"].path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images["metal-uefi"].sha256')"
    RHCOS_METAL_IMAGES["uefi"]="$FILENAME"
fi

# TODO: remove debug
for K in "${!RHCOS_IMAGES[@]}"; do echo "$K" --- "${RHCOS_IMAGES[$K]}"; done
for K in "${!RHCOS_METAL_IMAGES[@]}"; do echo "$K" --- "${RHCOS_METAL_IMAGES[$K]}"; done

export RHCOS_IMAGES
export RHCOS_METAL_IMAGES

# OCP binaries

# 4.3 is special case, and requires getting the latest version ID from an index page
LATEST_4_3="$(curl -sS https://openshift-release-artifacts.svc.ci.openshift.org/ | grep "4\.3\." | tail -1 | cut -d '"' -f 2)"

declare -A OCP_BINARIES=(
    [4.1]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    [4.2]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/"
    [4.3]="https://openshift-release-artifacts.svc.ci.openshift.org/$LATEST_4_3"
)

# TODO: remove debug
for K in "${!OCP_BINARIES[@]}"; do echo "$K" --- "${OCP_BINARIES[$K]}"; done

export OCP_BINARIES

OCP_CLIENT_BINARY_URL=""
OCP_INSTALL_BINARY_URL=""

FIELD_SELECTOR=8

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.3" ]]; then
    # HACK: 4.3 has a different HTML structure than the rest
    FIELD_SELECTOR=2
fi

OCP_CLIENT_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep client-linux | cut -d '"' -f $FIELD_SELECTOR)"
OCP_INSTALL_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep install-linux | cut -d '"' -f $FIELD_SELECTOR)"

# TODO: remove debug
echo "OCP_CLIENT_BINARY_URL: $OCP_CLIENT_BINARY_URL"
echo "OCP_INSTALL_BINARY_URL: $OCP_INSTALL_BINARY_URL"

export OCP_CLIENT_BINARY_URL
export OCP_INSTALL_BINARY_URL