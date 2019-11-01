# ================MATCHBOX=====================

locals {
  kernel_args = [
    "console=tty0",
    "console=ttyS0,115200n8",
    "console=ttyS1,115200n8",
    "rd.neednet=1",

    # "rd.break=initqueue"
  ]
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

resource "matchbox_profile" "worker" {
  count = var.worker_count
  name   = var.worker_nodes[count.index]["name"]
  kernel = var.worker_nodes[count.index]["kernel"]

  initrd = [
    var.worker_nodes[count.index]["initrd"]
  ]

  args = flatten([
    "${local.kernel_args}",
    (var.worker_nodes[count.index]["os_profile"] == "rhcos" ? "coreos.inst=yes coreos.inst.install_dev=${var.worker_nodes[count.index]["install_dev"]} coreos.inst.ignition_url=${var.matchbox_http_endpoint}/ignition?mac=${var.worker_nodes[count.index]["mac_address"]} coreos.inst.image_url=${var.worker_nodes[count.index]["pxe_os_image_url"]}" : "inst.ks=${var.worker_nodes[count.index]["kickstart"]}"),
    (lookup(var.worker_nodes[count.index], "provisioning_interface", "") != "" ? "ip=${var.worker_nodes[count.index]["provisioning_interface"]}:dhcp" : " "),
    (lookup(var.worker_nodes[count.index], "baremetal_interface", "") != "" ? "ip=${var.worker_nodes[count.index]["baremetal_interface"]}:dhcp" : " "),
    (lookup(var.master_nodes[count.index], "baremetal_interface", "") != "" || (lookup(var.master_nodes[count.index], "provisioning_interface", "") != "coreos.no_persist_ip" ? " "),
  ])

  raw_ignition= "${file(var.worker_ign_file)}"
}

resource "matchbox_group" "worker" {
  count = var.worker_count
  name    = var.worker_nodes[count.index]["name"]
  profile = "${matchbox_profile.worker[count.index]["name"]}"

  selector = {
    mac = "${var.worker_nodes[count.index]["mac_address"]}"
  }
}
