#!/bin/bash
# File to create a local registry to be used on disconnected deployments
source "common.sh"

REGISTRY_USERNAME=redhat
REGISTRY_PSSWD=redhat
REGISTRY_EMAIL=admin@redhat.com
REGISTRY_HOSTNAME=$HOSTNAME
REGISTRY_HOSTPORT=5000
AUTH=$(echo -n "$REGISTRY_USERNAME:$REGISTRY_PSSWD" | base64 -w0)
RELEASE_VERSION="4.3.0-x86_64"

# Data for OpenSSL certs
COUNTRY_CODE="US"
STATE="MA"
LOCALITY="Westford"
ORGANIZATION="Red Hat"
COMMON_NAME=$REGISTRY_HOSTNAME

export OCP_RELEASE=$RELEASE_VERSION
export LOCAL_REGISTRY="$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT"
export LOCAL_REPOSITORY=$REGISTRY_HOSTNAME
export PRODUCT_REPO='openshift-release-dev'
export LOCAL_SECRET_JSON='cluster/pull-secret.json'
export RELEASE_NAME="ocp-release"

rm -rf /opt/registry
mkdir -p /opt/registry/{auth,certs,data}

pushd /opt/registry/certs
openssl req -newkey rsa:4096 -nodes -subj "/C=$COUNTRY_CODE/ST=$STATE/L=$LOCALITY/O=$ORGANIZATION/CN=$COMMON_NAME" -sha256 -keyout domain.key -x509 -days 365 -out domain.crt
popd

htpasswd -bBc /opt/registry/auth/htpasswd $REGISTRY_USERNAME $REGISTRY_PSSWD

EXISTING_REGISTRY=$(podman ps -a | grep mirror-registry | awk '{print $1}')
if [[ -n $EXISTING_REGISTRY ]]
then
  podman stop $EXISTING_REGISTRY && podman rm $EXISTING_REGISTRY
fi

podman run --name mirror-registry -p $REGISTRY_HOSTPORT:5000 \
   -v /opt/registry/data:/var/lib/registry:z \
   -v /opt/registry/auth:/auth:z \
   -e "REGISTRY_AUTH=htpasswd" \
   -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
   -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
   -v /opt/registry/certs:/certs:z \
   -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
   -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
   -d docker.io/library/registry:2


if [[ $(systemctl is-active firewalld) = "active" ]];
then
  firewall-cmd --add-port=$REGISTRY_HOSTPORT/tcp --zone=internal --permanent
  firewall-cmd --add-port=$REGISTRY_HOSTPORT/tcp --zone=public   --permanent
  firewall-cmd --reload
fi

CRT=$(cat /opt/registry/certs/domain.crt)
rm -rf /etc/pki/ca-trust/source/anchors/domain.crt
cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
cp /opt/registry/certs/domain.crt /tmp/temp.crt
sed -i -e 's/^/  /' /tmp/temp.crt
update-ca-trust

# Check if registry is properly running

curl -u $REGISTRY_USERNAME:$REGISTRY_PSSWD -k https://$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/v2/_catalog
if [ $? -eq 0 ]; then
    echo OK
else
    echo FAIL
fi

PS_REGISTRY=$(cat << EOF
"$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT":{"auth":"$AUTH","email":"you@example.com"}
EOF
)
echo $PS_REGISTRY
PS_REGISTRY={$PS_REGISTRY}

cat cluster/install-config.yaml | yq -r .pullSecret > cluster/pull-secret.json.orig
cat cluster/pull-secret.json.orig | jq -c --argjson obj $PS_REGISTRY '.auths += $obj' > cluster/pull-secret.json

PS=$LOCAL_SECRET_JSON
sed -i -e "/^pullSecret*/c\pullSecret: $(echo \'$(cat $PS)\')" cluster/install-config.yaml

echo "Mirror images to the registry..."
oc adm -a ${LOCAL_SECRET_JSON} release mirror \
   --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
   --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
   --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}

echo "Extract the openshift-install binary from the local registry"
mkdir -p $PROJECT_DIR/requirements
oc adm -a ${LOCAL_SECRET_JSON} release extract --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"
mv openshift-install requirements/

MIRRORS=$(cat << EOF
imageContentSources:
- mirrors:
  - $REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/$LOCAL_REPOSITORY
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - $REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/$LOCAL_REPOSITORY
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
)

INSTALL_CONFIG_BACKUP=cluster/install-config.yaml.orig
if [ ! -f "$INSTALL_CONFIG_BACKUP" ]; then
    cp cluster/install-config.yaml cluster/install-config.yaml.orig
fi

if ! grep -q additionalTrustBundle cluster/install-config.yaml ; then
    echo "additionalTrustBundle: |" >> cluster/install-config.yaml
    cat /tmp/temp.crt >> cluster/install-config.yaml
    printf '%s\n' "$MIRRORS" >> cluster/install-config.yaml
fi
rm -rf /tmp/temp.crt
