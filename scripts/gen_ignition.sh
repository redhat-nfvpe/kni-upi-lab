#!/bin/bash

usage() {
    local out_dir="$1"

    cat <<-EOM
    Generate ignition files

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir]  ignition|installer|oc
            Parse manifest files and perform tasks related to deployment

            create-manifests  -- Generate manifest files
            creaate-output    -- Generate ignition files and place into $out_dir, apply any patches
            installer         -- Install the current openshift-install binary
            oc                -- Install the current oc binary

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $MANIFEST_DIR
        -o out_dir -- Where to put the output [defaults to $OPENSHIFT_DIR...]
EOM
    exit 0
}

gen_nm_disable_auto_config() {

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

    for role in master worker; do
        path="/etc/NetworkManager/conf.d/10-${role}-$name.conf"
        metadata_name="10-${role}-$name"

        gen_machineconfig $role "0644" $path $metadata_name "$content"
    done
}

gen_machineconfig() {
    local role="$1"
    local mode="$2"
    local path="$3"
    local metadata_name="$4"
    local content="$5"

    mkdir -p "$BUILD_DIR/openshift-patches"

    content=$(echo "$content" | base64 -w0)

    template="$TEMPLATES_DIR/machineconfig.yaml.tpl"
    if [ ! -f "$template" ]; then
        printf "Template \"%s\" does not exist!\n" "$template"
        return 1
    fi
    export metadata_name path mode content role

    gen_manifest="$BUILD_DIR/openshift-patches/$metadata_name.yaml"

    envsubst <"${template}" >"${gen_manifest}"
}

gen_ifcfg_manifest() {
    local role="$1"
    local interface="$2"
    local defroute="$3"

    template_cfg="$TEMPLATES_DIR/ifcfg-interface.tpl"

    # Generate the file contents
    export interface defroute
    content=$(envsubst <"${template_cfg}")

    path="/etc/sysconfig/network-scripts/ifcfg-$interface"
    metadata_name="99-ifcfg-$interface-$role"

    gen_machineconfig "$role" "0644" "$path" "$metadata_name" "$content"
}

cp_manifest() {
    local dir=$1
    local ocp_dir=$2

    for patch_file in "$dir"/*; do
        [ -f "$patch_file" ] || continue
        printf "Adding %s to %s\n" "${patch_file#$PROJECT_DIR/}" "${ocp_dir#$PROJECT_DIR/}"
        cp "$patch_file" "$ocp_dir"
    done
}

patch_manifest() {
    local ocp_dir="$1"
    local standalone="$2"

    if [[ $standalone =~ true ]]; then
        cp_manifest "$PROJECT_DIR/cluster/standalone/openshift" "$ocp_dir/openshift"
        cp_manifest "$PROJECT_DIR/cluster/standalone/manifest" "$ocp_dir/manifests"

	# TODO remove this workaround for 4.4 deployment
	if [[ $OPENSHIFT_RHCOS_MAJOR_REL == "4.4" ]]; then
		printf "Overwriting 02_autoapprover_statefulset.yaml for 4.4 StatefulSet API change"
		cp -f "$PROJECT_DIR/cluster/standalone/openshift/4.4/02_autoapprover_statefulset-4.4.yaml" \
			"$ocp_dir/openshift/02_autoapprover_statefulset.yaml"
	fi
    fi

    cp_manifest "$PROJECT_DIR/cluster/openshift-patches" "$ocp_dir/openshift"
    cp_manifest "$PROJECT_DIR/cluster/manifest-patches" "$ocp_dir/manifests"

    cp_manifest "$BUILD_DIR/openshift-patches" "$ocp_dir/openshift"
}

gen_manifests() {
    local out_dir="$1"
    local manifest_dir="$2"

    if [ ! -f "$manifest_dir/install-config.yaml" ]; then
        printf "%s is missing!" "$manifest_dir/install-config.yaml"
        exit 1
    fi

    rm -rf "$out_dir"
    mkdir -p "$out_dir"
    cp "$manifest_dir/install-config.yaml" "$out_dir"

    if ! "$REQUIREMENTS_DIR/openshift-install" --log-level warn --dir "$out_dir" create manifests >/dev/null; then
        printf "%s create manifests failed!\n" "$REQUIREMENTS_DIR/openshift-install"
        exit 1
    fi
}

gen_ignition() {
    local out_dir="$1"
    local standalone="$2"

    gen_nm_disable_auto_config "master" || exit 1
    gen_nm_disable_auto_config "worker" || exit 1

    gen_ifcfg_manifest "master" "$MASTER_BM_INTF" "yes" || exit 1
    gen_ifcfg_manifest "master" "$MASTER_PROV_INTF" "no" || exit 1
    gen_ifcfg_manifest "worker" "$WORKER_BM_INTF" "yes" || exit 1
    gen_ifcfg_manifest "worker" "$WORKER_PROV_INTF" "no" || exit 1

    patch_manifest "$out_dir" "$standalone"

    if ! "$REQUIREMENTS_DIR/openshift-install" --log-level warn --dir "$out_dir" create ignition-configs >/dev/null; then
        printf "%s create ignition-configs failed!\n" "$REQUIREMENTS_DIR/openshift-install"
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

        if [ ! -f "$REQUIREMENTS_DIR/openshift-install" ]; then
            curl -O "$OCP_INSTALL_BINARY_URL"
            tar xvf "${OCP_INSTALL_BINARY_URL##*/}"
            mkdir -p "$REQUIREMENTS_DIR"
            sudo mv openshift-install "$REQUIREMENTS_DIR"
        fi

    ) || exit 1
}

install_openshift_oc() {
    (
        cd /tmp

        if [ ! -f "$REQUIREMENTS_DIR/oc" ]; then
            curl -O "$OCP_CLIENT_BINARY_URL"
            tar xvf "${OCP_CLIENT_BINARY_URL##*/}"
            mkdir -p "$REQUIREMENTS_DIR"
            sudo mv oc "$REQUIREMENTS_DIR"
        fi

    ) || exit 1
}

VERBOSE="false"
export VERBOSE

while getopts ":hvm:o:s" opt; do
    case ${opt} in
    s)
        standalone="true"
        ;;
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
ignition)
    gen_manifests "$out_dir" "$manifest_dir"
    gen_ignition "$out_dir" "$standalone"
    ;;
# Parse options to the install sub command
create-output)
    gen_ignition "$out_dir" "$standalone"
    ;;
create-manifests)
    gen_manifests "$out_dir" "$manifest_dir"
    ;;
installer)
    # shellcheck disable=SC1091
    source "images_and_binaries.sh"

    install_openshift_bin
    ;;
oc)
    # shellcheck disable=SC1091
    source "images_and_binaries.sh"

    install_openshift_oc
    ;;
*)
    echo "Unknown command: $COMMAND"
    usage "$out_dir"
    ;;
esac
