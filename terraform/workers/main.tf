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
  kernel = "${var.worker_kernel}"

  initrd = [
    "${var.worker_initrd}",
  ]

  args = flatten([
    "${local.kernel_args}",
    "inst.ks=${var.worker_kickstart}",
  ])

}

resource "matchbox_group" "worker" {
  count = var.worker_count
  name    = var.worker_nodes[count.index]["name"]
  profile = "${matchbox_profile.worker[count.index]["name"]}"

  selector = {
    mac = "${var.worker_nodes[count.index]["mac_address"]}"
  }
}
