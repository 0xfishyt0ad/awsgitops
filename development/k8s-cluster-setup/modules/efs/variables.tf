variable "cluster_name" {
  type        = string
  description = "Cluster name"
}

variable "application_name" {
  type        = string
  description = "Name of application using efs volume"
}

variable "volume_size" {
  type        = string
  description = "Size of efs volume. Eg. 1Gi"
}

variable "subnets" {
  type        = map(string)
  description = "Set of subnets to be used when mounting efs target"
  default = {
    subnet1 = "id=subnet-0b14d00177efa8b94"
    subnet2 = "id=subnet-0fa698a26c32f533e"
  }
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