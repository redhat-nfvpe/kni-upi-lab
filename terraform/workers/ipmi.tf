resource "null_resource" "ipmi_worker" {
    count = var.worker_count
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${var.worker_nodes[count.index]["ipmi_host"]} -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} chassis bootdev pxe;
          ipmitool -I lanplus -H ${var.worker_nodes[count.index]["ipmi_host"]} -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power cycle || ipmitool -I lanplus -H ${var.worker_nodes[count.index]["ipmi_host"]} -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power on;
EOT
    }
}

resource "null_resource" "ipmi_worker_clenup" {
    count = var.worker_count
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${var.worker_nodes[count.index]["ipmi_host"]} -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power off;
EOT
    }
}
