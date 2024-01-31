variable "facts" {
  type = object({
    environment  = string
    workspace    = string
    provisioner  = string
    organization = string
  })

  description = "Basic facts used in module, all of them are used as tags"
}

variable "enable_control_plane_logging" {
  type        = bool
  default     = false
  description = "Enables logging of EKS control plane to cloudwatch group"
}