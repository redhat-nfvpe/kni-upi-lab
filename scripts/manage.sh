#!/bin/bash

usage() {
    local out_dir="$1"

    prog=$(basename "$0")
    cat <<-EOM
    Manage the cluster -- deploy | destroy

    Usage:
        $prog [-h] [-m manfifest_dir]  deploy|destroy|pxeboot
            deploy [cluster|workers]   -- Deploy cluster or worker nodes.  Run for initial deploy or after worker hosts have been changed
                         in install-config.yaml.  Master nodes cannot be changed (added or removed) after an
                         initial deploy.  
            destroy [cluster|workers]  -- Destroy workers or all nodes in the cluster. (destroy cluster first destroys worker nodes)
            pxeboot hostname           -- Force a pxeboot of the host (i.e. $prog pxeboot worker-1)

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $DNSMASQ_DIR...]
EOM
    exit 0
}

pxeboot() {
    local host="$1"

    local cluster_domain="${CLUSTER_FINAL_VALS[cluster_domain]}"

    # accept either worker-0 or test1-worker-0
    host=${host/$cluster_domain-/}

    user=$(get_host_var "$host" "bmc.user") || return 1
    password=$(get_host_var "$host" "bmc.password") || return 1
    address=$(get_host_var "$host" "bmc.address") || return 1

    if ! ipmitool -I lanplus -H "$address" -U "$user" -P "$password" chassis bootdev pxe; then
        printf "Could not set bootdev pxe host %s at %s!\n" "$host" "$address"
        return 1
    fi
    sleep 2
    if ! ipmitool -I lanplus -H "$address" -U "$user" -P "$password" chassis power cycle; then
        printf "Could not power cycle host %s at %s!\n" "$host" "$address"
        return 1
    fi
}

manage_cluster() {
    cmd="$1"

    if [[ ! $cmd =~ ^apply$|^destroy$ ]]; then
        printf "Invalid cmd %s\n" "$cmd"
        return 1
    fi

    [[ "$VERBOSE" =~ true ]] && printf "%s cluster...\n" "$cmd"

    (
        cd "$TERRAFORM_DIR/cluster" || return 1

        if ! terraform init; then
            printf "terraform init failed!\n"
            return 1
        fi

        if ! terraform "$cmd" --auto-approve; then
            printf "terraform %s failed!\n" "$cmd"
            return 1
        fi
    )

    if [[ $cmd =~ apply ]]; then
        printf "Check the status of the deployment with the following command...\n\n"
        printf "openshift-install --dir %s wait-for install-complete\n" "$OPENSHIFT_DIR"
    fi
}

manage_workers() {
    cmd="$1"

    if [[ ! $cmd =~ ^apply$|^destroy$ ]]; then
        printf "Invalid cmd %s\n" "$cmd"
        return 1
    fi

    [[ "$VERBOSE" =~ true ]] && printf "%s workers...\n" "$cmd"

    (
        cd "$TERRAFORM_DIR/workers" || return 1

        if ! terraform init; then
            printf "terraform init failed!\n"
            return 1
        fi
        if ! terraform "$cmd" --auto-approve; then
            printf "terraform %s failed!\n" "$cmd"
            return 1
        fi
    )
}

deploy() {
    local command="$1"

    [ -z "$command" ] && command="cluster"

    case $command in
    cluster)
        manage_cluster "apply"
        ;;
    workers)
        manage_workers "apply"
        ;;
    *)
        printf "Unknown deploy sub command %s!\n" "$command"
        exit 1
        ;;
    esac
}

destroy() {
    local command="$1"

    [ -z "$command" ] && command="cluster"

    case $command in
    cluster)
        manage_workers "destroy"
        manage_cluster "destroy"
        ;;
    workers)
        manage_workers "destroy"
        ;;
    *)
        printf "Unknown deploy sub command %s!\n" "$command"
        exit 1
        ;;
    esac
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

parse_manifests "$manifest_dir"
map_cluster_vars
map_worker_vars
map_hosts_vars

case "$COMMAND" in
# Parse options to the install sub command
deploy)
    SUB_COMMAND=$1
    shift
    deploy "$SUB_COMMAND"
    ;;
destroy)
    SUB_COMMAND=$1
    shift
    destroy "$SUB_COMMAND"
    ;;
pxeboot)
    HOST="$1"
    shift
    pxeboot "$HOST"
    ;;
*)
    echo "Unknown command: $COMMAND"
    usage "$out_dir"
    ;;
esac
