manifests := cluster/*.yaml cluster/*.src

dnsmasq_dir = ./dnsmasq
terraform_dir = ./terraform
coredns_dir = ./coredns
haproxy_dir = ./haproxy
openshift_dir = ./ocp
matchbox_dir = ./matchbox
matchbox_data_dir = ./matchbox-data
upi-rt_dir = ./upi-rt

dnsmasq_prov_conf := $(dnsmasq_dir)/prov/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_bm_conf := $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.conf
haproxy_conf := $(haproxy_dir)/haproxy.cfg
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := $(coredns_dir)/Corefile
terraform_cluster := $(terraform_dir)/cluster/terraform.tfvars
ignitions := $(openshift_dir)/worker.ign $(openshift_dir)/master.ign
matchbox_git := $(matchbox_dir)/.git
upi-rt_git := $(upi-rt_dir)/.git
matchbox-data-files := $(matchbox_data_dir)/etc/matchbox/ca.cert

terraform-bin := /usr/bin/terraform
openshift-bin := /usr/local/bin/openshift-install
openshift-oc := /usr/local/bin/oc

all: dns_conf haproxy terraform matchbox matchbox_data upi-rt


dns_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)

.PHONY: upi-rt
upi-rt: $(upi-rt_git)

$(upi-rt_git):
	git clone https://github.com/redhat-nfvpe/upi-rt.git

matchbox: $(manifests) ./scripts/gen_matchbox.sh
	./scripts/gen_matchbox.sh repo

matchbox-data: $(matchbox-data-files)

$(matchbox-data-files): $(manifests) ./scripts/gen_matchbox.sh matchbox
	./scripts/gen_matchbox.sh data

.PHONY: dnsmasq
dnsmasq:  $(dnsmasq_prov_conf) $(dnsmasq_bm_conf)

$(dnsmasq_prov_conf): $(manifests) ./scripts/gen_config_prov.sh
	./scripts/gen_config_prov.sh

$(dnsmasq_bm_conf): $(manifests) ./scripts/gen_config_bm.sh
	./scripts/gen_config_bm.sh bm

haproxy: $(haproxy_conf)

$(haproxy_conf): $(manifests) ./scripts/gen_haproxy.sh
	./scripts/gen_haproxy.sh gen-config

.PHONY: coredns
coredns: $(coredns_conf)

$(coredns_conf): $(manifests) ./scripts/gen_coredns.sh
	./scripts/gen_coredns.sh

openshift-install: $(openshift-bin)
openshift-oc: $(openshift-oc)

$(openshift-oc):
	./scripts/gen_ignition.sh oc

$(openshift-bin):
	./scripts/gen_ignition.sh installer

terraform: $(terraform-bin)

$(terraform-bin):
	./scripts/gen_terraform.sh install

$(terraform_cluster): $(manifests) ./scripts/cluster_map.sh ./scripts/network_conf.sh $(ignition)
	./scripts/gen_terraform.sh all

cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

ignition: $(ignitions) 

$(ignitions): $(manifests) ./scripts/gen_ignition.sh openshift-install
	./scripts/gen_ignition.sh

clean:
	rm -f ./cluster/manifest_vals.sh ./cluster/final_worker_vals.sh ./cluster/final_cluster_vals.sh
	rm -rf $(coredns_dir) $(terraform_dir) $(dnsmasq_dir) $(haproxy_dir) $(openshift_dir) $(matchbox_dir) upi-rt

dist-clean: clean
	rm -f $(matchbox_data_dir)