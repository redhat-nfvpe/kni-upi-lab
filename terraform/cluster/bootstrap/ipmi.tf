resource "null_resource" "ipmi_bootstrap" {
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} chassis bootdev pxe;
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} power reset;
EOT
    }
}

