####################################################################################################
### Basic configuration
####################################################################################################
provider "aws" {
  region = "eu-central-1"
}

locals {
  facts = {
    organization = "org"
    workspace    = "dev_database"
    provisioner  = "terraform"
    environment  = "dev"
  }
}

####################################################################################################
### Create database for current environment
####################################################################################################
module "dev" {
  source    = "./v1"
  facts     = local.facts
}

output "dev" {
  value       = module.dev
  sensitive   = true
  description = "Database outputs of current environment"
}