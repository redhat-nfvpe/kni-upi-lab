locals {
  bootstrap_img = "/var/lib/libvirt/images/bootstrap.img"
  bootstrap_img_size = "800G"
}
data "template_file" "vm_bootstrap" {
    template = file("bootstrap/templates/bootstrap_vm.tpl")
    vars =  {
      name                  = "${var.cluster_id}-bootstrap"
      memory_gb             = "${var.memory_gb}"
      vcpu                  = "${var.vcpu}"
      bootstrap_img         = "${local.bootstrap_img}"
      provisioning_bridge   = "${var.provisioning_bridge}"
      baremetal_bridge      = "${var.baremetal_bridge}"
      bootstrap_mac_address = "${var.bootstrap_mac_address}"
    }
}

resource "local_file" "vm_bootstrap" {
  content = "${data.template_file.vm_bootstrap.rendered}"
  filename = "/tmp/${var.cluster_id}-bootstrap-vm.xml"
}

resource "null_resource" "vm_bootstrap" {
    provisioner "local-exec" {
        command = <<EOT
rm -f ${local.bootstrap_img} || true
qemu-img create -f qcow2 ${local.bootstrap_img} ${local.bootstrap_img_size}
chown qemu:qemu ${local.bootstrap_img}
virsh create /tmp/${var.cluster_id}-bootstrap-vm.xml
EOT
    }
    depends_on = [local_file.vm_bootstrap]
}

resource "null_resource" "vm_bootstrap_destroy" {
    provisioner "local-exec" {
        when = "destroy"
        command = <<EOT
virsh destroy ${var.cluster_id}-bootstrap
EOT
    }
}
