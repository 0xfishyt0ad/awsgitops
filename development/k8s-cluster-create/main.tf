####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "dev_k8s-cluster-create"
    provisioner  = "terraform"
    environment  = "dev"
  }
}

####################################################################################################
### Create Kubernetes cluster for current environment
####################################################################################################
module "dev" {
  source    = "./v1"
  facts     = local.facts
}

output "dev" {
  value       = module.dev
  description = "Cluster outputs of current environment"
}
