#!/bin/bash

declare -A image_types=(
    [kernel]=true
    [initramfs]=true
    [metal]=true
)

usage() {
    cat <<-EOM
    Retrieve and display information about OpenShift and RHCOS releases

    Usage:
        $(basename "$0") [-h] [-m manfifest_dir] [-o out_dir] latest|all major_version
            major_version - Major OpenShift version.  i.e. 4.1, 4.2, 4.3 or 4.4

            latest   - Retrieve and print information about the latest release
            db       - Generate db file for Coredns
            start    - Start the coredns container 
            stop     - Stop the coredns container
            remove   - Stop and remove the coredns container
            restart  - Restart coredns to reload config files

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/coredns/...]
EOM
    exit 0
}

get_latest_build_url() {

    major="$1"

    if [[ ! $major =~ (4.1|4.2|4.3|4.4) ]]; then
        printf "Invalid major release given: %s\n" "$major"

        return 1
    fi

    release_url="https://releases-art-rhcos.svc.ci.openshift.org/art/storage/releases/rhcos-$major"

    builds=$(curl -k -sS "$release_url/builds.json")
    newest=$(jq '.builds[0] | if type=="object" then .id + "/" + .arches[0] else . end' <<<"$builds")
    newest="${newest//\"/}"

    echo "$release_url/$newest/meta.json"
}

latest_url=$(get_latest_build_url "$1") || exit 1

meta_json="$(curl -sS "$latest_url")"

image_json=$(jq '.images' <<<"$meta_json")

for image in $(jq 'keys[]' <<<"$image_json"); do
  if [[ $image =~ initramfs|kernel|metal ]]; then
     path=$(jq ".$image.path" <<<"$image_json")
     printf "Image %s, path %s\n" "$image" "$path"
  fi
done

buildid=$(jq '.buildid' <<<"$meta_json")

printf "Build ID: %s\n" "$buildid"

jq '.images[].path' <<< "$meta_json"