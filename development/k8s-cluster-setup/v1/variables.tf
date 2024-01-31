variable "cluster_name" {
  type        = string
  description = "Name of the cluster created in k8s-cluster-create workspace"
}

variable "argocd_admin_password_hash" {
  type        = string
  description = "Hash encrypted string password for argocd administrator account"
}

variable "argocd_git_ssh_key" {
  type        = string
  description = "SSH key used for integration with git repository"
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