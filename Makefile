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
dnsmasq_bm_conf := $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.conf $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.hostsfile
haproxy_conf := $(haproxy_dir)/haproxy.cfg
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := $(coredns_dir)/Corefile
terraform_cluster := $(terraform_dir)/cluster/terraform.tfvars
terraform_worker := $(terraform_dir)/workers/terraform.tfvars
ignitions := $(openshift_dir)/worker.ign $(openshift_dir)/master.ign
matchbox_git := $(matchbox_dir)/.git
upi-rt_git := $(upi-rt_dir)/.git
matchbox-data-files := $(matchbox_data_dir)/etc/matchbox/ca.cert

terraform-bin := /usr/bin/terraform
openshift-bin := /usr/local/bin/openshift-install
openshift-oc := /usr/local/bin/oc
haproxy_container := $(haproxy_dir)/imageid

## => General <================================================================
## = all (default)           - Generate all configuration files
all: dns_conf haproxy terraform matchbox matchbox-data upi-rt

## = clean                   - Remove all config files
clean:
	rm -f ./cluster/manifest_vals.sh ./cluster/final_worker_vals.sh ./cluster/final_cluster_vals.sh
	rm -rf $(coredns_dir) $(terraform_dir) $(dnsmasq_dir) $(haproxy_dir) $(openshift_dir) $(matchbox_dir) upi-rt

## = dist-clean              - Remove all config fiels and data files
dist-clean: clean
	rm -f $(matchbox_data_dir)
## = help                    - Show this screen
.PHONY : help
help : Makefile
	@sed -n 's/^##//p' $<

dns_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)

## = upi-rt                  - Clone upi-rt repo
.PHONY: upi-rt
upi-rt: $(upi-rt_git)

$(upi-rt_git):
	git clone https://github.com/redhat-nfvpe/upi-rt.git
## => Matchbox <===============================================================
## = matchbox                - Install the Matchbox repo
## =
matchbox: $(manifests) ./scripts/gen_matchbox.sh
	./scripts/gen_matchbox.sh repo

## = matchbox-data           - Generate data / config files for Matchbox
## =
matchbox-data: $(matchbox-data-files)

$(matchbox-data-files): $(manifests) ./scripts/gen_matchbox.sh matchbox
	./scripts/gen_matchbox.sh data

## => Baremetal dnsmasq <======================================================
## = dns-bm-con-stop         - Stop the dnsmasq-bm container
## = dns-bm-con-start        - Start the dnsmasq-bm container (regen configs)
## = dns-bm-con-remove       - Stop and remove the dnsmasq-bm container
## = dns-bm-con-isrunning    - Check if dnsmasq-bm container is running
## =
dns-bm-con-%: ./scripts/gen_config_bm.sh
	./scripts/gen_config_bm.sh $*

## = dns-bm-conf             - Generate dnsmasq-bm configuration
## =
dns-bm-conf: $(dnsmasq_bm_conf)
$(dnsmasq_bm_conf): $(manifests) ./scripts/gen_config_bm.sh
	./scripts/gen_config_bm.sh bm

## => Provisioning dnsmasq <===================================================
## = dns-prov-con-stop       - Stop the dnsmasq-bm container
## = dns-prov-con-start      - Start the dnsmasq-bm container (regen configs)
## = dns-prov-con-remove     - Stop and remove the dnsmasq-bm container
## = dns-prov-con-isrunning  - Check if dnsmasq-bm container is running
## =
dns-prov-con-%: ./scripts/gen_config_bm.sh
	./scripts/gen_config_prov.sh $*

## = dns-prov-conf           - Generate dnsmasq-prov configuration
## =
dns-prov-conf: $(dnsmasq_prov_conf)
$(dnsmasq_prov_conf): $(manifests) ./scripts/gen_config_prov.sh
	./scripts/gen_config_prov.sh
## => Misc dnsmasq <===========================================================
## = dns-conf                - Generate config files for BM and PROV network
## =
dns-conf:  $(dnsmasq_prov_conf) $(dnsmasq_bm_conf)

## => Coredns <================================================================
## = dns-core-con-stop       - Stop the dnsmasq-bm container
## = dns-core-con-start      - Start the dnsmasq-bm container
## = dns-core-con-remove     - Stop and remove the dnsmasq-bm container
## = dns-core-con-isrunning  - Check if dnsmasq-bm container is running
## =
dns-core-con-%: ./scripts/gen_coredns.sh
	./scripts/gen_coredns.sh $*

## = dns-core-conf           - Make coredns Corefile and database
## =
dns-core-conf: $(coredns_conf)
$(coredns_conf): $(manifests) ./scripts/gen_coredns.sh
	./scripts/gen_coredns.sh all

## => Openshift <==============================================================
## = openshift-install       - Install openshift-install binary
openshift-install: $(openshift-bin)
## = openshift-oc            - Install the openshift command line tool
openshift-oc: $(openshift-oc)
## =
## => haproxy <================================================================
## = haproxy                 - Generate haproxy config and container image
haproxy: $(haproxy_container)

$(haproxy_container): $(haproxy_conf)
	./scripts/gen_haproxy.sh build

$(haproxy_conf): $(manifests) ./scripts/gen_haproxy.sh
	./scripts/gen_haproxy.sh gen-config


$(openshift-oc):
	./scripts/gen_ignition.sh oc

$(openshift-bin):
	./scripts/gen_ignition.sh installer

## => terraform <==============================================================
## = terraform-install       - Install the Terraform binary
terraform-install: $(terraform-bin)

$(terraform-bin):
	./scripts/gen_terraform.sh install

## = terraform-conf       - Generate the Terraform config files
## =
terraform-conf: $(terraform_cluster) $(terraform_worker)
$(terraform_cluster): $(manifests) ./scripts/cluster_map.sh ./scripts/network_conf.sh $(ignition)
	./scripts/gen_terraform.sh all
$(terraform_worker): $(manifests) ./scripts/cluster_map.sh ./scripts/network_conf.sh $(ignition)
	./scripts/gen_terraform.sh all

cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

## => Ignition Files <=========================================================
## = ignition                - Create the required ignition files
ignition: $(ignitions) 
##
$(ignitions): $(manifests) ./scripts/gen_ignition.sh openshift-install
	./scripts/gen_ignition.sh

