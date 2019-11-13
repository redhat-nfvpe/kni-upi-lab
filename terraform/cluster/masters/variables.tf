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

variable "master_count" {
  type    = "string"
  default = "1"
}

variable "ignition_config_content" {
    type = "string"
}

variable "master_nodes" {
  type = list(map(string))
}

variable "enable_redfish" {
  description = "If set to true, uses redfish instead of IPMI"
  type = bool
  default = false
}