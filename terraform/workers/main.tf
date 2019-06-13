# ================MATCHBOX=====================

locals {
  kernel_args = [
    "console=tty0",
    "console=ttyS0,115200n8",
    "console=ttyS1,115200n8",
    "rd.neednet=1",

    # "rd.break=initqueue"
  ]

  worker_public_ipv4 = "${var.worker_public_ipv4}"
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
  name   = "${var.cluster_id}-worker"
  kernel = "${var.worker_kernel}"

  initrd = [
    "${var.worker_initrd}",
  ]

  args = flatten([
    "${local.kernel_args}",
    "inst.ks=${var.worker_kickstart}",
  ])

  raw_ignition = "${file(var.worker_ign_file)}"
}

resource "matchbox_group" "worker" {
  name    = "${var.cluster_id}-worker"
  profile = "${matchbox_profile.worker.name}"

  selector = {
    mac = "${var.worker_mac_address}"
  }
}


