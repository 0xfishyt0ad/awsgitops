variable "facts" {
  type = object({
    environment  = string
    workspace    = string
    provisioner  = string
    organization = string
  })

  description = "Basic facts used in module, all of them are used as tags"
}