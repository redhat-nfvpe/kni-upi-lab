resource "null_resource" "ipmi_worker" {
    count = var.enable_redfish ? 0 : var.worker_count
    
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} chassis bootdev pxe;
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power cycle || ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power on;
EOT
    }
}

resource "null_resource" "ipmi_worker_clenup" {
    count = var.enable_redfish ? 0 : var.worker_count

    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power off;
EOT
    }
}
