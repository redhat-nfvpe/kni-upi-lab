resource "null_resource" "redfish_master" {
    count = var.enable_redfish ? var.master_count : 0

    provisioner "local-exec" {
        command = <<EOT
          redfishtool -r ${var.master_nodes[count.index]["ipmi_host"]} -u ${var.master_nodes[count.index]["ipmi_user"]} -p ${var.master_nodes[count.index]["ipmi_pass"]} Systems setBootOverride Once Pxe || true
          redfishtool -r ${var.master_nodes[count.index]["ipmi_host"]} -u ${var.master_nodes[count.index]["ipmi_user"]} -p ${var.master_nodes[count.index]["ipmi_pass"]} Systems reset On || redfishtool -r ${var.master_nodes[count.index]["ipmi_host"]} -u ${var.master_nodes[count.index]["ipmi_user"]} -p ${var.master_nodes[count.index]["ipmi_pass"]} Systems reset GracefulRestart || true
EOT
    }
}

resource "null_resource" "redfish_master_cleanup" {
    count = var.enable_redfish ? var.master_count : 0

    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          redfishtool -r ${var.master_nodes[count.index]["ipmi_host"]} -u ${var.master_nodes[count.index]["ipmi_user"]} -p ${var.master_nodes[count.index]["ipmi_pass"]} Systems reset ForceOff || true
EOT
    }
}