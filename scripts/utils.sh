#!/bin/bash

# MANIFEST_VALS stores key / value pairs from the parsed manifest files
declare -A MANIFEST_VALS
export MANIFEST_VALS
# FINAL_VALS stores MANIFEST_VALS after mapping and manipulation
# FINAL_VALS is used to generate terraform files
declare -A CLUSTER_FINAL_VALS
export CLUSTER_FINAL_VALS

declare -A WORKERS_FINAL_VALS
export WORKERS_FINAL_VALS

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

#set -x

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/manifest_check.sh"

parse_manifests() {
    local manifest_dir=$1

    [[ "$VERBOSE" =~ true ]] && printf "Parsing manifest files in %s\n" "$manifest_dir"

    for file in "$manifest_dir"/*.yaml; do
        [[ "$VERBOSE" =~ true ]] && printf "Parsing %s\n" "$file"

        # Parse the yaml file using yq
        # The end result is an associative array, manifest_vars
        # The keys are the fields in the yaml file
        # and the values are the values in the yaml file
        # shellcheck disable=SC2016
        if ! values=$(yq 'paths(scalars) as $p | [ ( [ $p[] | tostring ] | join(".") ) , ( getpath($p) | tojson ) ] | join(" ")' "$file"); then
            printf "Error during parsing..."
            exit 1
        fi
        mapfile -t lines < <(echo "$values" | sed -e 's/^"//' -e 's/"$//' -e 's/\\"//g')
        unset manifest_vars
        declare -A manifest_vars
        for line in "${lines[@]}"; do
            # shellcheck disable=SC2206
            l=($line)
            # create the associative array
            manifest_vars[${l[0]}]=${l[1]}
            #echo "manifest_vars[${l[0]}] == ${l[1]}"
        done

        recognized=false

        name=""
        if [[ $file =~ install-config.yaml ]]; then
            # the install-config file is not really a manifest and
            # does not have a kind: tag.
            kind="install-config"
            name="install-config"
            recognized=true
        elif [[ ${manifest_vars[kind]} ]]; then
            # All the manifest types must have at least one entry
            # in MANIFEST_CHECK.  The entry can just be an optional
            # field.
            kind=${manifest_vars[kind]}
            name=${manifest_vars[metadata.name]}
        else
            printf "kind parameter missing OR of unrecognized type in file %s" "$file"
            exit 1
        fi

        [[ "$VERBOSE" =~ true ]] && printf "Kind: %s\n" "$kind"
        # Loop through all entries in MANIFEST_CHECK
        for v in "${!MANIFEST_CHECK[@]}"; do
            # Split the path (i.e. bootstrap.spec.hardwareProfile ) into array
            IFS='.' read -r -a split <<<"$v"
            # MANIFEST_CHECK has the kind as the first component
            # do we recognize this kind?
            if [[ ${split[0]} =~ $kind ]]; then
                recognized=true
                required=false
                # MANIFEST_CHECK has req/opt as second component
                [[ ${split[1]} =~ req ]] && required=true
                # Reform path removing kind.req/opt
                v_vars=$(join_by "." "${split[@]:2}")
                # Now check if there is a value for this MANIFEST_CHECK entry
                # in the parsed manifest
                if [[ ${manifest_vars[$v_vars]} ]]; then
                    if [[ ! "${manifest_vars[$v_vars]}" =~ ${MANIFEST_CHECK[$v]} ]]; then
                        printf "Invalid value for \"%s\" : \"%s\" does not match %s in %s\n" "$v" "${manifest_vars[$v_vars]}" "${MANIFEST_CHECK[$v]}" "$file"
                        exit 1
                    fi
                    # echo " ${manifest_vars[$v_vars]} ===== ${BASH_REMATCH[1]} === ${MANIFEST_CHECK[$v]}"
                    # The regex contains a capture group that retrieves the value to use
                    # from the field in the yaml file
                    # Update manifest_var with the captured value.
                    manifest_vars[$v_vars]="${BASH_REMATCH[1]}"
                elif [[ "$required" =~ true ]]; then
                    # There was no value found in the manifest and the value
                    # was required.
                    printf "Missing value, %s, in %s...\n" "$v" "$file"
                    exit 1
                fi
            fi
        done

        if [[ $recognized =~ false ]]; then
            printf "Warning... \"%s\" contains an unrecognized kind: \"%s\"\n" "$file" "$kind"
        fi

        # Finished the parse
        # Take all final values and place them in the MANIFEST_VALS
        # array for use by gen_terraform
        for v in "${!manifest_vars[@]}"; do
            # Make entries unique by prepending with manifest object name
            # Should have a uniqueness check here!
            val="$name.$v"
            if [[ ${MANIFEST_VALS[$val]} ]]; then
                printf "Duplicate Manifest value...\"%s\"\n" "$val"
                printf "This usually occurs when two manifests have the same metadata.name...\n"
                exit 1
            fi
            MANIFEST_VALS[$val]=${manifest_vars[$v]}
            [[ "$VERBOSE" =~ true ]] && printf "\tMANIFEST_VALS[%s] == \"%s\"\n" "$val" "${manifest_vars[$v]}"
        done
    done

    mapfile -t sorted < <(printf '%s\n' "${!MANIFEST_VALS[@]}" | sort)

    ofile="$BUILD_DIR/manifest_vals.sh"
    {
        printf "#!/bin/bash\n\n"
        printf "declare -A MANIFEST_VALS=(\n"

        for v in "${sorted[@]}"; do
            printf "  [%s]=\"%s\"\n" "$v" "${MANIFEST_VALS[$v]}"
        done

        printf ")\n"
        printf "export MANIFEST_VALS\n"
    } >"$ofile"

}

process_rule() {
    local rule="$1"
    local index="$2"
    local func="$3"
    local index_saved="$index"
    local rule_saved="$rule"

    # index = master-\\1.spec.bmc.user

    [[ "$VERBOSE" =~ true ]] && printf "Processing rule \"%s\"\n" "$rule"

    [[ $rule =~ ^\| ]] && optional=true || optional=false
    rule=${rule#|}
    # rule = %master-([012]+).spec.bmc.[credentialsName].stringdata.username@ (indirect)
    # rule = =master-([012]+).metadata.name=$BM_IP_NS (constant)
    [[ $rule =~ .*@$ ]] && base64=true || base64=false
    rule=${rule%@}
    # rule = %master-([012]+).spec.bmc.[credentialsName].stringdata.username
    [[ $rule =~ ^%.* ]] && lookup=true || lookup=false
    rule=${rule#%}
    # rule = master-([012]+).spec.bmc.[credentialsName].stringdata.username
    [[ $rule =~ ^=.* ]] && constant=true || constant=false
    rule=${rule#=}
    # rule  = master-([012]+).metadata.name=$BM_IP_NS (constant)
    # index = master-\\1.metadata.ns                  (constant)

    indirect=false
    if [[ $rule =~ ^(.*)\.\[([a-zA-Z_-]+)\]\.(.+) ]]; then
        indirect=true
        # This map rule contains an indirection [ ... ]
        # Capture the indirection...
        # index = master-\\1.spec.bmc.user
        # rule = master-([012]+).spec.bmc.[credentialsName].stringdata.username
        ref_field="${BASH_REMATCH[2]}"
        # ref_field = credentialsName
        rule="${BASH_REMATCH[1]}.$ref_field"
        # rule = master-([012]+).spec.bmc.credentialsName
        # rule = bootstrap.spec.bmc.credentialsName
        postfix="${BASH_REMATCH[3]}"
        # postfix = stringdata.username
    elif [ "$constant" = true ]; then
        if [[ ! $rule =~ =(.*)$ ]]; then
            printf "Invalid rule: %s\n" "$rule"
            exit 1
        fi
        value="${BASH_REMATCH[1]}"
        rule=${rule%=*}
        # A regular constant rule, i.e. ==FOO will be blank at this point
        # So just go ahead and set it.
        if [[ -z "$rule" ]]; then
            if [[ "$value" =~ ^\.\/ ]]; then
                # ASSume that this is meant to a path relative to the PROJECT_DIR
                # and expand to an absoute path
                # probably a bug
                value="$PROJECT_DIR${value#.}"
            fi
            $func "$index" "$value"
            #FINAL_VALS[$index]="$value"

            [[ "$VERBOSE" =~ true ]] && printf "\tFINAL_VALS[%s] = \"%s\"\n" "$index" "$value"

            return
        fi
    fi
    regex="/$rule/p"
    unset matches
    mapfile -t matches < <(printf "%s\n" "${!MANIFEST_VALS[@]}" | sed -nre "$regex")

    if [[ "$VERBOSE" =~ true ]]; then
        for m in "${matches[@]}"; do
            printf "\t\"%s\" matches \"%s\"\n" "$regex" "$m"
        done
    fi
    processed=false
    #start="$(date +%s%N)"
    # loop through all the manifest variables searching
    # for matches with the rule's index
    # if one is found process it.
    #    for v in "${!MANIFEST_VALS[@]}"; do
    for v in "${matches[@]}"; do
        # The $rule is used to match against every key in MANIFEST_VALS[@]
        # If there is a match, the pattern in $index is updated
        # For fixed entries like "bootstrap_memory_gb", nothing is changed
        # or for non-constant master-\\1.metadata.name => master-0.metadata.name
        regex="s/$rule/$index/p"
        if ! r=$(echo "$v" | sed -nre "$regex"); then
            printf "Error processing %s\n" "$rule"
            exit 1
        fi
        # Did we find a match?
        if [ -n "$r" ]; then

            [[ "$VERBOSE" =~ true ]] && printf "\tIndex -- Map \"%s\" -> \"%s\"\n" "$index" "$r"

            # Make sure there is a value for this key
            if [[ ! ${MANIFEST_VALS[$v]} ]]; then
                printf "Key with no value for key \"%s\" failed...\n" "$v"
                exit 1
            fi

            if [ "$indirect" = true ]; then
                field="${MANIFEST_VALS[$v]}"
                # field = ha-lab-impi-creds
                field="$field.$postfix"
                # field = ha-lab-impi-creds.stringdata.username
                if [[ ! ${MANIFEST_VALS[$field]} ]]; then
                    printf "Indirect ref \"%s\" in rule \"%s\" failed...\n" "$field" "$rule"
                    exit 1
                fi
                if [[ "$base64" == true ]]; then
                    mapped_val=$(echo "${MANIFEST_VALS[$field]}" | base64 -d)
                else
                    mapped_val="${MANIFEST_VALS[$field]}"
                fi
            elif [ "$lookup" = true ]; then
                if [[ "$base64" == true ]]; then
                    mapped_val=$(echo "${MANIFEST_VALS[$v]}" | base64 -d)
                else
                    mapped_val="${MANIFEST_VALS[$v]}"
                fi
            elif [ "$constant" = true ]; then
                if [[ "$value" =~ ^\.\/ ]]; then
                    # might be a path relative to the PROJECT_DIR
                    # if so, expand to an absoute path
                    value="$PROJECT_DIR${value#.}"
                fi
                mapped_val="$value"
            fi

            $func "$r" "$mapped_val"
            #FINAL_VALS[$r]="$mapped_val"

            processed=true
            [[ "$VERBOSE" =~ true ]] && printf "\tFINAL_VALS[%s] = \"%s\"\n" "$r" "$mapped_val"

        fi
    done

    if [[ "$processed" =~ false ]] && [[ "$optional" =~ false ]]; then
        printf "Unable to process rule \"%s\" : \"%s\"\n" "$index_saved" "$rule_saved"

        exit 1
    fi
    #end="$(date +%s%N)"
    #printf "Execution time was %'d ns\n" "$(( "$end" - "$start" ))"
}

set_cluster_vars() {
    local key="$1"
    local value="$2"

    CLUSTER_FINAL_VALS[$key]="$value"
}

map_cluster_vars() {

    [[ "$VERBOSE" =~ true ]] && printf "Mapping cluster vars...\n"

    # shellcheck disable=SC1091
    source scripts/cluster_map.sh

    # Generate the cluster terraform values for the fixed
    # variables
    #
    local v

    for v in "${!CLUSTER_MAP[@]}"; do
        rule=${CLUSTER_MAP[$v]}

        process_rule "$rule" "$v" set_cluster_vars
    done

    # Generate the cluster terraform values for the master nodes
    #
    for v in "${!CLUSTER_MASTER_MAP[@]}"; do
        rule=${CLUSTER_MASTER_MAP[$v]}

        process_rule "$rule" "$v" set_cluster_vars
    done

    mapfile -t sorted < <(printf '%s\n' "${!CLUSTER_FINAL_VALS[@]}" | sort)

    ofile="$BUILD_DIR/cluster_vals.sh"

    {
        printf "#!/bin/bash\n\n"

        printf "declare -A CLUSTER_FINAL_VALS=(\n"

        for v in "${sorted[@]}"; do
            printf "  [%s]=\"%s\"\n" "$v" "${CLUSTER_FINAL_VALS[$v]}"
        done

        printf ")\n"
        printf "export CLUSTER_FINAL_VALS\n"
    } >"$ofile"
}

set_workers_vars() {
    local key="$1"
    local value="$2"

    WORKERS_FINAL_VALS[$key]="$value"
}

map_worker_vars() {
    [[ "$VERBOSE" =~ true ]] && printf "Mapping worker vars...\n"

    # shellcheck disable=SC1091
    source scripts/cluster_map.sh

    # The keys in the following associative array
    # specify varies to be emitted in the terraform vars file.
    # the associated value contains
    #  1. A static string value
    #  2. A string with ENV vars that have been previously defined
    #  3. A string prepended with '%' to indicate the final value is
    #     located in the MANIFEST_VALS array
    #  4. MANIFEST_VALS references may contain path.[field].field
    #     i.e. bootstrap.spec.bmc.[credentialsName].password
    #     in this instance [name].field references another manifest file
    #  5. If a rule ends with an '@', the field will be base64 decoded
    #

    # Generate the cluster terraform values for the fixed
    # variables
    #
    local v

    for v in "${!WORKER_MAP[@]}"; do
        rule=${WORKER_MAP[$v]}

        process_rule "$rule" "$v" set_workers_vars
    done

    # Generate the cluster terraform values for the master nodes
    #
    for v in "${!CLUSTER_WORKER_MAP[@]}"; do
        rule=${CLUSTER_WORKER_MAP[$v]}

        process_rule "$rule" "$v" set_workers_vars
    done

    mapfile -t sorted < <(printf '%s\n' "${!WORKERS_FINAL_VALS[@]}" | sort)

    ofile="$BUILD_DIR/workers_vals.sh"
    {
        printf "#!/bin/bash\n\n"

        printf "declare -A WORKERS_FINAL_VALS=(\n"

        for v in "${sorted[@]}"; do
            printf "  [%s]=\"%s\"\n" "$v" "${WORKERS_FINAL_VALS[$v]}"
        done

        printf ")\n"
        printf "export WORKERS_FINAL_VALS\n"
    } >"$ofile"
}

check_var() {

    if [ "$#" -ne 2 ]; then
        echo "${FUNCNAME[0]} requires 2 arguements, varname and config_file...($(caller))"
        exit 1
    fi

    local varname=$1
    local config_file=$2

    if [ -z "${!varname}" ]; then
        echo "$varname not set in ${config_file}, must define $varname"
        exit 1
    fi
}

check_regular_file_exists() {
    cfile="$1"

    if [ ! -f "$cfile" ]; then
        echo "file does not exist: $cfile"
        exit 1
    fi
}

check_directory_exists() {
    dir="$1"

    if [ ! -d "$dir" ]; then
        echo "directory does not exist: $dir"
        exit 1
    fi
}

join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

#
# The prep_bm_host.src file contains information
# about the provisioning interface, baremetal interface
# and external (internet facing) interface of the
# provisioning host
#
parse_prep_bm_host_src() {
    prep_src="$1"

    [[ "$VERBOSE" =~ true ]] && printf "Processing prep_host vars in %s\n" "$prep_src"

    check_regular_file_exists "$prep_src"

    # shellcheck source=/dev/null
    source "$prep_src"

    if [ -z "${PROV_INTF}" ]; then
        echo "PROV_INTF not set in ${prep_src}, must define PROV_INTF"
        exit 1
    fi

    if [ -z "${PROV_BRIDGE}" ]; then
        PROV_BRIDGE="provisioning"
        export PROV_BRIDGE
    fi

    if [ -z "${BM_INTF}" ]; then
        echo "BM_INTF not set in ${prep_src}, must define BM_INTF"
        exit 1
    fi

    if [ -z "${BM_BRIDGE}" ]; then
        BM_BRIDGE="baremetal"
        export BM_BRIDGE
    fi

    if [[ "$VERBOSE" =~ true ]]; then

        printf "\tPROV_IP_CIDR = \"%s\"\n" "$PROV_IP_CIDR"
        printf "\tBM_IP_CIDR = \"%s\"\n" "$BM_IP_CIDR"
        printf "\tPROV_INTF = \"%s\"\n" "$PROV_INTF"
        printf "\tPROV_BRIDGE = \"%s\"\n" "$PROV_BRIDGE"
        printf "\tBM_INTF = \"%s\"\n" "$BM_INTF"
        printf "\tBM_BRIDGE = \"%s\"\n" "$BM_BRIDGE"
    fi

    # PROV_IP_CIDR has a default value defined in scripts/network_conf.sh
    # BM_IP_CIDR has a default value defined in scripts/network_conf.sh
}

podman_exists() {
    local name="$1"

    (set -o pipefail && sudo podman ps --all | grep "$name" >/dev/null)
}

podman_stop() {
    local name="$1"

    sudo podman stop "$name" >/dev/null
}

podman_rm() {
    local name="$1"

    sudo podman stop "$name" >/dev/null &&
        sudo podman rm "$name" >/dev/null
}

podman_isrunning() {
    local name="$1"

    run_status=$(set -o pipefail && sudo podman inspect "$name" 2>/dev/null | jq .[0].State.Running) || return 1
    [[ "$run_status" =~ true ]] || return 1 # be explicit
}

podman_isrunning_logs() {
    local name="$1"

    podman_isrunning "$name" || (sudo podman logs "$name" && return 1)
}
