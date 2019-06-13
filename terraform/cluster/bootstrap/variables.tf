variable "pxe_kernel" {
  type = "string"
}

variable "pxe_initrd" {
  type = "string"
}

variable "pxe_kernel_args" {
  type = "list"
}

variable "matchbox_http_endpoint" {
  type = "string"
}

variable "cluster_id" {
  type = "string"
}

variable "ignition_config_content" {
  type = "string"
}

variable "bootstrap_mac_address" {
  type = "string"
}

variable "bootstrap_ipmi_host" {
  type = "string"
}

variable "bootstrap_ipmi_user" {
  type = "string"
}

variable "bootstrap_ipmi_pass" {
  type = "string"
}
