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
EOM
    exit 0
}

get_asset_raw() {
    local pxe="$1"
    local raw

    for file in "$MATCHBOX_DATA_DIR"/var/lib/matchbox/assets/*; do
        if [[ $pxe =~ "bios" ]] && [[ $file =~ ${RHCOS_METAL_IMAGES["bios"]} ]]; then
            raw="${file##*/}"
        elif [[ $pxe =~ "uefi" ]] && [[ $file =~ ${RHCOS_METAL_IMAGES["uefi"]} ]]; then
            raw="${file##*/}"
        fi
    done

    [[ -z $raw ]] && return 1 || echo "$raw"
}

get_asset_initramfs() {
    local initramfs
    for file in "$MATCHBOX_DATA_DIR"/var/lib/matchbox/assets/*; do
        if [[ $file =~ rhcos-$OPENSHIFT_RHCOS_MINOR_REL-installer-initramfs.*.img ]]; then
            initramfs="${file##*/}"
        fi
    done

    [[ -z $initramfs ]] && return 1 || echo "$initramfs"
}

get_asset_kernel() {
    local kernel

    for file in "$MATCHBOX_DATA_DIR"/var/lib/matchbox/assets/*; do
        if [[ $file =~ rhcos-$OPENSHIFT_RHCOS_MINOR_REL-installer-kernel ]]; then
            kernel="${file##*/}"
        fi
    done

    [[ -z $kernel ]] && return 1 || echo "$kernel"
}

gen_terraform_cluster() {
    local out_dir="$1"

    local ofile="$out_dir/cluster/terraform.tfvars"

    # Patches
    pxe=$(get_host_var "master-0" pxe) || pxe="bios"
    if ! raw=$(get_asset_raw "$pxe"); then
        printf "Could not find raw image file in assets!\n"
        exit 1
    fi

    CLUSTER_FINAL_VALS["pxe_os_image_url"]="$PROV_IP_MATCHBOX_HTTP_URL/assets/$raw"

    if ! initrd=$(get_asset_initramfs); then
        printf "Could not find initrd image file in assets!\n"
        exit 1
    fi
    CLUSTER_FINAL_VALS["pxe_initrd_url"]="assets/$initrd"

    if ! kernel=$(get_asset_kernel); then
        printf "Could not find kernel image file in assets!\n"
        exit 1
    fi
    CLUSTER_FINAL_VALS["pxe_kernel_url"]="assets/$kernel"

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

    # Number of masters called for...
    num_masters="${HOSTS_FINAL_VALS[master_count]}"

    mapfile -t sorted < <(printf '%s\n' "${!HOSTS_FINAL_VALS[@]}" | sort)

    IFS= host_list=$(for key in "${sorted[@]}"; do printf "%s=%s\n\n" "$key" "${HOSTS_FINAL_VALS[$key]}"; done)

    mapfile -t masters < <(echo "$host_list" | sed -nre 's/^hosts.([0-9]+).role=master$/\1/p')

    {
        for ((i = 0; i < num_masters; i++)); do
            host_index=${masters[$i]}
            host="hosts.$host_index"

            if [[ -z ${HOSTS_FINAL_VALS[$host.name]} ]]; then
                printf "Error: platform.hosts[%s] missing .name in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            public_ipv4=$(get_master_bm_ip $i)
            if [[ -n ${HOSTS_FINAL_VALS[$host.sdnIPAddress]} ]]; then
                public_ipv4=${HOSTS_FINAL_VALS[$host.sdnIPAddress]}
            fi

            if [[ -z ${HOSTS_FINAL_VALS[$host.bmc.address]} ]]; then
                printf "Error: platform.hosts[%s] missing .bmc.address in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            if [[ -z ${HOSTS_FINAL_VALS[$host.bmc.user]} ]]; then
                printf "Error: platform.hosts[%s] missing .bmc.user in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            if [[ -z ${HOSTS_FINAL_VALS[$host.bmc.password]} ]]; then
                printf "Error: platform.hosts[%s] missing .bmc.password in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            if [[ -z ${HOSTS_FINAL_VALS[$host.bootMACAddress]} ]]; then
                printf "Error: platform.hosts[%s] missing .bootMACAddress in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            install_dev="sda"
            if [[ -n ${HOSTS_FINAL_VALS[$host.install_dev]} ]]; then
                install_dev=${HOSTS_FINAL_VALS[$host.install_dev]}
            fi

            provisioning_interface="${CLUSTER_FINAL_VALS[master_provisioning_interface]}"
            if [[ -n ${HOSTS_FINAL_VALS[$host.provisioning_interface]} ]]; then
                provisioning_interface=${HOSTS_FINAL_VALS[$host.provisioning_interface]}
            fi

            baremetal_interface="${CLUSTER_FINAL_VALS[master_baremetal_interface]}"
            if [[ -n ${HOSTS_FINAL_VALS[$host.baremetal_interface]} ]]; then
                baremetal_interface=${HOSTS_FINAL_VALS[$host.baremetal_interface]}
            fi

            printf "  {\n"
            printf "    name: \"%s-%s\",\n" "${CLUSTER_FINAL_VALS[cluster_id]}" "${HOSTS_FINAL_VALS[$host.name]}"
            printf "    baremetal_interface: \"%s\",\n" "$baremetal_interface"
            printf "    provisioning_interface: \"%s\",\n" "$provisioning_interface"
            printf "    public_ipv4: \"%s\",\n" "$public_ipv4"
            printf "    ipmi_host: \"%s\",\n" "${HOSTS_FINAL_VALS[$host.bmc.address]}"
            printf "    ipmi_user: \"%s\",\n" "${HOSTS_FINAL_VALS[$host.bmc.user]}"
            printf "    ipmi_pass: \"%s\",\n" "${HOSTS_FINAL_VALS[$host.bmc.password]}"
            printf "    mac_address: \"%s\",\n" "${HOSTS_FINAL_VALS[$host.bootMACAddress]}"
            printf "    install_dev: \"%s\",\n" "$install_dev"
            printf "  },\n"
        done

        printf "]\n"
    } >>"$ofile"

}

gen_rhcos() {
    local host="$1"

    local initramfs
    local kernel
    local raw
    local install_dev

    pxe=$(get_host_var "$host" pxe) || pxe="bios"

    for file in "$MATCHBOX_DATA_DIR"/var/lib/matchbox/assets/*; do
        if [[ $pxe =~ "bios" ]] && [[ $file =~ ${RHCOS_METAL_IMAGES["bios"]} ]]; then
            raw="${file##*/}"
        elif [[ $pxe =~ "uefi" ]] && [[ $file =~ ${RHCOS_METAL_IMAGES["uefi"]} ]]; then
            raw="${file##*/}"
        elif [[ $file =~ rhcos-$OPENSHIFT_RHCOS_MINOR_REL-installer-initramfs.*.img ]]; then
            initramfs="${file##*/}"
        elif [[ $file =~ rhcos-$OPENSHIFT_RHCOS_MINOR_REL-installer-kernel ]]; then
            kernel="${file##*/}"
        fi
    done

    printf "    os_profile: \"rhcos\",\n"
    printf "    pxe_os_image_url: \"%s\",\n" "$PROV_IP_MATCHBOX_HTTP_URL/assets/$raw"
    printf "    initrd: \"assets/%s\",\n" "$initramfs"
    printf "    kernel: \"assets/%s\",\n" "$kernel"

    install_dev=$(get_host_var "$host" install_dev) || install_dev="sda"
    printf "    install_dev: \"%s\",\n" "$install_dev"
}

gen_centos() {
    local host="$1"

    printf "    os_profile: \"centos\",\n"

    initrd=$(get_host_var "$host" osProfile.initrd) || initrd="assets/centos7/images/pxeboot/initrd.img"
    printf "    initrd: \"%s\",\n" "$initrd"

    kernel=$(get_host_var "$host" osProfile.kernel) || kernel="assets/centos7/images/pxeboot/vmlinuz"
    printf "    kernel: \"%s\",\n" "$kernel"

    kickstart=$(get_host_var "$host" osProfile.kickstart) || kickstart="$PROV_IP_MATCHBOX_HTTP_URL/assets/centos-worker-kickstart.cfg"
    printf "    kickstart: \"%s\",\n" "$kickstart"
}

gen_centos8() {
    local host="$1"

    printf "    os_profile: \"centos8\",\n"

    initrd=$(get_host_var "$host" osProfile.initrd) || initrd="assets/centos8/images/pxeboot/initrd.img"
    printf "    initrd: \"%s\",\n" "$initrd"

    kernel=$(get_host_var "$host" osProfile.kernel) || kernel="assets/centos8/images/pxeboot/vmlinuz"
    printf "    kernel: \"%s\",\n" "$kernel"

    kickstart=$(get_host_var "$host" osProfile.kickstart) || kickstart="$PROV_IP_MATCHBOX_HTTP_URL/assets/centos8-worker-kickstart.cfg"
    printf "    kickstart: \"%s\",\n" "$kickstart"
}

gen_rhel() {
    local host="$1"

    printf "    os_profile: \"rhel\",\n"

    initrd=$(get_host_var "$host" osProfile.initrd) || initrd="assets/rhel8/images/pxeboot/initrd.img"
    printf "    initrd: \"%s\",\n" "$initrd"

    kernel=$(get_host_var "$host" osProfile.kernel) || kernel="assets/rhel8/images/pxeboot/initrd.img"
    printf "    kernel: \"%s\",\n" "$kernel"

    kickstart=$(get_host_var "$host" osProfile.kickstart) || kickstart="$PROV_IP_MATCHBOX_HTTP_URL/assets/rhel8-worker-kickstart.cfg"
    printf "    kickstart: \"%s\",\n" "$kickstart"
}

gen_terraform_workers() {
    local out_dir="$1"

    local ofile="$out_dir/workers/terraform.tfvars"

    mapfile -t sorted < <(printf '%s\n' "${!WORKER_MAP[@]}" | sort)

    printf "Generating...%s\n" "$ofile"

    {
        printf "// AUTOMATICALLY GENERATED -- Do not edit\n"

        for key in "${sorted[@]}"; do
            if [[ ! ${NO_TERRAFORM_MAP[$key]} ]]; then
                printf "%s = \"%s\"\n" "$key" "${WORKERS_FINAL_VALS[$key]}"
            fi
        done
        printf "worker_nodes = [\n"
    } >"$ofile"

    mapfile -t sorted < <(printf '%s\n' "${!HOSTS_FINAL_VALS[@]}" | sort)

    IFS= host_list=$(for key in "${sorted[@]}"; do printf "%s=%s\n\n" "$key" "${HOSTS_FINAL_VALS[$key]}"; done)

    mapfile -t workers < <(echo "$host_list" | sed -nre 's/^hosts.([0-9]+).role=worker$/\1/p')
    IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
    {
        for worker in "${workers[@]}"; do
            index=${worker##*-}
            host="hosts.$host_index"

            if ! test_host_var "$worker" "name"; then
                printf "Error: platform.hosts[%s] missing .name in install-config.yaml!\n" "$worker" 1>&2
                exit 1
            fi

            public_ipv4=$(get_host_var "$worker" sdnIPAddress) || public_ipv4=$(get_worker_bm_ip "$index")

            if ! test_host_var "$worker" "bmc.address"; then
                printf "Error: platform.hosts[%s] missing .bmc.address in install-config.yaml!\n" "$worker" 1>&2
                exit 1
            fi

            if ! test_host_var "$worker" "bmc.user"; then
                printf "Error: platform.hosts[%s] missing .bmc.user in install-config.yaml!\n" "$worker" 1>&2
                exit 1
            fi

            if ! test_host_var "$worker" "bmc.password"; then
                printf "Error: platform.hosts[%s] missing .bmc.password in install-config.yaml!\n" "$worker" 1>&2
                exit 1
            fi

            if ! test_host_var "$worker" "bootMACAddress"; then
                printf "Error: platform.hosts[%s] missing .bootMACAddress in install-config.yaml!\n" "$host_index" 1>&2
                exit 1
            fi

            provisioning_interface="${WORKERS_FINAL_VALS[worker_provisioning_interface]}"
            if [[ -n ${HOSTS_FINAL_VALS[$host.provisioning_interface]} ]]; then
                provisioning_interface=${HOSTS_FINAL_VALS[$host.provisioning_interface]}
            fi

            baremetal_interface="${WORKERS_FINAL_VALS[worker_baremetal_interface]}"
            if [[ -n ${HOSTS_FINAL_VALS[$host.baremetal_interface]} ]]; then
                baremetal_interface=${HOSTS_FINAL_VALS[$host.baremetal_interface]}
            fi

            printf "  {\n"
            printf "    name: \"%s-%s\",\n" "${WORKERS_FINAL_VALS[cluster_id]}" "$(get_host_var "$worker" "name")"
            printf "    baremetal_interface: \"%s\",\n" "$baremetal_interface"
            printf "    provisioning_interface: \"%s\",\n" "$provisioning_interface"
            printf "    public_ipv4: \"%s\",\n" "$public_ipv4"
            printf "    ipmi_host: \"%s\",\n" "$(get_host_var "$worker" "bmc.address")"
            printf "    ipmi_user: \"%s\",\n" "$(get_host_var "$worker" "bmc.user")"
            printf "    ipmi_pass: \"%s\",\n" "$(get_host_var "$worker" "bmc.password")"
            printf "    mac_address: \"%s\",\n" "$(get_host_var "$worker" "bootMACAddress")"

            type=$(get_host_var "$worker" "osProfile.type") || type="rhcos"

            case $type in
            rhcos)
                gen_rhcos "$worker"
                ;;
            centos7)
                gen_centos "$worker"
                ;;
            centos8)
                gen_centos8 "$worker"
                ;;
            rhel)
                gen_rhel "$worker"
                ;;
            *)
                printf "Unknown osProfile.type=\"%s\" in platform.hosts[%s]!\n" "$type" "$worker" 1>&2
                exit 1
                ;;
            esac

            printf "  },\n"

        done

        printf "]\n"
    } >>"$ofile"

}

gen_cluster() {
    local tdir="$1"

    map_cluster_vars
    map_hosts_vars
    gen_terraform_cluster "$tdir"
}

gen_workers() {
    local tdir="$1"

    map_worker_vars
    map_hosts_vars
    gen_terraform_workers "$tdir"
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

while getopts ":hm:v" opt; do
    case ${opt} in
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

# shellcheck disable=SC1091
source "common.sh"
source "images_and_binaries.sh"

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

# get prep_host_setup.src file info
parse_prep_bm_host_src "$manifest_dir"

# shellcheck disable=SC1091
source "scripts/network_conf.sh"

parse_manifests "$manifest_dir"

command=$1
shift # Remove 'prov|bm' from the argument list
case "$command" in
# Parse options to the install sub command
all)
    gen_cluster "$TERRAFORM_DIR"
    gen_workers "$TERRAFORM_DIR"
    ;;
cluster)
    gen_cluster "$TERRAFORM_DIR"
    ;;
workers)
    gen_workers "$TERRAFORM_DIR"
    ;;
install)
    gen_install
    ;;
*)
    echo "Unknown command: $command"
    usage
    ;;
esac
