variable "lb_name" {
  type        = string
  description = "Prefix of name of LB created by K8s LB Controller"
}

variable "hostname" {
  type        = string
  description = "Desired hostname part of FQDN"
}

variable "zone_id" {
  type        = string
  description = "ID of domain zone"
}