#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"
source "images_and_binaries.sh"

MATCHBOX_REPO="https://github.com/poseidon/matchbox.git"

CONTAINER_NAME="kni-matchbox"

set -o pipefail

usage() {
    cat <<-EOM
    Generate files related to $CONTAINER_NAME

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-v] [-m manfifest_dir] assets|certs|start|stop|remove
            repo     - clone the matchbox repo located at $MATCHBOX_REPO
            assets   - Download assets for $CONTAINER_NAME
            certs    - Generate certs for $CONTAINER_NAME
            start    - Start the $CONTAINER_NAME container 
            stop     - Stop the $CONTAINER_NAME container
            remove   - Stop and remove the $CONTAINER_NAME container

    Options
        -v verbose
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
EOM
    exit 0
}

make_clone() {
    make_dirs

    [ -d "$MATCHBOX_DIR/.git" ] && return

    if ! git clone "$MATCHBOX_REPO"; then
        printf "Error cloning %s!\n" "$MATCHBOX_REPO"
        exit 1
    fi
}

start_matchbox() {

    podman_exists "$CONTAINER_NAME" &&
        (podman_rm "$CONTAINER_NAME" ||
            printf "Could not remove %s!\n" "$CONTAINER_NAME")

    if ! cid=$(sudo podman run -d --net=host --name "$CONTAINER_NAME" -v "$MATCHBOX_VAR_LIB:/var/lib/matchbox:Z" \
        -v "$MATCHBOX_ETC_DIR/server:/etc/matchbox:Z,ro" quay.io/poseidon/matchbox:latest -address=0.0.0.0:8080 \
        -rpc-address=0.0.0.0:8081 -log-level=debug); then
        printf "Could not start %s container!\n" "$CONTAINER_NAME"
        exit 1
    fi
    podman_isrunning_logs "$CONTAINER_NAME" && printf "Started %s as %s...\n" "$CONTAINER_NAME" "$cid"
}

download_assets() {

    make_dirs

    (
        if cd "$MATCHBOX_VAR_LIB/assets"; then
            for asset in "${!RHCOS_IMAGES[@]}"; do
                echo "ASSET: $asset"
                if [ -f "$asset" ] && sum=$(sha256sum "$asset" | awk '{print $1}'); then
                    if [[ "${RHCOS_IMAGES[$asset]}" == "$sum" ]]; then
                        printf "%s already present with correct sha256sum..skipping...\n" "$asset"
                        continue
                    fi
                fi
                printf "Fetching %s...\n" "$RHCOS_IMAGES_BASE_URI/$asset"
                curl -O "$RHCOS_IMAGES_BASE_URI/$asset"
            done
        else
            printf "Failed to download assets..."
            exit 1
        fi
    ) || exit 1
}

make_certs() {

    (
        if cd "$MATCHBOX_DIR/scripts/tls"; then
            SAN="IP.1:$PROV_IP_MATCHBOX_IP"
            export SAN

            if ./cert-gen; then
                cp ca.crt server.crt server.key "$MATCHBOX_ETC_DIR/server"
                cp ca.crt client.crt client.key "$MATCHBOX_ETC_DIR/client"
            else
                printf "cert-gen failed!\n"
                exit 1
            fi
        else
            printf "%s does not exist, 'gen_matchbox.sh clone-repo' first?" "$MATCHBOX_DIR/scripts/tls"
            exit 1
        fi
    ) || exit 1
}

make_dirs() {

    mkdir -p ~/.matchbox || exit 1
    mkdir -p "$MATCHBOX_DIR" || exit 1
    mkdir -p "$MATCHBOX_ETC_DIR/server" || exit 1
    mkdir -p "$MATCHBOX_ETC_DIR/client" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB" || exit 1
    mkdir -p "$MATCHBOX_VAR_LIB/assets" || exit 1
}

VERBOSE="false"
export VERBOSE

while getopts ":hm:v" opt; do
    case ${opt} in
    v)
        VERBOSE="true"
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="all"
fi

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

# shellcheck disable=SC1091
source "common.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

MATCHBOX_ETC_DIR="$MATCHBOX_DATA_DIR/etc/matchbox"
MATCHBOX_VAR_LIB="$MATCHBOX_DATA_DIR/var/lib/matchbox"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$COREDNS_DIR}
out_dir=$(realpath "$out_dir")

case "$COMMAND" in
all)
    make_clone
    download_assets
    make_certs
    start_matchbox
    ;;
data)
    download_assets
    make_certs
    ;;
repo)
    make_clone
    ;;
assets)
    download_assets
    ;;
certs)
    make_certs
    ;;
start)
    start_matchbox
    ;;
stop)
    podman_stop "$CONTAINER_NAME" && printf "Stopped %s\n" "$CONTAINER_NAME" || exit 1
    ;;
remove)
    status=$(podman_rm "$CONTAINER_NAME") && printf "%s %s\n" "$CONTAINER_NAME" "$status" || exit 1
    ;;
isrunning)
    if ! podman_isrunning "$CONTAINER_NAME"; then
        printf "%s is NOT running...\n" "$CONTAINER_NAME"
        exit 1
    else
        printf "%s is running...\n" "$CONTAINER_NAME"
    fi
    ;;
*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
