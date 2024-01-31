variable "name" {
  type        = string
  description = "Name of the API"
}

variable "domain" {
  type        = string
  description = "Domain name of the API"
}

variable "vpc_link_id" {
  type        = string
  description = "ID of the VPC Link"
}

variable "certificate_arn" {
  type = string
  description = "ARN of SSL certificate for API gateway"
}

variable "lb_name" {
  type = string
  description = "Name of the LB"
}

variable "zone_id" {
  type        = string
  description = "ID of domain zone"
}

variable "facts" {
  type = object({
    environment  = string
    workspace    = string
    provisioner  = string
    organization = string
  })
  description = "Basic facts used in module, all of them are used as tags"
}
