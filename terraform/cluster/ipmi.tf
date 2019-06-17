resource "null_resource" "ipmi_master" {
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} chassis bootdev pxe;
          ipmitool -I lanplus -H ${var.master_ipmi_host} -U ${var.master_ipmi_user} -P ${var.master_ipmi_pass} power cycle;
EOT
    }
}

resource "null_resource" "ipmi_master_cleanup" {
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${var.bootstrap_ipmi_host} -U ${var.bootstrap_ipmi_user} -P ${var.bootstrap_ipmi_pass} power off;
EOT
    }
}
