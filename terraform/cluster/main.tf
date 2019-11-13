# ================MATCHBOX=====================

locals {
  kernel_args = [
    "console=tty0",
    "console=ttyS0,115200n8",
    "console=ttyS1,115200n8",
    "rd.neednet=1",
    "nameserver=${var.nameserver}",

    # "rd.break=initqueue"
    "coreos.inst=yes",

    "coreos.inst.image_url=${var.pxe_os_image_url}",
  ]

  pxe_kernel = "${var.pxe_kernel_url}"
  pxe_initrd = "${var.pxe_initrd_url}"

  bootstrap_public_ipv4 = "${var.bootstrap_public_ipv4}"
}

provider "matchbox" {
  endpoint    = "${var.matchbox_rpc_endpoint}"
  client_cert = "${file(var.matchbox_client_cert)}"
  client_key  = "${file(var.matchbox_client_key)}"
  ca          = "${file(var.matchbox_trusted_ca_cert)}"
}

resource "matchbox_profile" "default" {
  name = "${var.cluster_id}"
}

resource "matchbox_group" "default" {
  name    = "${var.cluster_id}"
  profile = "${matchbox_profile.default.name}"
}

# ==============MASTERS===================
module "masters" {
  source = "./masters"

  pxe_kernel_args = "${local.kernel_args}"

  master_count            = "${var.master_count}"
  master_nodes            = "${var.master_nodes}"
  pxe_kernel              = "${local.pxe_kernel}"
  pxe_initrd              = "${local.pxe_initrd}"
  matchbox_http_endpoint  = "${var.matchbox_http_endpoint}"
  ignition_config_content = "${file(var.master_ign_file)}"

  cluster_id = "${var.cluster_id}"

  enable_redfish = var.enable_redfish
}

# ==============BOOTSTRAP=================

module "bootstrap" {
  source = "./bootstrap"

  pxe_kernel_args = "${concat([
    (var.bootstrap_provisioning_interface != "" ? "ip=${var.bootstrap_provisioning_interface}:dhcp" : " "),
    (var.bootstrap_baremetal_interface != "" ? "ip=${var.bootstrap_baremetal_interface}:dhcp" : " "),
  ], local.kernel_args)}"

  pxe_kernel             = "${local.pxe_kernel}"
  pxe_initrd             = "${local.pxe_initrd}"
  matchbox_http_endpoint = "${var.matchbox_http_endpoint}"
  bootstrap_mac_address  = "${var.bootstrap_mac_address}"
  ignition_config_content = "${file(var.bootstrap_ign_file)}"

  cluster_id          = "${var.cluster_id}"
  memory_gb           = "${var.bootstrap_memory_gb}"
  vcpu                = "${var.bootstrap_vcpu}"
  provisioning_bridge = "${var.bootstrap_provisioning_bridge}"
  baremetal_bridge    = "${var.bootstrap_baremetal_bridge}"
  install_dev         = "${var.bootstrap_install_dev}"
}
