variable "argocd_admin_password_hash" {
  type        = string
  description = "Hash encrypted string password for argocd administrator account"
}

variable "argocd_git_ssh_key" {
  type        = string
  description = "SSH key used for integration with git repository"
}

variable "subnets" {
  type = map(string)
  default = {
    subnet1 = "subnet-0b14d00177efa8b94"
    subnet2 = "subnet-0fa698a26c32f533e"
  }
}