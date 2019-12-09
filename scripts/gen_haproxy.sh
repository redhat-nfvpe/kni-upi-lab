#!/bin/bash

HAPROXY_IMAGE_NAME="kni-haproxy"
HAPROXY_IMAGE_TAG="latest"

CONTAINER_NAME="kni-haproxy"
HAPROXY_KUBEAPI_PORT="6443"
HAPROXY_MCS_MAIN_PORT="22623"

set -o pipefail

usage() {
    cat <<-EOM
    Generate an haproxy config file

    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the baremetal interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
EOM
    exit 0
}

gen_config_haproxy() {
    local out_dir="$1"
    local cfg_file="$out_dir/haproxy.cfg"
    local cluster_id="${CLUSTER_FINAL_VALS[cluster_id]}"
    local num_workers="${HOSTS_FINAL_VALS[worker_count]}"

    mkdir -p "$out_dir"

    cat <<EOF >"$cfg_file"
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

frontend kubeapi
    mode tcp
    bind *:6443
    option tcplog
    default_backend kubeapi-main

frontend mcs
    bind *:22623
    default_backend mcs-main
    mode tcp
    option tcplog
EOF

if [ "$num_workers" -gt 0 ]; then
    cat <<EOF >> "$cfg_file"
frontend http
    bind *:80
    mode tcp
    default_backend http-main
    option tcplog

frontend https
    bind *:443
    mode tcp
    default_backend https-main
    option tcplog
EOF
fi

cat <<EOF >> "$cfg_file"
backend kubeapi-main
    balance source
    mode tcp
EOF
    master1_mac=$(get_host_var "master-1" "sdnMacAddress")
    master2_mac=$(get_host_var "master-2" "sdnMacAddress")

    {
        printf "    server %s %s:%s check\n" "$cluster_id-bootstrap" "$BM_IP_BOOTSTRAP" "$HAPROXY_KUBEAPI_PORT"
        printf "    server %s %s:%s check\n" "$cluster_id-master-0" "$(get_master_bm_ip 0)" "$HAPROXY_KUBEAPI_PORT"
        if [ -n "$master1_mac" ] && [ "${HOSTS_FINAL_VALS[master_count]}" -eq 3 ]; then
            printf "    server %s %s:%s check\n" "$cluster_id-master-1" "$(get_master_bm_ip 1)" "$HAPROXY_KUBEAPI_PORT"
        fi

        if [ -n "$master2_mac" ] && [ "${HOSTS_FINAL_VALS[master_count]}" -eq 3 ]; then
            printf "    server %s %s:%s check\n" "$cluster_id-master-2" "$(get_master_bm_ip 2)" "$HAPROXY_KUBEAPI_PORT"
        fi
        printf "\n"

        printf "backend mcs-main\n"
        printf "    balance source\n"
        printf "    mode tcp\n"

        printf "    server %s %s:%s check\n" "$cluster_id-bootstrap" "$BM_IP_BOOTSTRAP" "$HAPROXY_MCS_MAIN_PORT"
        printf "    server %s %s:%s check\n" "$cluster_id-master-0" "$(get_master_bm_ip 0)" "$HAPROXY_MCS_MAIN_PORT"

        if [ -n "$master1_mac" ] && [ "${HOSTS_FINAL_VALS[master_count]}" -eq 3 ]; then
            printf "    server %s %s:%s check\n" "$cluster_id-master-1" "$(get_master_bm_ip 1)" "$HAPROXY_MCS_MAIN_PORT"
        fi

        if [ -n "$master2_mac" ] && [ "${HOSTS_FINAL_VALS[master_count]}" -eq 3 ]; then
            printf "    server %s %s:%s check\n" "$cluster_id-master-2" "$(get_master_bm_ip 2)" "$HAPROXY_MCS_MAIN_PORT"
        fi
        printf "\n"

        num_workers="${HOSTS_FINAL_VALS[worker_count]}"

        if [ "$num_workers" -gt 0 ]; then
            printf "backend http-main\n"
            printf "    balance source\n"
            printf "    mode tcp\n"

            IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
            for worker in "${workers[@]}"; do
                index=${worker##*-}
                printf "    server %s-%s %s:%s check\n" "$cluster_id" "$worker" "$(get_worker_bm_ip "$index")" "80"
            done

            printf "\n"

            printf "backend https-main\n"
            printf "    balance source\n"
            printf "    mode tcp\n"

            IFS=' ' read -r -a workers <<<"${HOSTS_FINAL_VALS[worker_hosts]}"
            for worker in "${workers[@]}"; do
                index=${worker##*-}
                printf "    server %s-%s %s:%s check\n" "$cluster_id" "$worker" "$(get_worker_bm_ip "$index")" "443"
            done

            printf "\n"
        fi

    } >>"$cfg_file"

    echo "$cfg_file"
}

gen_build() {
    local out_dir="$1"
    local docker_file

    docker_file="$(realpath "$out_dir/Dockerfile")"

    mkdir -p "$out_dir"

    cat <<'EOF' >"$docker_file"
FROM haproxy:1.7
#COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg

ENV HAPROXY_USER haproxy

EXPOSE 80
EXPOSE 443
EXPOSE 6443
EXPOSE 22623

RUN groupadd --system ${HAPROXY_USER} && \
useradd --system --gid ${HAPROXY_USER} ${HAPROXY_USER} && \
mkdir --parents /var/lib/${HAPROXY_USER} && \
chown -R ${HAPROXY_USER}:${HAPROXY_USER} /var/lib/${HAPROXY_USER}

CMD ["haproxy", "-db", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
EOF
    echo "$docker_file"
}

build_haproxy() {
    local out_dir="$1"

    ofile=$(gen_config_haproxy "$out_dir")
    printf "Generated %s...\n" "$ofile"

    ofile=$(gen_build "$out_dir")
    printf "Generated %s...\n" "$ofile"
    printf "Building haproxy container...\n"
    if ! image_id=$(cd "$PROJECT_DIR"/haproxy && sudo podman build . 2>/dev/null | rev | cut -d ' ' -f 1 | rev | tail -1); then
        printf "Error while building haproxy container...\n"
        return 1
    fi
    printf "Tagging image %s with %s ...\n" "$image_id" "$HAPROXY_IMAGE_NAME:$HAPROXY_IMAGE_TAG"
    if ! sudo podman tag "$image_id" "$HAPROXY_IMAGE_NAME:$HAPROXY_IMAGE_TAG"; then
        printf "Failed to tag image_id %s!" "$image_id"
        return 1
    fi
    printf "%s\n" "$image_id" >"$HAPROXY_DIR/imageid"

    echo "$image_id"
}

VERBOSE="false"
export VERBOSE

while getopts ":ho:m:v" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
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
shift $((OPTIND - 1))

if [ "$#" -ne 1 ]; then
    usage
fi

COMMAND=$1
shift

# shellcheck disable=SC1091
source "common.sh"

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

out_dir=${out_dir:-$HAPROXY_DIR}
out_dir=$(realpath "$out_dir")

case "$COMMAND" in
build)
    gen_variables "$manifest_dir"
    build_haproxy "$out_dir"
    ;;
gen-config)
    gen_variables "$manifest_dir"
    ofile=$(gen_config_haproxy "$out_dir")
    printf "Generated %s...\n" "$ofile"
    ;;
start)
    if ! image_id=$(sudo podman images | grep $HAPROXY_IMAGE_NAME | awk '{print $3}'); then
        image_id=$(build_haproxy "$out_dir") || printf "Cannot build image \"%s\"" "$HAPROXY_IMAGE_NAME"
    fi

    podman_exists "$CONTAINER_NAME" &&
        (podman_rm "$CONTAINER_NAME" ||
            printf "Could not remove %s!\n" "$CONTAINER_NAME")

    if ! cid=$(sudo podman run -d --name "$CONTAINER_NAME" --net=host -p 80:80 \
        -v "$PROJECT_DIR/haproxy:/usr/local/etc/haproxy:Z" \
        -p 443:443 -p 6443:6443 -p 22623:22623 "$image_id" -f /usr/local/etc/haproxy/haproxy.cfg); then
        printf "Could not start haproxy container!"
        exit 1
    fi
    podman_isrunning_logs "$CONTAINER_NAME" && printf "Started %s as %s...\n" "$CONTAINER_NAME" "$cid"
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
