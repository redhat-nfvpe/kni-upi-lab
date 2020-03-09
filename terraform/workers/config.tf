# ================COMMON=====================

variable "cluster_id" {
  type = "string"
}

variable "cluster_domain" {
  type = "string"
}

variable "nameserver" {
  type = "string"
  default = ""
}

variable "enable_redfish" {
  description = "If set to true, uses redfish instead of IPMI"
  type = bool
  default = false
}

# ================MATCHBOX=====================

variable "matchbox_rpc_endpoint" {
  type = "string"
}

variable "matchbox_http_endpoint" {
  type = "string"
}

variable "matchbox_trusted_ca_cert" {
  type    = "string"
  default = "matchbox/tls/ca.crt"
}

variable "matchbox_client_cert" {
  type    = "string"
  default = "matchbox/tls/client.crt"
}

variable "matchbox_client_key" {
  type    = "string"
  default = "matchbox/tls/client.key"
}

variable "worker_count" {
  type    = "string"
  default = "1"
}

variable "worker_nodes" {
  type = list(map(string))
}

variable "worker_ign_file" {
  type = "string"
}
