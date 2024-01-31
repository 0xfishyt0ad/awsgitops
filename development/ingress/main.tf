####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "env_ingress"
    provisioner  = "terraform"
  }
}

####################################################################################################
### Create APIs for each environment
####################################################################################################
module "dev" {
  source    = "./v1"

  ingresses = [
    {
      lb_name  = "k8s-argocd-argocdse-7913666486"
      hostname = "argocd"
      kind     = "lb"
    }
  ]

  facts = merge({environment = "dev"}, local.facts)
}
