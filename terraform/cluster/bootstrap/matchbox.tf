resource "matchbox_profile" "bootstrap" {
  name   = "${var.cluster_id}-bootstrap"
  kernel = "${var.pxe_kernel}"

  initrd = [
    "${var.pxe_initrd}",
  ]

  args = flatten([
    "${var.pxe_kernel_args}",
    "coreos.inst.install_dev=${var.install_dev}",
    "coreos.inst.ignition_url=${var.matchbox_http_endpoint}/ignition?mac=${var.bootstrap_mac_address}",
  ])

  raw_ignition = "${var.ignition_config_content}"
}

resource "matchbox_group" "bootstrap" {
  name    = "${var.cluster_id}-bootstrap"
  profile = "${matchbox_profile.bootstrap.name}"

  selector = {
    mac = "${var.bootstrap_mac_address}"
  }
}
