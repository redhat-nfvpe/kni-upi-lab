resource "null_resource" "ipmi_bootstrap" {
    provisioner "local-exec" {
        command = <<EOT
          rm -f /var/lib/libvirt/images/bootstrap.img || true
          qemu-img create -f qcow2 /var/lib/libvirt/images/bootstrap.img 800G
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} power cycle || ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} power on;
EOT
    }
}

resource "null_resource" "ipmi_bootstrap_cleanup" {
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} power off;
EOT
    }
}
