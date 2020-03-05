
# File to create a local registry to be used on disconnected deployments
source "common.sh"

REGISTRY_USERNAME=redhat
REGISTRY_PSSWD=redhat
REGISTRY_HOSTNAME=myHostname
REGISTRY_HOSTPORT=myPort
AUTH=$(echo -n "$REGISTRY_USERNAME:REGISTRY_PSSWD$" | base64 -w0)
RELEASE_VERSION="4.3.0-x86_64."

# Data for OpenSSL certs
COUNTRY_CODE="US"
STATE="MA"
LOCALITY="Westford"
ORGANIZATION="Red Hat"
COMMON_NAME=$REGISTRY_HOSTNAME

export OCP_RELEASE=$RELEASE_VERSION
export LOCAL_REGISTRY="$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT" 
export LOCAL_REPOSITORY='<repository_name>' 
export PRODUCT_REPO='openshift-release-dev' 
export LOCAL_SECRET_JSON='<path_to_pull_secret>' 
export RELEASE_NAME="ocp-release" 


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

podman run --name mirror-registry -p <local_registry_host_port>:5000 \
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

firewall-cmd --add-port=$REGISTRY_HOSTPORT/tcp --zone=internal --permanent 
firewall-cmd --add-port=$REGISTRY_HOSTPORT/tcp --zone=public   --permanent 
firewall-cmd --reload

CRT=$(cat /opt/registry/certs/domain.crt)
cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust

# Check if registry is properly running

curl -u $REGISTRY_USERNAME:$REGISTRY_PSSWD -k https://$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/v2/_catalog
if [ $? -eq 0 ]; then
    echo OK
else
    echo FAIL
fi

echo "######################################################"
echo "    Add the following section to your pull secret"
echo "######################################################"
cat << EOF
 "$REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT":{"auth":"$AUTH","email":"you@example.com"}
EOF

echo "Mirror images to the registry..."
oc adm -a ${LOCAL_SECRET_JSON} release mirror \
   --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
   --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
   --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}

echo "Extract the openshift-install binary from the local registry"
oc adm -a ${LOCAL_SECRET_JSON} release extract --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"


cat << EOF
additionalTrustBundle: | 
$(for i in $CRT;do echo "  $i";done) 
imageContentSources: 
- mirrors:
  - $REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/$LOCAL_REPOSITORY/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - $REGISTRY_HOSTNAME:$REGISTRY_HOSTPORT/$LOCAL_REPOSITORY/release
  source: registry.svc.ci.openshift.org/ocp/release
EOF
