#!/bin/bash

# This script generates configuration files for the UPI install project.
# The first set of scripts are related to dns and haproxy.  The second
# set of files are for terraform
#
# The UPI install project employs two instances of dnsmasq.  One instance provides
# dhcp/pxe boot for the provisioning network.  The second instance provides dhcp
# and DNS for the baremetal network.  Dnsmasq is run as a container using podman.
# The configuration files for both dnsmasqs are located as should below.
#
#── /root_path/
#|
#├── dnsmasq
#│   ├── bm
#│   │   ├── etc
#│   │   │   └── dnsmasq.d
#│   │   │       ├── dnsmasq.conf
#│   │   │       └── dnsmasq.hostsfile
#│   │   └── var
#│   │       └── run
#│   │           ├── dnsmasq.leasefile
#│   │           └── dnsmasq.log
#│   └── prov
#│       ├── etc
#│       │   └── dnsmasq.conf
#│       └── var
#│           └── run
#│               ├── dnsmasq.leasefile
#│               └── dnsmasq.log
#|
#├── terraform
#|   ├── cluster
#|   │   └── terraform.tfvars
#|   └── workers
#|       └── terraform.tfvars
#|
#├── cluster
#│   ├── bootstrap-creds.yaml
#│   ├── bootstrap.yaml
#│   ├── ha-lab-ipmi-creds.yaml
#│   ├── install-config.yaml
#│   ├── master-0.yaml
#│   ├── prep_bm_host.src
#│   ├── worker-0.yaml
#│   └── worker-1.yaml

#
# This script requires a /root_path/ argument in order to set the proper locations
# in the generated config files.  For the provisioning network, only the dnsmasq.conf
# is generated.  The dnsmasq.leasefile and dnsmasq.logfile are created when dnsmasq
# is started.  For the the baremetal network, dnsmasq.conf and dnsmasq.hostsfiles are
# generated.
#
# The script also requires a path to one or three MASTER manifest files.
# The name: attribute should be master-0[, master-1, master-2].
#
# An example manifest file is show below.
#
# apiVersion: metalkube.org/v1alpha1
#
# kind: BareMetalHost
# metadata:
#   name: master-0
# spec:
#   externallyProvisioned: true
#   online: true # Must be set to true for provisioing
#   hardwareProfile: ""
#   bmc:
#     address: ipmi://10.19.110.16
#     credentialsName: ha-lab-ipmi-secret
#   bootMACAddress: 0c:c4:7a:8e:ee:0c

CLUSTER_DIR=cluster
CLUSTER_TFVARS="$CLUSTER_DIR/terraform.tfvars"
WORKER_DIR=workers
WORKER_TFVARS="$WORKER_DIR/terraform.tfvars"

usage() {
    cat <<EOM

     $(basename "$0") [common_options] cluster
        Generate cluster (master) config files for terraform

     $(basename "$0") [common_options] workers
        Generate worker config files for terraform

     $(basename "$0") [common_options] all
        Generate cluster and worker config files for terraform

    common_options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to ./cluster/
        -b base_dir -- Where to put the output [defaults to ./dnsmasq/...]
        -s [path/]prep_host_setup.src -- Location of the config file for host prep
            Default to ./prep_host_setup.src
        -t terraform_dir -- Location to place terraform output.  Defaults to ./terraform
EOM
    exit 0
}

gen_terraform_cluster() {
    local out_dir="$1"

    local cluster_dir="$out_dir/cluster"

    mkdir -p "$cluster_dir"

    local ofile="$cluster_dir/terraform.tfvars"

    mapfile -t sorted < <(printf '%s\n' "${!CLUSTER_MAP[@]}" | sort)

    printf "Generating...%s\n" "$ofile"

    {
        printf "// AUTOMATICALLY GENERATED -- Do not edit\n"

        for key in "${sorted[@]}"; do
            if [[ ! ${NO_TERRAFORM_MAP[$key]} ]]; then
                printf "%s = \"%s\"\n" "$key" "${CLUSTER_FINAL_VALS[$key]}"
            fi
        done

        printf "master_nodes = [\n"

    } >"$ofile"
    {
        num_masters="${CLUSTER_FINAL_VALS[master_count]}"
        for ((i = 0; i < num_masters; i++)); do
            m="master-$i"
            if [[ -z ${CLUSTER_FINAL_VALS[$m.metadata.name]} ]]; then
                printf "\n Missing manifest data for %s, %d masters(replicas) were specified in install-config.yaml\n" "$m" "$num_masters"
                exit 1
            fi
            printf "  {\n"
            printf "    name: \"%s-%s\",\n" "${CLUSTER_FINAL_VALS[cluster_id]}" "${CLUSTER_FINAL_VALS[$m.metadata.name]}"
            printf "    public_ipv4: \"%s\",\n" "$(get_master_bm_ip $i)"
            printf "    ipmi_host: \"%s\",\n" "${CLUSTER_FINAL_VALS[$m.spec.bmc.address]}"
            printf "    ipmi_user: \"%s\",\n" "${CLUSTER_FINAL_VALS[$m.spec.bmc.user]}"
            printf "    ipmi_pass: \"%s\",\n" "${CLUSTER_FINAL_VALS[$m.spec.bmc.password]}"
            printf "    mac_address: \"%s\",\n" "${CLUSTER_FINAL_VALS[$m.spec.bootMACAddress]}"
            printf "    install_dev: \"%s\",\n" "${CLUSTER_FINAL_VALS[$m.install_dev]}"

            printf "  },\n"
        done

        printf "]\n"
    } >>"$ofile"

}

gen_terraform_workers() {
    local out_dir="$1"

    local worker_dir="$out_dir/workers"

    mkdir -p "$worker_dir"

    local ofile="$worker_dir/terraform.tfvars"

    mapfile -t sorted < <(printf '%s\n' "${!WORKER_MAP[@]}" | sort)

    printf "Generating...%s\n" "$ofile"

    {
        printf "// AUTOMATICALLY GENERATED -- Do not edit\n"

        for key in "${sorted[@]}"; do
            printf "%s = \"%s\"\n" "$key" "${WORKERS_FINAL_VALS[$key]}"
        done
        printf "worker_nodes = [\n"
    } >"$ofile"

    {
        num_workers="${WORKERS_FINAL_VALS[worker_count]}"
        for ((i = 0; i < num_workers; i++)); do
            m="worker-$i"

            printf "  {\n"
            printf "    name: \"%s\",\n" "${WORKERS_FINAL_VALS[$m.metadata.name]}"
            printf "    public_ipv4: \"%s\",\n" "$(get_worker_bm_ip $i)"
            printf "    ipmi_host: \"%s\",\n" "${WORKERS_FINAL_VALS[$m.spec.bmc.address]}"
            printf "    ipmi_user: \"%s\",\n" "${WORKERS_FINAL_VALS[$m.spec.bmc.user]}"
            printf "    ipmi_pass: \"%s\",\n" "${WORKERS_FINAL_VALS[$m.spec.bmc.password]}"
            printf "    mac_address: \"%s\",\n" "${WORKERS_FINAL_VALS[$m.spec.bootMACAddress]}"
            printf "  },\n"

        done

        printf "]\n"
    } >>"$ofile"

}

gen_cluster() {
    local terraform_dir="$1"

    map_cluster_vars
    gen_terraform_cluster "$terraform_dir"
}

gen_workers() {
    local terraform_dir="$1"

    map_worker_vars
    gen_terraform_workers "$terraform_dir"

}

gen_install() {
    ###-------------------###
    ### Prepare terraform ###
    ###-------------------###

    printf "\nInstalling Terraform\n\n"

    (
        cd /tmp

        if [[ ! -f "/usr/bin/terraform" ]]; then
            curl -O "https://releases.hashicorp.com/terraform/0.12.2/terraform_0.12.2_linux_amd64.zip"
            unzip terraform_0.12.2_linux_amd64.zip
            sudo mv terraform /usr/bin/.
        fi

        if [[ ! -f "$HOME/.terraform.d/plugins/terraform-provider-matchbox" ]]; then
            git clone https://github.com/poseidon/terraform-provider-matchbox.git
            cd terraform-provider-matchbox
            go build
            mkdir -p "$HOME/.terraform.d/plugins"
            cp terraform-provider-matchbox "$HOME/.terraform.d/plugins/"
        fi
    ) || exit 1
}

if [ "$#" -lt 1 ]; then
    usage
fi

VERBOSE="false"
export VERBOSE

while getopts ":hm:t:v" opt; do
    case ${opt} in
    m)
        manifest_dir=$OPTARG
        ;;
    t)
        terraform_dir=$OPTARG
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

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1091
source "scripts/manifest_check.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

manifest_dir=${manifest_dir:-$MANIFEST_DIR}
check_directory_exists "$manifest_dir"
manifest_dir=$(realpath "$manifest_dir")

terraform_dir=${terraform_dir:-$TERRAFORM_DIR}
terraform_dir=$(realpath "$terraform_dir")

mkdir -p "$terraform_dir"

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir/prep_bm_host.src"

# shellcheck disable=SC1091
source "scripts/network_conf.sh"

parse_manifests "$manifest_dir"

command=$1
shift # Remove 'prov|bm' from the argument list
case "$command" in
# Parse options to the install sub command
all)
    gen_cluster "$terraform_dir"
    gen_workers "$terraform_dir"
    ;;
cluster)
    gen_cluster "$terraform_dir"
    ;;
workers)
    gen_workers "$terraform_dir"
    ;;
install)
    gen_install
    ;;
apply-cluster)
    cp "$out_dir/$CLUSTER_TFVARS" upi-rt/terraform/cluster
    (
        cd upi-rt/terraform/cluster || exit
        terraform apply --auto-approve
    )
    ;;
apply-workers)
    cp "$out_dir/$WORKER_TFVARS" upi-rt/terraform/workers
    (
        cd upi-rt/terraform/workers || exit
        terraform apply --auto-approve
    )
    ;;
*)
    echo "Unknown command: $command"
    usage
    ;;
esac
