output "master_ips" {
  value = ["${local.master_public_ipv4}"]
}

output "bootstrap_ip" {
  value = "${local.bootstrap_public_ipv4}"
}

