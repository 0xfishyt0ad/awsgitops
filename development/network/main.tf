####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "dev_network"
    provisioner  = "terraform"
    environment  = "dev"
  }
}

####################################################################################################
### Create network
####################################################################################################
module "dev" {
  source = "./v1"
  cidr_block = "10.10.0.0/16"
  facts      = local.facts
}

output "dev" {
  value       = module.dev
  description = "Network outputs of current environment"
}