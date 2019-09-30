#!/bin/bash

usage() {
    local out_dir="$1"

    cat <<-EOM
    Generate ignition files

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir]  ignition|installer|oc
            Parse manifest files and perform tasks related to deployment

            ignition  -- Generate ignition files into $out_dir, apply any patches
            installer -- Install the current openshift-install binary
            oc        -- Install the current oc binary

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $DNSMASQ_DIR...]
EOM
    exit 0
}

gen_nm_disable_auto_config() {
    local role="$1"

    mkdir -p "$BUILD_DIR/openshift-patches"

    read -r -d '' content <<EOF
[main]
# Do not do automatic (DHCP/SLAAC) configuration on ethernet devices
# with no other matching connections.
no-auto-default=*
# Ignore the carrier (cable plugged in) state when attempting to
# activate static-IP connections.
ignore-carrier=*
EOF
    name="nm-disable-auto-config"

    mode="0644"
    path="/etc/NetworkManager/conf.d/10-${role}-$name.conf"
    metadata_name="10-${role}-$name"

    content=$(echo "$content" | base64 -w0)

    export metadata_name path mode content role

    template="$TEMPLATES_DIR/$name.yaml.tpl"
    if [ ! -f "$template" ]; then
        printf "Template \"%s\" does not exist!\n" "$template"
        return 1
    fi

    gen_manifest="$BUILD_DIR/openshift-patches/$metadata_name.yaml"
    envsubst <"${template}" >"${gen_manifest}"
}

gen_ifcfg_manifest() {
    local role="$1"
    local interface="$2"
    local defroute="$3"

    mkdir -p "$BUILD_DIR/openshift-patches"

    template_cfg="$TEMPLATES_DIR/ifcfg-interface.tpl"
    template_yaml="$TEMPLATES_DIR/ifcfg-interface.yaml.tpl"

    manifest_name="99-ifcfg-$interface-$role.yaml"

    # Generate the file contents
    export interface defroute
    content=$(envsubst <"${template_cfg}" | base64 -w0)

    mode="0644"
    path="/etc/sysconfig/network-scripts/ifcfg-$interface"
    metadata_name="99-ifcfg-$interface-$role"
    export metadata_name path mode content role

    envsubst <"${template_yaml}" >"$BUILD_DIR/openshift-patches/${manifest_name}"
}

patch_manifest() {
    local ocp_dir="$1"

    files=$(find "$PROJECT_DIR/cluster/manifest-patches" -name "*.yaml")
    if [ -n "$files" ]; then
        for patch_file in "$PROJECT_DIR"/cluster/manifest-patches/*.yaml; do
            printf "Adding %s to %s\n" "${patch_file%.*}" "manifests"
            cp "$patch_file" "$ocp_dir/manifests"
        done
    fi

    files=$(find "$PROJECT_DIR/cluster/openshift-patches" -name "*.yaml")
    if [ -n "$files" ]; then
        for patch_file in "$PROJECT_DIR"/cluster/openshift-patches/*.yaml; do
            printf "Adding %s to %s\n" "${patch_file%.*}" "openshift"
            cp "$patch_file" "$ocp_dir/openshift"
        done
    fi

    files=$(find "$BUILD_DIR/openshift-patches" -name "*.yaml")
    if [ -n "$files" ]; then
        for patch_file in "$BUILD_DIR"/openshift-patches/*.yaml; do
            printf "Adding %s to %s\n" "${patch_file%.*}" "openshift"
            cp "$patch_file" "$ocp_dir/openshift"
        done
    fi

}

gen_ignition() {
    local out_dir="$1"
    local manifest_dir="$2"

    if [ ! -f "$manifest_dir/install-config.yaml" ]; then
        printf "%s does not exists, create!" "$manifest_dir/install-config.yaml"
        exit 1
    fi

    rm -rf "$out_dir"
    mkdir -p "$out_dir"
    cp "$manifest_dir/install-config.yaml" "$out_dir"

    if ! openshift-install --log-level warn --dir "$out_dir" create manifests >/dev/null; then
        printf "openshift-install create manifests failed!\n"
        exit 1
    fi

    gen_nm_disable_auto_config "master" || exit 1
    gen_nm_disable_auto_config "worker" || exit 1

#need interfaces...

    gen_ifcfg_manifest "master"  "$MASTER_BM_INTF"  "yes" || exit 1
    gen_ifcfg_manifest "master"  "$MASTER_PROV_INTF" "no" || exit 1
    gen_ifcfg_manifest "worker"  "$WORKER_BM_INTF"  "yes" || exit 1
    gen_ifcfg_manifest "worker"  "$WORKER_PROV_INTF" "no" || exit 1

    patch_manifest "$out_dir"

    if ! openshift-install --log-level warn --dir "$out_dir" create ignition-configs >/dev/null; then
        printf "openshift-install create ignition-configs failed!\n"
        exit 1
    fi

    #
    # apply patches to ignition
    #
    if [ -z "$PATH_NM_WAIT" ]; then
        for ign in bootstrap.ign master.ign worker.ign; do
            jq '.systemd.units += [{"name": "NetworkManager-wait-online.service", 
     "dropins": [{ 
       "name": "timeout.conf", 
       "contents": "[Service]\nExecStart=\nExecStart=/usr/bin/nm-online -s -q --timeout=300" 
     }]}]' <"$out_dir/$ign" >"$out_dir/$ign.bak"

            mv "$out_dir/$ign.bak" "$out_dir/$ign"
        done
    fi

    if [ ! -f "${CLUSTER_FINAL_VALS[bootstrap_ign_file]}" ] || [ ! -f "${CLUSTER_FINAL_VALS[master_ign_file]}" ]; then
        printf "terraform cluster vars expects ignition files in the following places...\n"
        printf "\t%s\n" "bootstrap_ign_file = ${CLUSTER_FINAL_VALS[bootstrap_ign_file]}"
        printf "\t%s\n" "master_ign_file = ${CLUSTER_FINAL_VALS[master_ign_file]}"
        printf "The following Ignition files were generated\n"
        for f in "$out_dir"/*.ign; do
            printf "\t%s\n" "$f"
        done
        printf "Need to correct paths...\n"

        exit 1
    fi

}

install_openshift_bin() {
    (
        cd /tmp

        if [[ ! -f "/usr/local/bin/openshift-install" ]]; then
            if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" != "latest" ]]; then
                curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_OCP_MINOR_REL/openshift-install-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
                tar xvf "openshift-install-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
            else
                LATEST_OCP_INSTALLER=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/ | grep install-linux | cut -d '"' -f 8)
                curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/$LATEST_OCP_INSTALLER"
                tar xvf "$LATEST_OCP_INSTALLER"
            fi
            sudo mv openshift-install /usr/local/bin/
        fi

    ) || exit 1
}

install_openshift_oc() {
    (
        cd /tmp

        if [[ ! -f "/usr/local/bin/oc" ]]; then
            if [[ "$OPENSHIFT_RHCOS_MAJOR_REL" != "latest" ]]; then
                curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OPENSHIFT_OCP_MINOR_REL/openshift-client-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
                tar xvf "openshift-client-linux-$OPENSHIFT_OCP_MINOR_REL.tar.gz"
            else
                LATEST_OCP_CLIENT=$(curl https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/ | grep client-linux | cut -d '"' -f 8)
                curl -O "https://mirror.openshift.com/pub/openshift-v4/clients/ocp-dev-preview/latest/$LATEST_OCP_CLIENT"
                tar xvf "$LATEST_OCP_CLIENT"
            fi
            sudo mv oc /usr/local/bin/
        fi
    ) || exit 1
}

VERBOSE="false"
export VERBOSE

while getopts ":hvm:o:" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
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
shift $((OPTIND - 1))

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="ignition"
fi

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

if [[ -z "$PROJECT_DIR" ]]; then
    printf "Internal error!\n"
    exit 1
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
manifest_dir=$(realpath "$manifest_dir")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$OPENSHIFT_DIR}
out_dir=$(realpath "$out_dir")

gen_variables "$manifest_dir"

case "$COMMAND" in
# Parse options to the install sub command
ignition)
    gen_ignition "$out_dir" "$manifest_dir"
    ;;
installer)
    install_openshift_bin
    ;;
oc)
    install_openshift_oc
    ;;
*)
    echo "Unknown command: $COMMAND"
    usage "$out_dir"
    ;;
esac
