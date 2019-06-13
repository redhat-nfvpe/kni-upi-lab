resource "null_resource" "ipmi_worker" {
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${var.worker_ipmi_host} -U ${var.worker_ipmi_user} -P ${var.worker_ipmi_pass} chassis bootdev pxe;
          ipmitool -I lanplus -H ${var.worker_ipmi_host} -U ${var.worker_ipmi_user} -P ${var.worker_ipmi_pass} power reset;
EOT
    }
}

