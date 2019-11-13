resource "null_resource" "redfish_worker" {
    count = var.enable_redfish ? var.worker_count : 0

    provisioner "local-exec" {
        command = <<EOT
          redfishtool -r ${var.worker_nodes[count.index]["ipmi_host"]} -u ${var.worker_nodes[count.index]["ipmi_user"]} -p ${var.worker_nodes[count.index]["ipmi_pass"]} Systems setBootOverride Once Pxe
          redfishtool -r ${var.worker_nodes[count.index]["ipmi_host"]} -u ${var.worker_nodes[count.index]["ipmi_user"]} -p ${var.worker_nodes[count.index]["ipmi_pass"]} Systems reset GracefulRestart || redfishtool -r ${var.worker_nodes[count.index]["ipmi_host"]} -u ${var.worker_nodes[count.index]["ipmi_user"]} -p ${var.worker_nodes[count.index]["ipmi_pass"]} Systems reset On
EOT
    }
}

resource "null_resource" "redfish_worker_clenup" {
    count = var.enable_redfish ? var.worker_count : 0

    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          redfishtool -r ${var.worker_nodes[count.index]["ipmi_host"]} -u ${var.worker_nodes[count.index]["ipmi_user"]} -p ${var.worker_nodes[count.index]["ipmi_pass"]} Systems reset ForceOff
EOT
    }
}