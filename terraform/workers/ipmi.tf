resource "null_resource" "ipmi_worker" {
    count = var.virtual_workers == "true" ? 0 : var.worker_count
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} chassis bootdev pxe;
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power cycle || ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power on;
EOT
    }
}

resource "null_resource" "ipmi_virtual_worker" {
    count = var.virtual_workers == "true" ? var.worker_count : 0
    provisioner "local-exec" {
        command = <<EOT
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} chassis bootdev pxe;
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power off || ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power on;
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power on;
          sleep 3;
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} chassis bootdev disk;
EOT
    }
}

resource "null_resource" "ipmi_worker_clenup" {
    count = var.worker_count
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
          ipmitool -I lanplus -H ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),0)} %{if element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)!=var.worker_nodes[count.index]["ipmi_host"]}-p ${element(split(":", var.worker_nodes[count.index]["ipmi_host"]),1)}%{ endif } -U ${var.worker_nodes[count.index]["ipmi_user"]} -P ${var.worker_nodes[count.index]["ipmi_pass"]} power off;
EOT
    }
}
