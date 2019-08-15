manifests := cluster/*.yaml cluster/*.src

dnsmasq_dir = ./dnsmasq
terraform_dir = ./terraform
coredns_dir = ./coredns
haproxy_dir = ./haproxy
openshift_dir = ./ocp
matchbox_dir = ./matchbox
matchbox_data_dir = ./matchbox-data

dnsmasq_prov_conf := $(dnsmasq_dir)/prov/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_bm_conf := $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.conf
haproxy_conf := $(haproxy_dir)/haproxy.conf
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := $(coredns_dir)/Corefile
terraform := $(terraform_dir)/cluster/terraform.tfvars $(terraform_dir)/workers/terraform.tfvars 
ignitions := $(openshift_dir)/worker.ign $(openshift_dir)/master.ign
matchbox_git := $(matchbox_dir)/.git

all: dns_conf haproxy terraform matchbox matchbox_data

dns_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)

matchbox: $(manifests) ./scripts/gen_matchbox.sh
	./scripts/gen_matchbox.sh repo

matchbox_data: $(manifests) ./scripts/gen_matchbox.sh
	./scripts/gen_matchbox.sh data

.PHONY: dnsmasq
dnsmasq:  $(dnsmasq_prov_conf) $(dnsmasq_bm_conf)

$(dnsmasq_prov_conf): $(manifests) ./scripts/gen_config_prov.sh
	./scripts/gen_config_prov.sh

$(dnsmasq_bm_conf): $(manifests) ./scripts/gen_config_bm.sh
	./scripts/gen_config_bm.sh bm

.PHONY: haproxy
haproxy: $(haproxy_conf)

$(haproxy_conf): $(manifests) ./scripts/gen_haproxy.sh
	./scripts/gen_haproxy.sh build

.PHONY: coredns
coredns: $(coredns_conf)

$(coredns_conf): $(manifests) ./scripts/gen_coredns.sh
	./scripts/gen_coredns.sh

terraform: $(terraform)

$(terraform): $(manifests) ./scripts/cluster_map.sh ./scripts/network_conf.sh
	./gen_terraform.sh all


cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

ignition: $(ignitions) 
$(ignitions): $(manifests) ./scripts/gen_ignition.sh
	./scripts/gen_ignition.sh

clean:
	rm -f ./cluster/manifest_vals.sh ./cluster/final_worker_vals.sh ./cluster/final_cluster_vals.sh
	rm -rf $(coredns_dir) $(terraform_dir) $(dnsmasq_dir) $(haproxy_dir) $(openshift_dir) $(matchbox_dir) $(matchbox_data_dir)
