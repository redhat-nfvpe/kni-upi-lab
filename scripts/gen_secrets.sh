#!/bin/bash

# set -x
set -e

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/paths.sh"

PULL_SECRET=$(cat "$MANIFEST_DIR/pull-secret.json")
SSH_PUB_KEY=$(cat "$MANIFEST_DIR/id_rsa.pub")

cat - | sed \
    -e "s|PULL_SECRET|\'${PULL_SECRET}\'|" \
    -e "s|SSH_PUB_KEY|${SSH_PUB_KEY}|"