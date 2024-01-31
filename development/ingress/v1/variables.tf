variable "ingresses" {
  type = list(object({
    lb_name  = string
    hostname = string
    kind     = string
  }))
  description = "Object describing ingress mapping of LB name and hostname, standalone LB or via API Gateway"
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