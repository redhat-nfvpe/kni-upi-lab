manifests := cluster/*.yaml cluster/*.src

dnsmasq_dir = ./dnsmasq
terraform_dir = ./terraform
coredns_dir = ./coredns
haproxy_dir = ./haproxy
openshift_dir = ./ocp
matchbox_dir = ./matchbox
matchbox_data_dir = ./matchbox-data
matchbox_etc_dir = $(matchbox_data_dir)/etc/matchbox
upi_rt_dir = ./upi-rt
build_dir = ./build

dnsmasq_prov_conf := $(dnsmasq_dir)/prov/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_bm_conf := $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.conf $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.hostsfile
haproxy_conf := $(haproxy_dir)/haproxy.cfg
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := $(coredns_dir)/Corefile
terraform_cluster := $(terraform_dir)/cluster/terraform.tfvars
terraform_worker := $(terraform_dir)/workers/terraform.tfvars
terraform_cluster_upi := $(upi_rt_dir)/terraform/cluster/terraform.tfvars
terraform_worker_upi := $(upi_rt_dir)/terraform/workers/terraform.tfvars
ignitions := $(openshift_dir)/worker.ign $(openshift_dir)/master.ign
matchbox_git := $(matchbox_dir)/.git
upi_rt_git := $(upi_rt_dir)/.git
matchbox-data-files := $(matchbox_etc_dir)/server/ca.crt
common_scripts := ./scripts/utils.sh ./scripts/cluster_map.sh 
kickstart_cfg := $(matchbox_data_dir)/var/lib/matchbox/assets/rhel8-worker-kickstart.cfg

terraform-bin := /usr/bin/terraform
openshift-bin := /usr/local/bin/openshift-install
openshift-oc := /usr/local/bin/oc
haproxy_container := $(haproxy_dir)/imageid

## => General <================================================================

## = all (default)           - Generate all configuration files
all: dns_conf haproxy-conf terraform-install matchbox matchbox-data upi-rt ignition kickstart terraform-conf
	echo "All config files generated and copied into their proper locations..."

## = cluster                 - Invoke terrafor to create cluster
#.PHONY: cluster
#cluster:#
#	cd $(upi_rt_dir)/terraform/cluster && terraform init
#	-cd $(upi_rt_dir)/terraform/cluster && terraform destroy --auto-approve 
#	cd $(upi_rt_dir)/terraform/cluster && terraform apply --auto-approve

## = clean                   - Remove all config files
clean: 
	rm -rf $(build_dir) $(coredns_dir) $(dnsmasq_dir) $(haproxy_dir) $(openshift_dir) 
	-./scripts/gen_config_prov.sh remove
	-./scripts/gen_config_bm.sh remove
	-./scripts/gen_haproxy.sh remove
	-./scripts/gen_coredns.sh remove
	-./scripts/gen_matchbox.sh remove


## = dist-clean              - Remove all config files and data files
dist-clean: clean
	rm -f $(matchbox_data_dir) $(matchbox_dir) upi-rt
## = help                    - Show this screen
.PHONY : help
help : Makefile
	@sed -n 's/^##//p' $<

dns_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)

## = upi-rt                  - Clone upi-rt repo
upi-rt: $(upi-rt_git)

$(upi_rt_git):
	git clone https://github.com/redhat-nfvpe/upi-rt.git

## => Matchbox <===============================================================
## = matchbox                - Install the Matchbox repo
## =
## = matchbox-con-stop         - Stop the dnsmasq-bm container
## = matchbox-con-start        - Start the dnsmasq-bm container (regen configs)
## = matchbox-con-remove       - Stop and remove the dnsmasq-bm container
## = matchbox-con-isrunning    - Check if dnsmasq-bm container is running
## =
matchbox-con-%: $(manifests) ./scripts/gen_matchbox.sh $(common_scripts)
	./scripts/gen_matchbox.sh $*

matchbox: $(matchbox_git)

$(matchbox_git):
	./scripts/gen_matchbox.sh repo

## = matchbox-data           - Generate data / config files for Matchbox
## =
matchbox-data: $(matchbox-data-files)

$(matchbox-data-files): $(manifests) ./scripts/gen_matchbox.sh 
	./scripts/gen_matchbox.sh data

## => Baremetal dnsmasq <======================================================
## = dns-bm-con-stop         - Stop the dnsmasq-bm container
## = dns-bm-con-start        - Start the dnsmasq-bm container (regen configs)
## = dns-bm-con-remove       - Stop and remove the dnsmasq-bm container
## = dns-bm-con-isrunning    - Check if dnsmasq-bm container is running
## =
dns-bm-con-%: ./scripts/gen_config_bm.sh dns-bm-conf $(common_scripts)
	./scripts/gen_config_bm.sh $*

## = dns-bm-conf             - Generate dnsmasq-bm configuration
## =
dns-bm-conf: $(dnsmasq_bm_conf)
$(dnsmasq_bm_conf): $(manifests) ./scripts/gen_config_bm.sh $(common_scripts)
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
$(dnsmasq_prov_conf): $(manifests) ./scripts/gen_config_prov.sh $(common_scripts)
	./scripts/gen_config_prov.sh

## => Misc dns <===========================================================
## = dns-conf                - Generate all dns config dnsmasq+coredns
## =
dns-conf:  $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)

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
$(coredns_conf): $(manifests) ./scripts/gen_coredns.sh $(common_scripts)
	./scripts/gen_coredns.sh all

## => Openshift <==============================================================
## = openshift-install       - Install openshift-install binary
openshift-install: $(openshift-bin)
## = openshift-oc            - Install the openshift command line tool
openshift-oc: $(openshift-oc)
## =
## => haproxy <================================================================
## = haproxy-conf            - Generate the haproxy config file
## =
## = haproxy-con-build       - Build the haproxy container
## = haproxy-con-stop        - Stop the dnsmasq-bm container
## = haproxy-con-start       - Start the dnsmasq-bm container
## = haproxy-con-remove      - Stop and remove the dnsmasq-bm container
## = haproxy-con-isrunning   - Check if dnsmasq-bm container is running
## =
haproxy-con-%: ./scripts/gen_haproxy.sh
	./scripts/gen_haproxy.sh $*

haproxy-conf: $(haproxy_conf)

$(haproxy_conf): $(manifests) ./scripts/gen_haproxy.sh $(common_scripts)
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
terraform-conf: $(terraform_cluster) $(terraform_worker) $(terraform_cluster_upi) $(terraform_worker_upi)
$(terraform_cluster): $(upi_rt_git) $(manifests) ./scripts/gen_terraform.sh ./scripts/cluster_map.sh ./scripts/network_conf.sh $(ignition) $(common_scripts)
	./scripts/gen_terraform.sh cluster

$(terraform_worker): $(upi_rt_git) $(manifests) ./scripts/gen_terraform.sh ./scripts/cluster_map.sh ./scripts/network_conf.sh $(ignition) $(common_scripts)
	./scripts/gen_terraform.sh workers

cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

## => Ignition Files <=========================================================
## = ignition                - Create the required ignition files
ignition: $(ignitions) 
## =
$(ignitions): $(manifests) ./scripts/gen_ignition.sh $(openshift-bin) $(common_scripts)
	./scripts/gen_ignition.sh

## => Kickstart Files <=========================================================
## = kickstart                - Create the required kickstart files
kickstart: $(kickstart_cfg)
##
$(kickstart_cfg): $(upi_rt_git) $(matchbox-data-files) $(manifests) $(ignitions) ./scripts/gen_kickstart.sh $(common_scripts)
	./scripts/gen_kickstart.sh kickstart

## => Container Management <===============================================================
## = con-stop         - Stop all containers
## = con-start        - Start all containers
## = con-remove       - Stop and remove all containers
## = con-isrunning    - Check if all containers are running
con-start:
con-%: all
	-./scripts/gen_config_prov.sh $*
	-./scripts/gen_config_bm.sh $*
	-./scripts/gen_haproxy.sh $*
	-./scripts/gen_coredns.sh $*
	-./scripts/gen_matchbox.sh $*
