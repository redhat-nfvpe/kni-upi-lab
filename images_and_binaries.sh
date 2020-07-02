#!/bin/bash

# RHCOS images

RHCOS_IMAGES_BASE_URI=""

# Map of image name to sha256
declare -A RHCOS_IMAGES

# Map of ramdisk/kernel to boot image
declare -A RHCOS_BOOT_IMAGES

# Map of boot type to raw metal image
declare -A RHCOS_METAL_IMAGES

# Download from the official mirror site
if [ "$OPENSHIFT_RHCOS_REL" == "GA" ]; then

    OPENSHIFT_RHCOS_MINOR_REL="$(curl -sS https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/latest/ | grep rhcos-$OPENSHIFT_RHCOS_MAJOR_REL | head -1 | cut -d '-' -f 2)"

    RHCOS_IMAGES_BASE_URI="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/$OPENSHIFT_RHCOS_MAJOR_REL/latest/"

    SHA256=$(curl -sS "$RHCOS_IMAGES_BASE_URI"sha256sum.txt)

    RHCOS_BOOT_IMAGES["ramdisk"]="$(echo "$SHA256" | grep installer-initramfs | rev | cut -d ' ' -f 1 | rev)"
    RHCOS_BOOT_IMAGES["kernel"]="$(echo "$SHA256" | grep installer-kernel | rev | cut -d ' ' -f 1 | rev)"

    # Now handle metal images and map file names to sha256 values
    FILENAME_LIST=("${RHCOS_BOOT_IMAGES["kernel"]}" "${RHCOS_BOOT_IMAGES["ramdisk"]}")
    
    if [[ (  $OPENSHIFT_RHCOS_MAJOR_REL =~ (4.1|4.2)) ]]; then
        # 4.1/4.2 use separate bios and uefi metal images
        BIOS_METAL="$(echo "$SHA256" | grep metal-bios | rev | cut -d ' ' -f 1 | rev)"
        UEFI_METAL="$(echo "$SHA256" | grep metal-uefi | rev | cut -d ' ' -f 1 | rev)"

        FILENAME_LIST+=("$BIOS_METAL")
        FILENAME_LIST+=("$UEFI_METAL")

        RHCOS_METAL_IMAGES["bios"]="$BIOS_METAL"
        RHCOS_METAL_IMAGES["uefi"]="$UEFI_METAL"
    else
        # 4.3+ uses one unified metal image 
        UNIFIED_METAL="$(echo "$SHA256" | grep x86_64-metal | rev | cut -d ' ' -f 1 | rev)"
        
        FILENAME_LIST+=("$UNIFIED_METAL")
        
        RHCOS_METAL_IMAGES["bios"]="$UNIFIED_METAL"
        RHCOS_METAL_IMAGES["uefi"]="$UNIFIED_METAL"

    fi

    for i in "${FILENAME_LIST[@]}"; do
        RHCOS_IMAGES["$i"]="$(echo "$SHA256" | grep "$i" | cut -d ' ' -f 1)"
    done
else
    # Download from the internal CI registry
    BUILDS_JSON="$(curl -sS https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-$OPENSHIFT_RHCOS_MAJOR_REL/builds.json)"

    if [[ -z "$OPENSHIFT_RHCOS_MINOR_REL" ]]; then
        # If a minor release wasn't set, get latest
        LATEST=$(jq -r '.builds[0] | if type=="object" then .id else . end' <<<"$BUILDS_JSON")
        #LATEST="${LATEST//\"/}"
        OPENSHIFT_RHCOS_MINOR_REL="$LATEST"
    fi

    RHCOS_IMAGES_BASE_URI="https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-$OPENSHIFT_RHCOS_MAJOR_REL/$OPENSHIFT_RHCOS_MINOR_REL/x86_64/"

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
fi  

# TODO: remove debug
# echo "OPENSHIFT_RHCOS_MAJOR_REL: $OPENSHIFT_RHCOS_MAJOR_REL"
# echo "OPENSHIFT_RHCOS_MINOR_REL: $OPENSHIFT_RHCOS_MINOR_REL"

export OPENSHIFT_RHCOS_MINOR_REL

# TODO: remove debug
# echo "RHCOS_IMAGES_BASE_URI: $RHCOS_IMAGES_BASE_URI"

export RHCOS_IMAGES_BASE_URI

# TODO: remove debug
#for K in "${!RHCOS_IMAGES[@]}"; do echo "$K" --- "${RHCOS_IMAGES[$K]}"; done
#for K in "${!RHCOS_BOOT_IMAGES[@]}"; do echo "$K" --- "${RHCOS_BOOT_IMAGES[$K]}"; done
#for K in "${!RHCOS_METAL_IMAGES[@]}"; do echo "$K" --- "${RHCOS_METAL_IMAGES[$K]}"; done

export RHCOS_IMAGES
export RHCOS_BOOT_IMAGES
export RHCOS_METAL_IMAGES

# OCP binaries
# TODO: Is there a uniform base URL to use here like there is for images?

# 4.4 is a special case, and requires getting the latest version ID from an index page
#LATEST_4_4="$(curl -sS https://openshift-release-artifacts.svc.ci.openshift.org/ | awk "/4\.4\./ && !(/s390x/ || /ppc64le/)" | tail -1 | cut -d '"' -f 2)"

declare -A OCP_BINARIES=(
    [4.1]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.1/"
    [4.2]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.2/"
    [4.3]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.3/"
    [4.4]="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.4/"
)

# TODO: remove debug
#for K in "${!OCP_BINARIES[@]}"; do echo "$K" --- "${OCP_BINARIES[$K]}"; done

export OCP_BINARIES

OCP_CLIENT_BINARY_URL=""
OCP_INSTALL_BINARY_URL=""

FIELD_SELECTOR=8

# if [ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.4" ]; then
#     # HACK: 4.4 has a different HTML structure than the rest
#     FIELD_SELECTOR=2
# fi

if [[ -z $OCP_CLIENT_BINARY_URL ]]; then
    OCP_CLIENT_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep client-linux | cut -d '"' -f $FIELD_SELECTOR | tail -1)"
fi

if [[ -z $OCP_INSTALL_BINARY_URL ]]; then
    OCP_INSTALL_BINARY_URL="${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}$(curl -sS "${OCP_BINARIES["$OPENSHIFT_RHCOS_MAJOR_REL"]}" | grep install-linux | cut -d '"' -f $FIELD_SELECTOR | tail -1)"
fi

# TODO: remove debug
# echo "OCP_CLIENT_BINARY_URL: $OCP_CLIENT_BINARY_URL"
# echo "OCP_INSTALL_BINARY_URL: $OCP_INSTALL_BINARY_URL"

export OCP_CLIENT_BINARY_URL
export OCP_INSTALL_BINARY_URL

if [ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.4" ] || [ "$OPENSHIFT_RHCOS_MAJOR_REL" == "4.5" ]; then
	ENABLE_BOOTSTRAP_BOOT_INDEX="true"
else
	ENABLE_BOOTSTRAP_BOOT_INDEX="false"
fi
export ENABLE_BOOTSTRAP_BOOT_INDEX
