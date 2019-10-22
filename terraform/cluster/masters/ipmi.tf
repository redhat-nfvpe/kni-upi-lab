resource "null_resource" "ipmi_master" {
    count = var.master_count
    provisioner "local-exec" {
        working_dir = "../../../"
        command = "./scripts/oob_control.sh"
        environment = {
            IPMI_HOST = ${var.master_nodes[count.index]["ipmi_host"]}
            IPMI_USER = ${var.master_nodes[count.index]["ipmi_user"]}
            IPMI_PASSWORD = ${var.master_nodes[count.index]["ipmi_pass"]}

            HOST_NAME = ${var.master_nodes[count.index]["name"]}
            HOST_IP = ${var.master_nodes[count.index]["public_ipv4"]}
        }
        command = <<EOT
          ipmitool -I lanplus -H ${var.master_nodes[count.index]["ipmi_host"]} -U ${var.master_nodes[count.index]["ipmi_user"]} -P ${var.master_nodes[count.index]["ipmi_pass"]} chassis bootdev pxe;
          ipmitool -I lanplus -H ${var.master_nodes[count.index]["ipmi_host"]} -U ${var.master_nodes[count.index]["ipmi_user"]} -P ${var.master_nodes[count.index]["ipmi_pass"]} power cycle || ipmitool -I lanplus -H ${var.master_nodes[count.index]["ipmi_host"]} -U ${var.master_nodes[count.index]["ipmi_user"]} -P ${var.master_nodes[count.index]["ipmi_pass"]} power on;
EOT
    }
}

resource "null_resource" "ipmi_master_cleanup" {
    count = var.master_count
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${var.master_nodes[count.index]["ipmi_host"]} -U ${var.master_nodes[count.index]["ipmi_user"]} -P ${var.master_nodes[count.index]["ipmi_pass"]} power off;
EOT
    }
}
