#!/bin/bash

# RHCOS images

RHCOS_IMAGES_BASE_URI=""

# Map of image name to sha256
declare -A RHCOS_IMAGES

# Map of ramdisk/kernel to boot image
declare -A RHCOS_BOOT_IMAGES

# Map of boot type to raw metal image
declare -A RHCOS_METAL_IMAGES

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.3" ]]; then
    BUILDS_JSON="$(curl -sS https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-4.3/builds.json)"

    if [[ -z "$OPENSHIFT_RHCOS_MINOR_REL" ]]; then
        # If a minor release wasn't set, get latest
        LATEST=$(jq -r '.builds[0] | if type=="object" then .id else . end' <<<"$BUILDS_JSON")
        #LATEST="${LATEST//\"/}"
        OPENSHIFT_RHCOS_MINOR_REL="$LATEST"
    fi

    RHCOS_IMAGES_BASE_URI="https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-4.3/$OPENSHIFT_RHCOS_MINOR_REL/x86_64/"

    META_JSON="$(curl -sS "$RHCOS_IMAGES_BASE_URI"meta.json)"

    FILENAME="$(echo "$META_JSON" | jq -r '.images.initramfs.path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images.initramfs.sha256')"
    RHCOS_BOOT_IMAGES["ramdisk"]="$FILENAME"

    FILENAME="$(echo "$META_JSON" | jq -r '.images.kernel.path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images.kernel.sha256')"
    RHCOS_BOOT_IMAGES["kernel"]="$FILENAME"

    FILENAME="$(echo "$META_JSON" | jq -r '.images.metal.path')"
    RHCOS_IMAGES["$FILENAME"]="$(echo "$META_JSON" | jq -r '.images.metal.sha256')"
    RHCOS_METAL_IMAGES["bios"]="$FILENAME"
    RHCOS_METAL_IMAGES["uefi"]="$FILENAME"
else
    OPENSHIFT_RHCOS_MINOR_REL="$(curl -sS https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/latest/ | grep rhcos-$OPENSHIFT_RHCOS_MAJOR_REL | head -1 | cut -d '-' -f 2)"

    RHCOS_IMAGES_BASE_URI="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/latest/"

    SHA256=$(curl -sS "$RHCOS_IMAGES_BASE_URI"sha256sum.txt)

    BASE_FILENAME="rhcos-$OPENSHIFT_RHCOS_MINOR_REL-x86_64"

    for i in "$BASE_FILENAME-installer-kernel" "$BASE_FILENAME-installer-initramfs.img" "$BASE_FILENAME-metal-bios.raw.gz" "$BASE_FILENAME-metal-uefi.raw.gz"; do
        RHCOS_IMAGES["$i"]="$(echo "$SHA256" | grep "$i" | cut -d ' ' -f 1)"
    done

    RHCOS_BOOT_IMAGES["ramdisk"]="$BASE_FILENAME-installer-initramfs.img"
    RHCOS_BOOT_IMAGES["kernel"]="$BASE_FILENAME-installer-kernel"
    RHCOS_METAL_IMAGES["bios"]="$BASE_FILENAME-metal-bios.raw.gz"
    RHCOS_METAL_IMAGES["uefi"]="$BASE_FILENAME-metal-uefi.raw.gz"
fi

# TODO: remove debug
# echo "OPENSHIFT_RHCOS_MAJOR_REL: $OPENSHIFT_RHCOS_MAJOR_REL"
# echo "OPENSHIFT_RHCOS_MINOR_REL: $OPENSHIFT_RHCOS_MINOR_REL"

export OPENSHIFT_RHCOS_MINOR_REL

# TODO: remove debug
# echo "RHCOS_IMAGES_BASE_URI: $RHCOS_IMAGES_BASE_URI"

export RHCOS_IMAGES_BASE_URI

# TODO: remove debug
# for K in "${!RHCOS_IMAGES[@]}"; do echo "$K" --- "${RHCOS_IMAGES[$K]}"; done
# for K in "${!RHCOS_METAL_IMAGES[@]}"; do echo "$K" --- "${RHCOS_METAL_IMAGES[$K]}"; done

export RHCOS_IMAGES
export RHCOS_BOOT_IMAGES
export RHCOS_METAL_IMAGES

# OCP binaries
# TODO: Is there a uniform base URL to use here like there is for images?

# 4.3 is special case, and requires getting the latest version ID from an index page
LATEST_4_3="$(curl -sS https://openshift-release-artifacts.svc.ci.openshift.org/ | awk "/4\.3\./ && !(/s390x/ || /ppc64le/)" | tail -1 | cut -d '"' -f 2)"

declare -A OCP_BINARIES=(
    [4.1]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.1/"
    [4.2]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.2/"
    [4.3]="https://openshift-release-artifacts.svc.ci.openshift.org/$LATEST_4_3"
)

# TODO: remove debug
#for K in "${!OCP_BINARIES[@]}"; do echo "$K" --- "${OCP_BINARIES[$K]}"; done

export OCP_BINARIES

OCP_CLIENT_BINARY_URL=""
OCP_INSTALL_BINARY_URL=""

FIELD_SELECTOR=8

if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.3" ]]; then
    # HACK: 4.3 has a different HTML structure than the rest
    FIELD_SELECTOR=2
fi

if [[ -z $OCP_CLIENT_BINARY_URL ]]; then
    OCP_CLIENT_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep client-linux | cut -d '"' -f $FIELD_SELECTOR)"
fi

if [[ -z $OCP_INSTALL_BINARY_URL ]]; then
    OCP_INSTALL_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep install-linux | cut -d '"' -f $FIELD_SELECTOR)"
fi

# TODO: remove debug
# echo "OCP_CLIENT_BINARY_URL: $OCP_CLIENT_BINARY_URL"
# echo "OCP_INSTALL_BINARY_URL: $OCP_INSTALL_BINARY_URL"

export OCP_CLIENT_BINARY_URL
export OCP_INSTALL_BINARY_URL
