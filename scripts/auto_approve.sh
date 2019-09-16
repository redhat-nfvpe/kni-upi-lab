shell: >
    count=0;
    for csr in `oc --config={{ openshift_node_kubeconfig_path }} get csr --no-headers \
      | grep " system:serviceaccount:openshift-machine-config-operator:node-bootstrapper " \
      | cut -d " " -f1`;
    do
      oc --config={{ openshift_node_kubeconfig_path }} describe csr/$csr \
        | grep " system:node:{{ hostvars[item].ansible_nodename | lower }}$";
      if [ $? -eq 0 ];
      then
        oc --config={{ openshift_node_kubeconfig_path }} adm certificate approve ${csr};
        if [ $? -eq 0 ];
        then
          count=$((count+1));
        fi;
      fi;
    done;
    exit $((!count));