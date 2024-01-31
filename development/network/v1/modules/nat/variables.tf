variable "vpc_id" {
  type        = string
  description = "ID of VPC"
}

variable "cidr_block" {
  type        = string
  description = "CIDR block of NAT gateway subnet"
}

variable "availability_zone" {
  type        = string
  description = "Availability zone of NAT gateway"
}

variable "region" {
  type        = string
  description = "AWS region name"
}

variable "route_table_id" {
  type        = string
  description = "ID of route table with IGW"
}

variable "vpc_peering_routes" {
  description = "Object containing values about VPC peering routes"
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
