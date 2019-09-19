#!/bin/bash

parse_site_config() {
    local file="$1"

    # shellcheck disable=SC2016
    if ! values=$(yq 'paths(scalars) as $p | [ ( [ $p[] | tostring ] | join(".") ) , ( getpath($p) | tojson ) ] | join(" ")' "$file"); then
        printf "Error during parsing...%s\n" "$file"

        return 1
    fi

    mapfile -t lines < <(echo "$values" | sed -e 's/^"//' -e 's/"$//' -e 's/\\\\\\"/"/g' -e 's/\\"//g')

    declare -g -A SITE_CONFIG
    for line in "${lines[@]}"; do
        # create the associative array
        SITE_CONFIG[${line%% *}]=${line#* }
    done
}

declare -g -A SITE_CONFIG_MAP=(
    [HOST_PROV_INTF]="provisioningInfrastructure.hosts.defaultBootInterface"
    [HOST_BM_INTF]="provisioningInfrastructure.hosts.defaultSdnInterface"
    [PROV_INTF]="provisioningInfrastructure.provHost.interfaces.provisioning"
    [PROV_BRIDGE]="provisioningInfrastructure.provHost.bridges.provisioning"
    [BM_INTF]="provisioningInfrastructure.provHost.interfaces.baremetal"
    [BM_BRIDGE]="provisioningInfrastructure.provHost.bridges.baremetal"
    [EXT_INTF]="provisioningInfrastructure.provHost.interfaces.external"
    [PROV_IP_CIDR]="provisioningInfrastructure.network.provisioningIpCidr"
    [BM_IP_CIDR]="provisioningInfrastructure.network.baremetalIpCidr"
    [BM_INTF_IP]="provisioningInfrastructure.provHost.interfaces.baremetalIpAddress"
    [CLUSTER_DNS]="provisioningInfrastructure.network.dns.cluster"
    [CLUSTER_DEFAULT_GW]="provisioningInfrastructure.network.baremetalGWIP"
    [EXT_DNS1]="provisioningInfrastructure.network.dns.external1"
    [EXT_DNS2]="provisioningInfrastructure.network.dns.external2"
    [EXT_DNS3]="provisioningInfrastructure.network.dns.external3"
    [PROVIDE_DNS]="provisioningInfrastructure.provHost.services.clusterDNS"
    [PROVIDE_DHCP]="provisioningInfrastructure.provHost.services.baremetalDHCP"
    [PROVIDE_GW]="provisioningInfrastructure.provHost.services.baremetalGateway"
)

map_site_config() {
    status="$1"
    for var in "${!SITE_CONFIG_MAP[@]}"; do
        read -r "${var?}" <<<"${SITE_CONFIG[${SITE_CONFIG_MAP[$var]}]}"
    done

    printf "\nChecking parameters...\n\n"

    error=false
    for i in HOST_PROV_INTF HOST_BM_INTF PROV_INTF PROV_BRIDGE BM_INTF BM_BRIDGE EXT_INTF PROV_IP_CIDR BM_IP_CIDR BM_INTF_IP CLUSTER_DNS CLUSTER_DEFAULT_GW EXT_DNS1; do
        if [[ -z "${!i}" ]]; then
            printf "Error: %s is unset in %s, must be set\n\n" "${SITE_CONFIG_MAP[$i]}" "./cluster/site-config.yaml"
            error=true
        else
            v=${SITE_CONFIG_MAP[$i]}
            [[ $status =~ true ]] && printf "%s: %s\n" "${v//./\/}" "${!i}"
        fi
    done

    [[ $error =~ false ]] && return 0 || return 1
}

print_site_config() {
    for var in "${!SITE_CONFIG_MAP[@]}"; do
        printf "[%s]=\"%s\"\n" "$var" "${SITE_CONFIG[${SITE_CONFIG_MAP[$var]}]}"
    done
}

store_site_config() {

    mapfile -t sorted < <(printf '%s\n' "${!SITE_CONFIG[@]}" | sort)

    ofile="$BUILD_DIR/site_vals.sh"
    {
        printf "#!/bin/bash\n\n"

        for v in "${sorted[@]}"; do
             printf "MANIFEST_VALS[%s]=\'%s\'\n" "$v" "${SITE_CONFIG[$v]}"
        done

    } >"$ofile"
}